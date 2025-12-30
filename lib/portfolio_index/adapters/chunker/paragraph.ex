defmodule PortfolioIndex.Adapters.Chunker.Paragraph do
  @moduledoc """
  Paragraph-based text chunker.

  Implements the `PortfolioCore.Ports.Chunker` behaviour.

  ## Strategy

  Splits text on paragraph boundaries (double newlines):
  1. Split text into paragraphs
  2. Merge small paragraphs to reach target size
  3. Split large paragraphs at sentence boundaries if needed

  ## Configuration

  - `:chunk_size` - Target chunk size (default: 1000)
  - `:chunk_overlap` - Overlap between chunks (default: 200)
  - `:min_paragraph_size` - Minimum paragraph size before merging (default: 50)
  - `:get_chunk_size` - Function to measure size (default: `&String.length/1`)

  ## Example

      config = %{chunk_size: 1000, chunk_overlap: 200, min_paragraph_size: 100}
      {:ok, chunks} = Paragraph.chunk(text, :plain, config)

      # With token-based sizing
      config = %{
        chunk_size: 256,
        chunk_overlap: 40,
        get_chunk_size: &MyTokenizer.count_tokens/1
      }
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
    get_chunk_size = config[:get_chunk_size] || (&String.length/1)

    if String.trim(text) == "" do
      {:ok, []}
    else
      chunks =
        text
        |> split_into_paragraphs()
        |> merge_small_paragraphs(min_paragraph_size, get_chunk_size)
        |> split_large_paragraphs(chunk_size, get_chunk_size)
        |> group_to_chunk_size(chunk_size, chunk_overlap, get_chunk_size)
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
    get_chunk_size = config[:get_chunk_size] || (&String.length/1)

    text_size = get_chunk_size.(text)
    paragraph_count = count_paragraphs(text)

    # Estimate based on both text size and paragraph count
    by_size = div(text_size, chunk_size) + 1
    max(by_size, div(paragraph_count, 3) + 1)
  end

  # Private functions

  @spec split_into_paragraphs(String.t()) :: [String.t()]
  defp split_into_paragraphs(text) do
    text
    |> String.split(~r/\n\s*\n/, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  @spec merge_small_paragraphs([String.t()], pos_integer(), function()) :: [String.t()]
  defp merge_small_paragraphs(paragraphs, min_size, get_chunk_size) do
    {merged, current} =
      Enum.reduce(paragraphs, {[], ""}, fn para, {result, current} ->
        current_size = if current == "", do: 0, else: get_chunk_size.(current)
        para_size = get_chunk_size.(para)

        cond do
          # Current is empty, use this paragraph
          current == "" ->
            {result, para}

          # Current paragraph is small, try to merge
          current_size < min_size ->
            {result, current <> "\n\n" <> para}

          # Current is big enough, keep separate
          para_size < min_size and current_size + para_size < min_size * 3 ->
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

  @spec split_large_paragraphs([String.t()], pos_integer(), function()) :: [String.t()]
  defp split_large_paragraphs(paragraphs, max_size, get_chunk_size) do
    Enum.flat_map(paragraphs, fn para ->
      if get_chunk_size.(para) > max_size do
        split_at_sentences(para, max_size, get_chunk_size)
      else
        [para]
      end
    end)
  end

  @spec split_at_sentences(String.t(), pos_integer(), function()) :: [String.t()]
  defp split_at_sentences(text, max_size, get_chunk_size) do
    sentences = split_into_sentences(text)

    {chunks, current, _} =
      Enum.reduce(sentences, {[], "", 0}, fn sentence, {chunks, current, current_size} ->
        sentence_size = get_chunk_size.(sentence)
        separator_size = if current == "", do: 0, else: get_chunk_size.(" ")

        cond do
          # Single sentence exceeds max size, keep it anyway
          current == "" and sentence_size > max_size ->
            {[sentence | chunks], "", 0}

          # Current is empty, start with this sentence
          current == "" ->
            {chunks, sentence, sentence_size}

          # Adding would exceed max size
          current_size + separator_size + sentence_size > max_size ->
            {[current | chunks], sentence, sentence_size}

          # Add to current
          true ->
            new_current = current <> " " <> sentence
            {chunks, new_current, current_size + separator_size + sentence_size}
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

  @spec group_to_chunk_size([String.t()], pos_integer(), non_neg_integer(), function()) ::
          [String.t()]
  defp group_to_chunk_size(paragraphs, chunk_size, overlap, get_chunk_size) do
    {chunks, current, _} =
      Enum.reduce(paragraphs, {[], "", 0}, fn para, {chunks, current, current_size} ->
        para_size = get_chunk_size.(para)
        separator = if current == "", do: "", else: "\n\n"
        separator_size = get_chunk_size.(separator)

        cond do
          # Current is empty
          current == "" ->
            {chunks, para, para_size}

          # Adding this paragraph would exceed chunk size
          current_size + separator_size + para_size > chunk_size ->
            overlap_text = get_overlap_text(current, overlap, get_chunk_size)
            new_current = if overlap_text == "", do: para, else: overlap_text <> "\n\n" <> para
            {[current | chunks], new_current, get_chunk_size.(new_current)}

          # Add paragraph to current chunk
          true ->
            new_current = current <> separator <> para
            {chunks, new_current, current_size + separator_size + para_size}
        end
      end)

    if current != "" do
      Enum.reverse([current | chunks])
    else
      Enum.reverse(chunks)
    end
  end

  @spec get_overlap_text(String.t(), non_neg_integer(), function()) :: String.t()
  defp get_overlap_text(_text, overlap, _get_chunk_size) when overlap <= 0, do: ""

  defp get_overlap_text(text, overlap, get_chunk_size) do
    # Get the last paragraph(s) that fit within overlap
    paragraphs =
      text
      |> split_into_paragraphs()
      |> Enum.reverse()

    take_for_overlap(paragraphs, overlap, [], get_chunk_size)
    |> Enum.join("\n\n")
  end

  @spec take_for_overlap([String.t()], non_neg_integer(), [String.t()], function()) :: [
          String.t()
        ]
  defp take_for_overlap([], _remaining, acc, _get_chunk_size), do: acc

  defp take_for_overlap([para | rest], remaining, acc, get_chunk_size) do
    para_size = get_chunk_size.(para)

    if para_size <= remaining do
      take_for_overlap(rest, remaining - para_size - 2, [para | acc], get_chunk_size)
    else
      # Take partial paragraph if it's the first one and acc is empty
      if acc == [] do
        partial = String.slice(para, -min(remaining, String.length(para)), remaining)
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
