defmodule PortfolioIndex.Adapters.Chunker.Sentence do
  @moduledoc """
  Sentence-based text chunker with NLP tokenization.

  Implements the `PortfolioCore.Ports.Chunker` behaviour.

  ## Strategy

  Splits text on sentence boundaries using regex-based detection:
  1. Detect sentence boundaries (. ! ? with following space/newline)
  2. Group sentences to reach target chunk size
  3. Add overlap from previous chunk
  4. Track byte positions for each chunk

  ## Example

      config = %{chunk_size: 1000, chunk_overlap: 200}
      {:ok, chunks} = Sentence.chunk(text, :plain, config)
  """

  @behaviour PortfolioCore.Ports.Chunker

  @default_chunk_size 1000
  @default_chunk_overlap 200

  # Sentence ending patterns
  @sentence_pattern ~r/(?<=[.!?])(?:\s+|$)(?=[A-Z\d"]|$)/

  @impl true
  @spec chunk(String.t(), atom(), map()) :: {:ok, [map()]} | {:error, term()}
  def chunk(text, _format, config) do
    chunk_size = config[:chunk_size] || @default_chunk_size
    chunk_overlap = config[:chunk_overlap] || @default_chunk_overlap

    if String.trim(text) == "" do
      {:ok, []}
    else
      sentences = split_into_sentences(text)
      sentences_with_positions = calculate_sentence_positions(text, sentences)
      chunks = group_sentences(sentences_with_positions, chunk_size, chunk_overlap)

      result =
        chunks
        |> Enum.with_index()
        |> Enum.map(fn {{content, start_byte, end_byte, sentence_count}, index} ->
          %{
            content: content,
            index: index,
            start_byte: start_byte,
            end_byte: end_byte,
            start_offset: start_byte,
            end_offset: end_byte,
            metadata: %{
              strategy: :sentence,
              char_count: String.length(content),
              sentence_count: sentence_count
            }
          }
        end)

      {:ok, result}
    end
  end

  @impl true
  @spec estimate_chunks(String.t(), map()) :: non_neg_integer()
  def estimate_chunks(text, config) do
    chunk_size = config[:chunk_size] || @default_chunk_size

    sentence_count = count_sentences(text)

    avg_sentence_length =
      if sentence_count > 0, do: div(String.length(text), sentence_count), else: 50

    sentences_per_chunk = max(div(chunk_size, avg_sentence_length), 1)
    div(sentence_count, sentences_per_chunk) + 1
  end

  # Private functions

  @spec split_into_sentences(String.t()) :: [String.t()]
  defp split_into_sentences(text) do
    # Split on sentence boundaries
    # Handle abbreviations, quotes, and other edge cases
    processed = handle_abbreviations(text)

    Regex.split(@sentence_pattern, processed, include_captures: false)
    |> Enum.map(&restore_abbreviations/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  @spec handle_abbreviations(String.t()) :: String.t()
  defp handle_abbreviations(text) do
    # Replace common abbreviations to prevent false sentence splits
    text
    |> String.replace(~r/\b(Mr|Mrs|Ms|Dr|Prof|Sr|Jr|vs|etc|i\.e|e\.g)\./i, "\\1\x00")
    |> String.replace(~r/\b([A-Z])\.(?=[A-Z]\.)/i, "\\1\x00")
  end

  @spec restore_abbreviations(String.t()) :: String.t()
  defp restore_abbreviations(text) do
    String.replace(text, "\x00", ".")
  end

  @spec calculate_sentence_positions(String.t(), [String.t()]) :: [
          {String.t(), non_neg_integer(), non_neg_integer()}
        ]
  defp calculate_sentence_positions(text, sentences) do
    {result, _} =
      Enum.reduce(sentences, {[], 0}, fn sentence, {acc, search_start} ->
        # Find this sentence in the remaining text
        remaining = binary_part(text, search_start, byte_size(text) - search_start)

        case find_sentence_in_text(remaining, sentence) do
          {relative_start, sentence_bytes} ->
            absolute_start = search_start + relative_start
            absolute_end = absolute_start + sentence_bytes
            # Move search position past this sentence
            new_search_start = absolute_end
            {[{sentence, absolute_start, absolute_end} | acc], new_search_start}

          :not_found ->
            # Fallback: just use current position
            sentence_bytes = byte_size(sentence)

            {[{sentence, search_start, search_start + sentence_bytes} | acc],
             search_start + sentence_bytes}
        end
      end)

    Enum.reverse(result)
  end

  @spec find_sentence_in_text(String.t(), String.t()) ::
          {non_neg_integer(), non_neg_integer()} | :not_found
  defp find_sentence_in_text(text, sentence) do
    # Try exact match first
    trimmed = String.trim(sentence)

    case :binary.match(text, trimmed) do
      {start, len} -> {start, len}
      :nomatch -> :not_found
    end
  end

  @spec group_sentences(
          [{String.t(), non_neg_integer(), non_neg_integer()}],
          pos_integer(),
          non_neg_integer()
        ) ::
          [{String.t(), non_neg_integer(), non_neg_integer(), non_neg_integer()}]
  defp group_sentences(sentences, chunk_size, overlap) do
    {chunks, current_sentences, _current_len, current_start} =
      Enum.reduce(sentences, {[], [], 0, 0}, fn {sentence, start_byte, end_byte},
                                                {chunks, current_sentences, current_len,
                                                 current_start} ->
        sentence_len = String.length(sentence)
        separator_len = if current_sentences == [], do: 0, else: 1

        cond do
          # Current is empty, start with this sentence
          current_sentences == [] ->
            {chunks, [{sentence, start_byte, end_byte}], sentence_len, start_byte}

          # Adding would exceed chunk size
          current_len + separator_len + sentence_len > chunk_size ->
            # Finalize current chunk
            chunk = finalize_chunk(current_sentences, current_start)
            # Get overlap sentences
            overlap_sentences = get_overlap_sentences(current_sentences, overlap)

            overlap_start =
              if overlap_sentences == [], do: start_byte, else: elem(hd(overlap_sentences), 1)

            overlap_len =
              overlap_sentences |> Enum.map(fn {s, _, _} -> String.length(s) end) |> Enum.sum()

            {
              [chunk | chunks],
              overlap_sentences ++ [{sentence, start_byte, end_byte}],
              overlap_len + sentence_len + length(overlap_sentences),
              overlap_start
            }

          # Add to current chunk
          true ->
            {
              chunks,
              current_sentences ++ [{sentence, start_byte, end_byte}],
              current_len + separator_len + sentence_len,
              current_start
            }
        end
      end)

    # Finalize last chunk
    final_chunks =
      if current_sentences != [] do
        [finalize_chunk(current_sentences, current_start) | chunks]
      else
        chunks
      end

    Enum.reverse(final_chunks)
  end

  @spec finalize_chunk([{String.t(), non_neg_integer(), non_neg_integer()}], non_neg_integer()) ::
          {String.t(), non_neg_integer(), non_neg_integer(), non_neg_integer()}
  defp finalize_chunk(sentences, start) do
    content = Enum.map_join(sentences, " ", &elem(&1, 0))
    {_last_sentence, _last_start, last_end} = List.last(sentences)
    {content, start, last_end, length(sentences)}
  end

  @spec get_overlap_sentences(
          [{String.t(), non_neg_integer(), non_neg_integer()}],
          non_neg_integer()
        ) ::
          [{String.t(), non_neg_integer(), non_neg_integer()}]
  defp get_overlap_sentences(_sentences, overlap) when overlap <= 0, do: []

  defp get_overlap_sentences(sentences, overlap) do
    sentences
    |> Enum.reverse()
    |> take_sentences_for_overlap(overlap, [])
  end

  @type sentence_tuple :: {String.t(), non_neg_integer(), non_neg_integer()}

  @spec take_sentences_for_overlap([sentence_tuple()], non_neg_integer(), [sentence_tuple()]) ::
          [sentence_tuple()]
  defp take_sentences_for_overlap([], _remaining, acc), do: acc

  defp take_sentences_for_overlap([{sentence, start, ending} | rest], remaining, acc) do
    sentence_len = String.length(sentence)

    if sentence_len <= remaining do
      take_sentences_for_overlap(rest, remaining - sentence_len - 1, [
        {sentence, start, ending} | acc
      ])
    else
      acc
    end
  end

  @spec count_sentences(String.t()) :: non_neg_integer()
  defp count_sentences(text) do
    text
    |> split_into_sentences()
    |> length()
  end
end
