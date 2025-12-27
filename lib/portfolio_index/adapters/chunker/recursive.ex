defmodule PortfolioIndex.Adapters.Chunker.Recursive do
  @moduledoc """
  Recursive text chunker with format-aware splitting.

  Implements the `PortfolioCore.Ports.Chunker` behaviour.

  ## Strategy

  Recursively splits text using a hierarchy of separators:
  1. Try to split on the largest separator
  2. If chunks are still too large, split on smaller separators
  3. Continue until all chunks are within size limits

  ## Format Support

  - `:plain` - Generic text splitting
  - `:markdown` - Respects headers, code blocks, paragraphs
  - `:code` - Respects function/module boundaries (Elixir-aware)
  - `:html` - Respects HTML structure

  ## Example

      config = %{chunk_size: 1000, chunk_overlap: 200}
      {:ok, chunks} = Recursive.chunk(text, :markdown, config)
  """

  @behaviour PortfolioCore.Ports.Chunker

  @default_chunk_size 1000
  @default_chunk_overlap 200

  # Separators by format, in order of preference (largest to smallest)
  @separators %{
    plain: ["\n\n", "\n", ". ", " ", ""],
    markdown: [
      # H2 headers
      "\n## ",
      # H3 headers
      "\n### ",
      # H4 headers
      "\n#### ",
      # Code blocks
      "\n```",
      # Paragraphs
      "\n\n",
      # Lines
      "\n",
      # Sentences
      ". ",
      # Words
      " ",
      # Characters
      ""
    ],
    code: [
      # Module boundaries
      "\ndefmodule ",
      # Function definitions
      "\ndef ",
      # Private function definitions
      "\ndefp ",
      # Double newlines
      "\n\n",
      # Single newlines
      "\n",
      # Spaces
      " ",
      # Characters
      ""
    ],
    html: [
      "</div>",
      "</p>",
      "</section>",
      "<br>",
      "\n\n",
      "\n",
      ". ",
      " ",
      ""
    ]
  }

  @impl true
  def chunk(text, format, config) do
    chunk_size = config[:chunk_size] || config.chunk_size || @default_chunk_size
    chunk_overlap = config[:chunk_overlap] || config.chunk_overlap || @default_chunk_overlap
    separators = config[:separators] || Map.get(@separators, format, @separators.plain)

    chunks = recursive_split(text, separators, chunk_size, chunk_overlap)

    result =
      chunks
      |> Enum.with_index()
      |> Enum.map(fn {content, index} ->
        %{
          content: content,
          index: index,
          start_offset: calculate_offset(text, content, index, chunks),
          end_offset: calculate_end_offset(text, content, index, chunks),
          metadata: %{
            format: format,
            char_count: String.length(content),
            separator_used: find_separator_used(content, separators)
          }
        }
      end)

    {:ok, result}
  end

  @impl true
  def estimate_chunks(text, config) do
    chunk_size = config[:chunk_size] || config.chunk_size || @default_chunk_size
    chunk_overlap = config[:chunk_overlap] || config.chunk_overlap || @default_chunk_overlap

    text_length = String.length(text)

    if text_length <= chunk_size do
      1
    else
      effective_chunk_size = chunk_size - chunk_overlap
      div(text_length, effective_chunk_size) + 1
    end
  end

  # Private functions

  defp recursive_split(text, separators, chunk_size, chunk_overlap) do
    do_recursive_split(text, separators, chunk_size, chunk_overlap)
    |> List.flatten()
    |> add_overlap(chunk_overlap)
    |> Enum.reject(&(String.trim(&1) == ""))
  end

  defp do_recursive_split(text, _separators, chunk_size, _overlap)
       when byte_size(text) <= chunk_size do
    [text]
  end

  defp do_recursive_split(text, [], chunk_size, _overlap) do
    # No more separators, force split by character count
    split_by_size(text, chunk_size)
  end

  defp do_recursive_split(text, [separator | rest_separators], chunk_size, overlap) do
    if separator == "" do
      # Empty separator means character-level split
      split_by_size(text, chunk_size)
    else
      parts = String.split(text, separator)
      process_split_parts(parts, text, separator, rest_separators, chunk_size, overlap)
    end
  end

  defp process_split_parts([_single_part], text, _separator, rest_separators, chunk_size, overlap) do
    # Separator not found (only one part), try next separator
    do_recursive_split(text, rest_separators, chunk_size, overlap)
  end

  defp process_split_parts(parts, _text, separator, rest_separators, chunk_size, overlap) do
    # Successfully split into multiple parts, now process each part
    parts
    |> Enum.map(&split_part_if_needed(&1, rest_separators, chunk_size, overlap))
    |> Enum.intersperse(String.trim(separator))
    |> merge_small_chunks(chunk_size)
  end

  defp split_part_if_needed(part, rest_separators, chunk_size, overlap) do
    if String.length(part) > chunk_size do
      do_recursive_split(part, rest_separators, chunk_size, overlap)
    else
      part
    end
  end

  defp split_by_size(text, size) do
    text
    |> String.graphemes()
    |> Enum.chunk_every(size)
    |> Enum.map(&Enum.join/1)
  end

  defp merge_small_chunks(chunks, max_size) when is_list(chunks) do
    chunks
    |> List.flatten()
    |> Enum.reduce([], &merge_chunk_into_acc(&1, &2, max_size))
    |> Enum.reverse()
  end

  defp merge_chunk_into_acc(chunk, [], _max_size), do: [chunk]

  defp merge_chunk_into_acc(chunk, [last | rest] = acc, max_size) do
    combined = last <> " " <> chunk

    if String.length(combined) <= max_size do
      [combined | rest]
    else
      [chunk | acc]
    end
  end

  defp add_overlap(chunks, overlap) when overlap > 0 and length(chunks) > 1 do
    chunks
    |> Enum.with_index()
    |> Enum.map(fn {chunk, index} ->
      if index > 0 do
        prev_chunk = Enum.at(chunks, index - 1)
        overlap_text = String.slice(prev_chunk, -overlap, overlap)
        overlap_text <> chunk
      else
        chunk
      end
    end)
  end

  defp add_overlap(chunks, _overlap), do: chunks

  defp calculate_offset(_text, _content, 0, _chunks), do: 0

  defp calculate_offset(_text, _content, index, chunks) do
    # Sum of lengths of previous chunks (approximate due to overlap)
    chunks
    |> Enum.take(index)
    |> Enum.map(&String.length/1)
    |> Enum.sum()
  end

  defp calculate_end_offset(text, content, index, chunks) do
    calculate_offset(text, content, index, chunks) + String.length(content)
  end

  defp find_separator_used(_content, []), do: nil

  defp find_separator_used(content, [sep | rest]) do
    if sep != "" and String.contains?(content, sep) do
      sep
    else
      find_separator_used(content, rest)
    end
  end
end
