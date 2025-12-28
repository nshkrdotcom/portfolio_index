defmodule PortfolioIndex.Adapters.Chunker.Character do
  @moduledoc """
  Character-based text chunker with smart boundary handling.

  Implements the `PortfolioCore.Ports.Chunker` behaviour.

  ## Strategy

  Splits text at character boundaries with optional word/sentence preservation:
  - `:word` - Never split in the middle of a word (default)
  - `:sentence` - Try to split at sentence boundaries
  - `:none` - Split exactly at character count

  ## Example

      config = %{chunk_size: 500, chunk_overlap: 100, boundary: :word}
      {:ok, chunks} = Character.chunk(text, :plain, config)
  """

  @behaviour PortfolioCore.Ports.Chunker

  @default_chunk_size 1000
  @default_chunk_overlap 200

  @type boundary :: :word | :sentence | :none

  @impl true
  @spec chunk(String.t(), atom(), map()) :: {:ok, [map()]} | {:error, term()}
  def chunk(text, _format, config) do
    chunk_size = config[:chunk_size] || @default_chunk_size
    chunk_overlap = config[:chunk_overlap] || @default_chunk_overlap
    boundary = config[:boundary] || :word

    if String.trim(text) == "" do
      {:ok, []}
    else
      chunks = split_with_boundary(text, chunk_size, chunk_overlap, boundary)

      result =
        chunks
        |> Enum.with_index()
        |> Enum.map(fn {content, index} ->
          {start_byte, end_byte} = calculate_byte_positions(text, content, index, chunks)

          %{
            content: content,
            index: index,
            start_byte: start_byte,
            end_byte: end_byte,
            start_offset: start_byte,
            end_offset: end_byte,
            metadata: %{
              strategy: :character,
              boundary: boundary,
              char_count: String.length(content)
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
    chunk_overlap = config[:chunk_overlap] || @default_chunk_overlap

    text_length = String.length(text)

    if text_length <= chunk_size do
      1
    else
      effective_chunk_size = max(chunk_size - chunk_overlap, 1)
      div(text_length, effective_chunk_size) + 1
    end
  end

  # Private functions

  @spec split_with_boundary(String.t(), pos_integer(), non_neg_integer(), boundary()) :: [
          String.t()
        ]
  defp split_with_boundary(text, chunk_size, overlap, :none) do
    # Direct character splitting without boundary awareness
    graphemes = String.graphemes(text)
    effective_step = max(chunk_size - overlap, 1)

    graphemes
    |> chunk_at_positions(chunk_size, effective_step)
    |> Enum.reject(&(String.trim(&1) == ""))
  end

  defp split_with_boundary(text, chunk_size, overlap, :word) do
    # Split at word boundaries
    split_at_word_boundaries(text, chunk_size, overlap)
  end

  defp split_with_boundary(text, chunk_size, overlap, :sentence) do
    # Split at sentence boundaries
    split_at_sentence_boundaries(text, chunk_size, overlap)
  end

  @spec chunk_at_positions([String.t()], pos_integer(), pos_integer()) :: [String.t()]
  defp chunk_at_positions(graphemes, chunk_size, step) do
    total = length(graphemes)

    if total <= chunk_size do
      [Enum.join(graphemes)]
    else
      0
      |> Stream.iterate(&(&1 + step))
      |> Stream.take_while(&(&1 < total))
      |> Enum.map(fn start ->
        graphemes
        |> Enum.slice(start, chunk_size)
        |> Enum.join()
      end)
    end
  end

  @spec split_at_word_boundaries(String.t(), pos_integer(), non_neg_integer()) :: [String.t()]
  defp split_at_word_boundaries(text, chunk_size, overlap) do
    words = String.split(text, ~r/(\s+)/, include_captures: true)

    build_chunks_from_words(words, chunk_size, overlap)
    |> Enum.reject(&(String.trim(&1) == ""))
  end

  @spec build_chunks_from_words([String.t()], pos_integer(), non_neg_integer()) :: [String.t()]
  defp build_chunks_from_words(words, chunk_size, overlap) do
    {chunks, current, _} =
      Enum.reduce(words, {[], "", 0}, fn word, {chunks, current, current_len} ->
        word_len = String.length(word)

        cond do
          # Current chunk is empty, start with this word
          current == "" ->
            {chunks, word, word_len}

          # Adding this word would exceed chunk size
          current_len + word_len > chunk_size ->
            # Finalize current chunk and start new one with overlap
            overlap_text = get_word_overlap(current, overlap)
            {[current | chunks], overlap_text <> word, String.length(overlap_text) + word_len}

          # Add word to current chunk
          true ->
            {chunks, current <> word, current_len + word_len}
        end
      end)

    # Don't forget the last chunk
    if current != "" do
      Enum.reverse([current | chunks])
    else
      Enum.reverse(chunks)
    end
  end

  @spec get_word_overlap(String.t(), non_neg_integer()) :: String.t()
  defp get_word_overlap(_text, overlap) when overlap <= 0, do: ""

  defp get_word_overlap(text, overlap) do
    # Get the last `overlap` characters, but try to start at a word boundary
    text_len = String.length(text)

    if text_len <= overlap do
      text
    else
      start_pos = text_len - overlap
      overlap_text = String.slice(text, start_pos, overlap)

      # Try to find a word boundary (space) to start from
      case :binary.match(overlap_text, " ") do
        {pos, _} when pos < overlap ->
          String.slice(overlap_text, pos + 1, overlap)

        _ ->
          overlap_text
      end
    end
  end

  @spec split_at_sentence_boundaries(String.t(), pos_integer(), non_neg_integer()) :: [String.t()]
  defp split_at_sentence_boundaries(text, chunk_size, overlap) do
    # Split on sentence endings (. ! ?)
    sentences = split_into_sentences(text)

    build_chunks_from_sentences(sentences, chunk_size, overlap)
    |> Enum.reject(&(String.trim(&1) == ""))
  end

  @spec split_into_sentences(String.t()) :: [String.t()]
  defp split_into_sentences(text) do
    # Split on sentence boundaries while preserving the punctuation
    ~r/(?<=[.!?])\s+/
    |> Regex.split(text, include_captures: false)
    |> Enum.reject(&(String.trim(&1) == ""))
  end

  @spec build_chunks_from_sentences([String.t()], pos_integer(), non_neg_integer()) :: [
          String.t()
        ]
  defp build_chunks_from_sentences(sentences, chunk_size, overlap) do
    {chunks, current, _} =
      Enum.reduce(sentences, {[], "", 0}, fn sentence, {chunks, current, current_len} ->
        sentence_with_space = if current == "", do: sentence, else: " " <> sentence
        sentence_len = String.length(sentence_with_space)

        cond do
          # Single sentence exceeds chunk size, keep it as is
          current == "" and sentence_len > chunk_size ->
            {[sentence | chunks], "", 0}

          # Current chunk is empty, start with this sentence
          current == "" ->
            {chunks, sentence, sentence_len}

          # Adding this sentence would exceed chunk size
          current_len + sentence_len > chunk_size ->
            # Finalize current chunk and start new one with overlap
            overlap_text = get_sentence_overlap(current, overlap)
            new_current = String.trim(overlap_text <> " " <> sentence)
            {[current | chunks], new_current, String.length(new_current)}

          # Add sentence to current chunk
          true ->
            new_current = current <> sentence_with_space
            {chunks, new_current, String.length(new_current)}
        end
      end)

    # Don't forget the last chunk
    if current != "" do
      Enum.reverse([current | chunks])
    else
      Enum.reverse(chunks)
    end
  end

  @spec get_sentence_overlap(String.t(), non_neg_integer()) :: String.t()
  defp get_sentence_overlap(_text, overlap) when overlap <= 0, do: ""

  defp get_sentence_overlap(text, overlap) do
    # Get the last sentence(s) that fit within the overlap size
    sentences =
      text
      |> split_into_sentences()
      |> Enum.reverse()

    take_sentences_for_overlap(sentences, overlap, [])
    |> Enum.join(" ")
  end

  @spec take_sentences_for_overlap([String.t()], non_neg_integer(), [String.t()]) :: [String.t()]
  defp take_sentences_for_overlap([], _remaining, acc), do: acc

  defp take_sentences_for_overlap([sentence | rest], remaining, acc) do
    sentence_len = String.length(sentence)

    if sentence_len <= remaining do
      take_sentences_for_overlap(rest, remaining - sentence_len - 1, [sentence | acc])
    else
      acc
    end
  end

  @spec calculate_byte_positions(String.t(), String.t(), non_neg_integer(), [String.t()]) ::
          {non_neg_integer(), non_neg_integer()}
  defp calculate_byte_positions(text, content, index, _chunks) do
    # Find the actual byte position of this content in the original text
    start_byte = find_content_position(text, content, index)
    end_byte = start_byte + byte_size(content)
    {start_byte, end_byte}
  end

  @spec find_content_position(String.t(), String.t(), non_neg_integer()) :: non_neg_integer()
  defp find_content_position(text, content, _index) do
    # Find the byte offset of the content in the original text
    # For simplicity, use the first occurrence
    case :binary.match(text, content) do
      {pos, _} -> pos
      :nomatch -> 0
    end
  end
end
