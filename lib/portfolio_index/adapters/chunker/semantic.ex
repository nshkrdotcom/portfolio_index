defmodule PortfolioIndex.Adapters.Chunker.Semantic do
  @moduledoc """
  Semantic chunker that groups text by embedding similarity.

  Implements the `PortfolioCore.Ports.Chunker` behaviour.

  ## Strategy

  Uses cosine similarity between sentence embeddings to determine
  chunk boundaries:
  1. Split text into sentences
  2. Generate embedding for each sentence
  3. Calculate cosine similarity between adjacent sentences
  4. Start new chunk when similarity drops below threshold
  5. Respect max_chars limit
  6. Track byte positions

  ## Example

      config = %{
        threshold: 0.75,
        max_chars: 1000,
        embedding_fn: fn text ->
          {:ok, %{vector: embedding}}
        end
      }
      {:ok, chunks} = Semantic.chunk(text, :semantic, config)

  ## Options

  - `:threshold` - Similarity threshold for grouping (default: 0.75)
  - `:max_chars` - Maximum characters per chunk (default: 1000)
  - `:min_sentences` - Minimum sentences per chunk (default: 2)
  - `:embedding_fn` - Function to generate embeddings (required)
  - `:get_chunk_size` - Function to measure size (default: `&String.length/1`)

  ## Token-Based Chunking

      config = %{
        max_chars: 256,
        embedding_fn: &my_embedding_fn/1,
        get_chunk_size: &MyTokenizer.count_tokens/1
      }
      {:ok, chunks} = Semantic.chunk(text, :semantic, config)
  """

  @behaviour PortfolioCore.Ports.Chunker

  alias PortfolioIndex.Adapters.Chunker.Tokens

  require Logger

  @default_threshold 0.75
  @default_max_chars 1000
  @default_min_sentences 2

  @impl true
  @spec chunk(String.t(), atom(), map()) :: {:ok, [map()]} | {:error, term()}
  def chunk(text, _format, config) do
    threshold = config[:threshold] || @default_threshold
    max_chars = config[:max_chars] || @default_max_chars
    min_sentences = config[:min_sentences] || @default_min_sentences
    embedding_fn = config[:embedding_fn]
    get_chunk_size = config[:get_chunk_size] || (&String.length/1)

    cond do
      String.trim(text) == "" ->
        {:ok, []}

      is_nil(embedding_fn) ->
        {:error, :no_embedding_fn}

      true ->
        do_semantic_chunk(text, threshold, max_chars, min_sentences, embedding_fn, get_chunk_size)
    end
  end

  @impl true
  @spec estimate_chunks(String.t(), map()) :: non_neg_integer()
  def estimate_chunks(text, config) do
    max_chars = config[:max_chars] || @default_max_chars
    get_chunk_size = config[:get_chunk_size] || (&String.length/1)

    # Estimate based on text size and max_chars
    text_size = get_chunk_size.(text)

    if text_size <= max_chars do
      1
    else
      div(text_size, max_chars) + 1
    end
  end

  # Private functions

  @spec do_semantic_chunk(
          String.t(),
          float(),
          pos_integer(),
          pos_integer(),
          function(),
          function()
        ) ::
          {:ok, [map()]} | {:error, term()}
  defp do_semantic_chunk(text, threshold, max_chars, min_sentences, embedding_fn, get_chunk_size) do
    sentences = split_into_sentences(text)

    if length(sentences) <= min_sentences do
      # Not enough sentences to chunk, return as single chunk
      {:ok, [build_single_chunk(text, 0)]}
    else
      case generate_embeddings(sentences, embedding_fn) do
        {:ok, embeddings} ->
          chunks =
            group_by_similarity(
              sentences,
              embeddings,
              threshold,
              max_chars,
              min_sentences,
              get_chunk_size
            )

          positioned_chunks = add_positions(text, chunks)
          {:ok, positioned_chunks}

        {:error, reason} ->
          Logger.warning(
            "Embedding generation failed: #{inspect(reason)}, falling back to size-based chunking"
          )

          # Fallback to simple size-based chunking
          {:ok, fallback_chunk(text, max_chars, get_chunk_size)}
      end
    end
  end

  @spec split_into_sentences(String.t()) :: [String.t()]
  defp split_into_sentences(text) do
    # Split on sentence boundaries
    ~r/(?<=[.!?])\s+(?=[A-Z\d"])/
    |> Regex.split(text, include_captures: false)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  @spec generate_embeddings([String.t()], function()) :: {:ok, [[float()]]} | {:error, term()}
  defp generate_embeddings(sentences, embedding_fn) do
    results =
      sentences
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, []}, fn {sentence, _idx}, {:ok, acc} ->
        case embedding_fn.(sentence) do
          {:ok, %{vector: vector}} when is_list(vector) ->
            {:cont, {:ok, [vector | acc]}}

          {:ok, vector} when is_list(vector) ->
            {:cont, {:ok, [vector | acc]}}

          {:error, reason} ->
            {:halt, {:error, reason}}

          other ->
            {:halt, {:error, {:invalid_embedding, other}}}
        end
      end)

    case results do
      {:ok, embeddings} -> {:ok, Enum.reverse(embeddings)}
      error -> error
    end
  end

  @spec group_by_similarity(
          [String.t()],
          [[float()]],
          float(),
          pos_integer(),
          pos_integer(),
          function()
        ) :: [
          [String.t()]
        ]
  defp group_by_similarity(
         sentences,
         embeddings,
         threshold,
         max_chars,
         min_sentences,
         get_chunk_size
       ) do
    sentences_with_embeddings = Enum.zip(sentences, embeddings)

    {groups, current_group, _final_len} =
      sentences_with_embeddings
      |> Enum.with_index()
      |> Enum.reduce({[], [], 0}, fn {{sentence, embedding}, _idx},
                                     {groups, current_group, current_len} ->
        sentence_size = get_chunk_size.(sentence)

        cond do
          # First sentence
          current_group == [] ->
            {groups, [{sentence, embedding}], sentence_size}

          # Would exceed max_chars
          current_len + sentence_size + 1 > max_chars and length(current_group) >= min_sentences ->
            {[extract_sentences(current_group) | groups], [{sentence, embedding}], sentence_size}

          # Check similarity with previous sentence
          true ->
            {_prev_sentence, prev_embedding} = List.last(current_group)
            similarity = cosine_similarity(prev_embedding, embedding)

            if similarity < threshold and length(current_group) >= min_sentences do
              # Low similarity, start new group
              {[extract_sentences(current_group) | groups], [{sentence, embedding}],
               sentence_size}
            else
              # High similarity or min_sentences not reached, continue group
              {groups, current_group ++ [{sentence, embedding}], current_len + sentence_size + 1}
            end
        end
      end)

    # Don't forget the last group
    final_groups =
      if current_group != [] do
        [extract_sentences(current_group) | groups]
      else
        groups
      end

    Enum.reverse(final_groups)
  end

  @spec extract_sentences([{String.t(), [float()]}]) :: [String.t()]
  defp extract_sentences(group) do
    Enum.map(group, &elem(&1, 0))
  end

  @spec cosine_similarity([float()], [float()]) :: float()
  defp cosine_similarity(vec1, vec2) when length(vec1) == length(vec2) do
    dot_product = dot(vec1, vec2)
    magnitude1 = magnitude(vec1)
    magnitude2 = magnitude(vec2)

    if magnitude1 == 0 or magnitude2 == 0 do
      0.0
    else
      dot_product / (magnitude1 * magnitude2)
    end
  end

  defp cosine_similarity(_vec1, _vec2), do: 0.0

  @spec dot([float()], [float()]) :: float()
  defp dot(vec1, vec2) do
    vec1
    |> Enum.zip(vec2)
    |> Enum.reduce(0.0, fn {a, b}, acc -> acc + a * b end)
  end

  @spec magnitude([float()]) :: float()
  defp magnitude(vec) do
    vec
    |> Enum.reduce(0.0, fn x, acc -> acc + x * x end)
    |> :math.sqrt()
  end

  @spec add_positions(String.t(), [[String.t()]]) :: [map()]
  defp add_positions(text, groups) do
    {chunks, _} =
      groups
      |> Enum.with_index()
      |> Enum.reduce({[], 0}, fn {sentences, idx}, {acc, search_start} ->
        content = Enum.join(sentences, " ")

        {start_byte, end_byte} = find_chunk_position(text, content, search_start)

        chunk = %{
          content: content,
          index: idx,
          start_byte: start_byte,
          end_byte: end_byte,
          start_offset: start_byte,
          end_offset: end_byte,
          metadata: %{
            strategy: :semantic,
            char_count: String.length(content),
            token_count: Tokens.estimate(content),
            sentence_count: length(sentences)
          }
        }

        {[chunk | acc], end_byte}
      end)

    Enum.reverse(chunks)
  end

  @spec find_chunk_position(String.t(), String.t(), non_neg_integer()) ::
          {non_neg_integer(), non_neg_integer()}
  defp find_chunk_position(text, content, search_start) do
    # Try to find the first sentence of the content in the remaining text
    first_sentence = content |> String.split(~r/[.!?]\s+/) |> List.first() || content

    remaining =
      if search_start < byte_size(text) do
        binary_part(text, search_start, byte_size(text) - search_start)
      else
        ""
      end

    case :binary.match(remaining, first_sentence) do
      {relative_start, _} ->
        start_byte = search_start + relative_start
        end_byte = start_byte + byte_size(content)
        {start_byte, min(end_byte, byte_size(text))}

      :nomatch ->
        # Fallback to search_start
        {search_start, min(search_start + byte_size(content), byte_size(text))}
    end
  end

  @spec build_single_chunk(String.t(), non_neg_integer()) :: map()
  defp build_single_chunk(text, index) do
    %{
      content: text,
      index: index,
      start_byte: 0,
      end_byte: byte_size(text),
      start_offset: 0,
      end_offset: byte_size(text),
      metadata: %{
        strategy: :semantic,
        char_count: String.length(text),
        token_count: Tokens.estimate(text),
        sentence_count: count_sentences(text)
      }
    }
  end

  @spec fallback_chunk(String.t(), pos_integer(), function()) :: [map()]
  defp fallback_chunk(text, max_chars, get_chunk_size) do
    # Simple fallback: split by size at sentence boundaries
    sentences = split_into_sentences(text)

    {groups, current, _current_len} =
      Enum.reduce(sentences, {[], [], 0}, fn sentence, {groups, current, current_len} ->
        sentence_size = get_chunk_size.(sentence)

        if current_len + sentence_size + 1 > max_chars and current != [] do
          {[Enum.reverse(current) | groups], [sentence], sentence_size}
        else
          sep = if current == [], do: 0, else: 1
          {groups, [sentence | current], current_len + sentence_size + sep}
        end
      end)

    final_groups =
      if current != [] do
        [Enum.reverse(current) | groups]
      else
        groups
      end

    final_groups
    |> Enum.reverse()
    |> Enum.with_index()
    |> Enum.map(fn {sentences, idx} ->
      content = Enum.join(sentences, " ")

      %{
        content: content,
        index: idx,
        start_byte: 0,
        end_byte: byte_size(content),
        start_offset: 0,
        end_offset: byte_size(content),
        metadata: %{
          strategy: :semantic,
          char_count: String.length(content),
          token_count: Tokens.estimate(content),
          sentence_count: length(sentences),
          fallback: true
        }
      }
    end)
  end

  @spec count_sentences(String.t()) :: non_neg_integer()
  defp count_sentences(text) do
    text
    |> split_into_sentences()
    |> length()
  end
end
