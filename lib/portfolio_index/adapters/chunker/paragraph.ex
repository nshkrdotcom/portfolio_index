defmodule PortfolioIndex.Adapters.Chunker.Paragraph do
  @moduledoc """
  Paragraph-based text chunker.

  Implements the `PortfolioCore.Ports.Chunker` behaviour.

  ## Strategy

  Splits text on paragraph boundaries (double newlines):
  1. Split text into paragraphs
  2. Merge small paragraphs to reach target size
  3. Split large paragraphs at sentence boundaries if needed

  ## Example

      config = %{chunk_size: 1000, chunk_overlap: 200, min_paragraph_size: 100}
      {:ok, chunks} = Paragraph.chunk(text, :plain, config)
  """

  @behaviour PortfolioCore.Ports.Chunker

  @default_chunk_size 1000
  @default_chunk_overlap 200
  @default_min_paragraph_size 50

  @impl true
  @spec chunk(String.t(), atom(), map()) :: {:ok, [map()]} | {:error, term()}
  def chunk(text, _format, config) do
    chunk_size = config[:chunk_size] || @default_chunk_size
    chunk_overlap = config[:chunk_overlap] || @default_chunk_overlap
    min_paragraph_size = config[:min_paragraph_size] || @default_min_paragraph_size

    if String.trim(text) == "" do
      {:ok, []}
    else
      chunks =
        text
        |> split_into_paragraphs()
        |> merge_small_paragraphs(min_paragraph_size)
        |> split_large_paragraphs(chunk_size)
        |> group_to_chunk_size(chunk_size, chunk_overlap)
        |> Enum.reject(&(String.trim(&1) == ""))

      result =
        chunks
        |> Enum.with_index()
        |> Enum.map(fn {content, index} ->
          {start_byte, end_byte} = calculate_byte_positions(text, content)

          %{
            content: content,
            index: index,
            start_byte: start_byte,
            end_byte: end_byte,
            start_offset: start_byte,
            end_offset: end_byte,
            metadata: %{
              strategy: :paragraph,
              char_count: String.length(content),
              paragraph_count: count_paragraphs(content)
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

    text_length = String.length(text)
    paragraph_count = count_paragraphs(text)

    # Estimate based on both text length and paragraph count
    by_length = div(text_length, chunk_size) + 1
    max(by_length, div(paragraph_count, 3) + 1)
  end

  # Private functions

  @spec split_into_paragraphs(String.t()) :: [String.t()]
  defp split_into_paragraphs(text) do
    text
    |> String.split(~r/\n\s*\n/, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  @spec merge_small_paragraphs([String.t()], pos_integer()) :: [String.t()]
  defp merge_small_paragraphs(paragraphs, min_size) do
    {merged, current} =
      Enum.reduce(paragraphs, {[], ""}, fn para, {result, current} ->
        cond do
          # Current is empty, use this paragraph
          current == "" ->
            {result, para}

          # Current paragraph is small, try to merge
          String.length(current) < min_size ->
            {result, current <> "\n\n" <> para}

          # Current is big enough, keep separate
          String.length(para) < min_size and
              String.length(current) + String.length(para) < min_size * 3 ->
            {result, current <> "\n\n" <> para}

          # Keep as separate paragraphs
          true ->
            {[current | result], para}
        end
      end)

    if current != "" do
      Enum.reverse([current | merged])
    else
      Enum.reverse(merged)
    end
  end

  @spec split_large_paragraphs([String.t()], pos_integer()) :: [String.t()]
  defp split_large_paragraphs(paragraphs, max_size) do
    Enum.flat_map(paragraphs, fn para ->
      if String.length(para) > max_size do
        split_at_sentences(para, max_size)
      else
        [para]
      end
    end)
  end

  @spec split_at_sentences(String.t(), pos_integer()) :: [String.t()]
  defp split_at_sentences(text, max_size) do
    sentences = split_into_sentences(text)

    {chunks, current, _} =
      Enum.reduce(sentences, {[], "", 0}, fn sentence, {chunks, current, current_len} ->
        sentence_len = String.length(sentence)

        cond do
          # Single sentence exceeds max size, keep it anyway
          current == "" and sentence_len > max_size ->
            {[sentence | chunks], "", 0}

          # Current is empty, start with this sentence
          current == "" ->
            {chunks, sentence, sentence_len}

          # Adding would exceed max size
          current_len + sentence_len + 1 > max_size ->
            {[current | chunks], sentence, sentence_len}

          # Add to current
          true ->
            {chunks, current <> " " <> sentence, current_len + sentence_len + 1}
        end
      end)

    if current != "" do
      Enum.reverse([current | chunks])
    else
      Enum.reverse(chunks)
    end
  end

  @spec split_into_sentences(String.t()) :: [String.t()]
  defp split_into_sentences(text) do
    ~r/(?<=[.!?])\s+/
    |> Regex.split(text, include_captures: false)
    |> Enum.reject(&(String.trim(&1) == ""))
  end

  @spec group_to_chunk_size([String.t()], pos_integer(), non_neg_integer()) :: [String.t()]
  defp group_to_chunk_size(paragraphs, chunk_size, overlap) do
    {chunks, current, _} =
      Enum.reduce(paragraphs, {[], "", 0}, fn para, {chunks, current, current_len} ->
        para_len = String.length(para)
        separator = if current == "", do: "", else: "\n\n"
        separator_len = String.length(separator)

        cond do
          # Current is empty
          current == "" ->
            {chunks, para, para_len}

          # Adding this paragraph would exceed chunk size
          current_len + separator_len + para_len > chunk_size ->
            overlap_text = get_overlap_text(current, overlap)
            new_current = if overlap_text == "", do: para, else: overlap_text <> "\n\n" <> para
            {[current | chunks], new_current, String.length(new_current)}

          # Add paragraph to current chunk
          true ->
            new_current = current <> separator <> para
            {chunks, new_current, current_len + separator_len + para_len}
        end
      end)

    if current != "" do
      Enum.reverse([current | chunks])
    else
      Enum.reverse(chunks)
    end
  end

  @spec get_overlap_text(String.t(), non_neg_integer()) :: String.t()
  defp get_overlap_text(_text, overlap) when overlap <= 0, do: ""

  defp get_overlap_text(text, overlap) do
    # Get the last paragraph(s) that fit within overlap
    paragraphs =
      text
      |> split_into_paragraphs()
      |> Enum.reverse()

    take_for_overlap(paragraphs, overlap, [])
    |> Enum.join("\n\n")
  end

  @spec take_for_overlap([String.t()], non_neg_integer(), [String.t()]) :: [String.t()]
  defp take_for_overlap([], _remaining, acc), do: acc

  defp take_for_overlap([para | rest], remaining, acc) do
    para_len = String.length(para)

    if para_len <= remaining do
      take_for_overlap(rest, remaining - para_len - 2, [para | acc])
    else
      # Take partial paragraph if it's the first one and acc is empty
      if acc == [] do
        partial = String.slice(para, -min(remaining, para_len), remaining)
        [partial]
      else
        acc
      end
    end
  end

  @spec count_paragraphs(String.t()) :: non_neg_integer()
  defp count_paragraphs(text) do
    text
    |> split_into_paragraphs()
    |> length()
  end

  @spec calculate_byte_positions(String.t(), String.t()) :: {non_neg_integer(), non_neg_integer()}
  defp calculate_byte_positions(text, content) do
    # Find normalized content in text
    normalized_content = content |> String.trim()

    start_byte =
      case :binary.match(text, normalized_content) do
        {pos, _} -> pos
        :nomatch -> 0
      end

    end_byte = start_byte + byte_size(content)
    {start_byte, end_byte}
  end
end
