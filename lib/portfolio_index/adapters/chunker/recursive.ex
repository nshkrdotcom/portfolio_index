defmodule PortfolioIndex.Adapters.Chunker.Recursive do
  @moduledoc """
  Recursive text chunker with format-aware splitting.

  Implements the `PortfolioCore.Ports.Chunker` behaviour.

  ## Strategy

  Recursively splits text using a hierarchy of separators:
  1. Try to split on the largest separator (e.g., module/class definitions)
  2. If chunks are still too large, split on smaller separators
  3. Continue until all chunks are within size limits
  4. Merge small adjacent chunks to approach target size
  5. Apply overlap between chunks for context preservation

  ## Format Support

  Supports 17+ formats via the `Separators` module:

  ### Programming Languages
  - `:elixir` / `:code` - Elixir source files (defmodule, def, defp, etc.)
  - `:ruby` - Ruby source files (class, def, etc.)
  - `:php` - PHP source files (class, function, etc.)
  - `:python` - Python source files (class, def)
  - `:javascript` - JavaScript source files
  - `:typescript` - TypeScript source files
  - `:vue` - Vue.js Single File Components

  ### Markup
  - `:markdown` - Respects headers, code blocks, paragraphs
  - `:html` - Respects HTML structure
  - `:plain` - Generic text splitting

  ### Documents
  - `:doc`, `:docx`, `:epub`, `:latex`, `:odt`, `:pdf`, `:rtf`

  ## Configuration

  - `:chunk_size` - Target chunk size (default: 1000)
  - `:chunk_overlap` - Overlap between chunks (default: 200)
  - `:get_chunk_size` - Function to measure size (default: `&String.length/1`)
  - `:separators` - Custom separators (overrides format-based)

  ## Examples

      # Basic usage
      config = %{chunk_size: 1000, chunk_overlap: 200}
      {:ok, chunks} = Recursive.chunk(text, :markdown, config)

      # With token-based sizing
      config = %{
        chunk_size: 512,
        chunk_overlap: 50,
        get_chunk_size: &MyTokenizer.count_tokens/1
      }
      {:ok, chunks} = Recursive.chunk(text, :plain, config)

      # With custom separators
      config = %{
        chunk_size: 1000,
        separators: ["\\n## ", "\\n\\n", "\\n", " "]
      }
      {:ok, chunks} = Recursive.chunk(text, :custom, config)
  """

  @behaviour PortfolioCore.Ports.Chunker

  alias PortfolioIndex.Adapters.Chunker.{Separators, Tokens}

  @default_chunk_size 1000
  @default_chunk_overlap 200

  @impl true
  @spec chunk(String.t(), atom(), map()) :: {:ok, [map()]} | {:error, term()}
  def chunk(text, format, config) do
    chunk_size = get_config(config, :chunk_size, @default_chunk_size)
    chunk_overlap = get_config(config, :chunk_overlap, @default_chunk_overlap)
    get_chunk_size = get_config(config, :get_chunk_size, &String.length/1)
    separators = get_config(config, :separators, nil) || Separators.get_separators(format)

    chunks = recursive_split(text, separators, chunk_size, chunk_overlap, get_chunk_size)

    result =
      chunks
      |> Enum.with_index()
      |> Enum.map(fn {content, index} ->
        {start_offset, end_offset} = calculate_offsets(text, content, index, chunks)

        %{
          content: content,
          index: index,
          start_byte: start_offset,
          end_byte: end_offset,
          start_offset: start_offset,
          end_offset: end_offset,
          metadata: %{
            format: format,
            char_count: String.length(content),
            token_count: Tokens.estimate(content),
            separator_used: find_separator_used(content, separators)
          }
        }
      end)

    {:ok, result}
  end

  @impl true
  @spec estimate_chunks(String.t(), map()) :: non_neg_integer()
  def estimate_chunks(text, config) do
    chunk_size = get_config(config, :chunk_size, @default_chunk_size)
    chunk_overlap = get_config(config, :chunk_overlap, @default_chunk_overlap)
    get_chunk_size = get_config(config, :get_chunk_size, &String.length/1)

    text_size = get_chunk_size.(text)

    if text_size <= chunk_size do
      1
    else
      effective_chunk_size = max(chunk_size - chunk_overlap, 1)
      div(text_size, effective_chunk_size) + 1
    end
  end

  # Private functions

  @spec get_config(map(), atom(), term()) :: term()
  defp get_config(config, key, default) when is_map(config) do
    case Map.get(config, key) do
      nil ->
        # Try struct access pattern
        case config do
          %{^key => value} when not is_nil(value) -> value
          _ -> default
        end

      value ->
        value
    end
  end

  @spec recursive_split(String.t(), [String.t()], pos_integer(), non_neg_integer(), function()) ::
          [String.t()]
  defp recursive_split(text, separators, chunk_size, chunk_overlap, get_chunk_size) do
    text
    |> do_recursive_split(separators, chunk_size, get_chunk_size)
    |> List.flatten()
    |> add_overlap(chunk_overlap)
    |> Enum.reject(&(String.trim(&1) == ""))
  end

  @spec do_recursive_split(String.t(), [String.t()], pos_integer(), function()) ::
          [String.t()] | [[String.t()]]
  defp do_recursive_split(text, separators, chunk_size, get_chunk_size) do
    if get_chunk_size.(text) <= chunk_size do
      [text]
    else
      do_recursive_split_impl(text, separators, chunk_size, get_chunk_size)
    end
  end

  @spec do_recursive_split_impl(String.t(), [String.t()], pos_integer(), function()) ::
          [String.t()] | [[String.t()]]
  defp do_recursive_split_impl(text, [], chunk_size, _get_chunk_size) do
    # No more separators, force split by character count
    split_by_size(text, chunk_size)
  end

  defp do_recursive_split_impl(text, [separator | rest_separators], chunk_size, get_chunk_size) do
    if separator == "" do
      # Empty separator means character-level split
      split_by_size(text, chunk_size)
    else
      parts = String.split(text, separator)
      process_split_parts(parts, text, separator, rest_separators, chunk_size, get_chunk_size)
    end
  end

  @spec process_split_parts(
          [String.t()],
          String.t(),
          String.t(),
          [String.t()],
          pos_integer(),
          function()
        ) ::
          [String.t()] | [[String.t()]]
  defp process_split_parts(
         [_single_part],
         text,
         _separator,
         rest_separators,
         chunk_size,
         get_chunk_size
       ) do
    # Separator not found (only one part), try next separator
    do_recursive_split(text, rest_separators, chunk_size, get_chunk_size)
  end

  defp process_split_parts(parts, _text, separator, rest_separators, chunk_size, get_chunk_size) do
    # Successfully split into multiple parts, now process each part
    parts
    |> Enum.map(&split_part_if_needed(&1, rest_separators, chunk_size, get_chunk_size))
    |> Enum.intersperse(String.trim(separator))
    |> merge_small_chunks(chunk_size, get_chunk_size)
  end

  @spec split_part_if_needed(String.t(), [String.t()], pos_integer(), function()) ::
          String.t() | [String.t()]
  defp split_part_if_needed(part, rest_separators, chunk_size, get_chunk_size) do
    if get_chunk_size.(part) > chunk_size do
      do_recursive_split(part, rest_separators, chunk_size, get_chunk_size)
    else
      part
    end
  end

  @spec split_by_size(String.t(), pos_integer()) :: [String.t()]
  defp split_by_size(text, size) do
    text
    |> String.graphemes()
    |> Enum.chunk_every(size)
    |> Enum.map(&Enum.join/1)
  end

  @spec merge_small_chunks([String.t() | [String.t()]], pos_integer(), function()) :: [String.t()]
  defp merge_small_chunks(chunks, max_size, get_chunk_size) when is_list(chunks) do
    chunks
    |> List.flatten()
    |> Enum.reduce([], &merge_chunk_into_acc(&1, &2, max_size, get_chunk_size))
    |> Enum.reverse()
  end

  @spec merge_chunk_into_acc(String.t(), [String.t()], pos_integer(), function()) :: [String.t()]
  defp merge_chunk_into_acc(chunk, [], _max_size, _get_chunk_size), do: [chunk]

  defp merge_chunk_into_acc(chunk, [last | rest] = acc, max_size, get_chunk_size) do
    combined = last <> " " <> chunk

    if get_chunk_size.(combined) <= max_size do
      [combined | rest]
    else
      [chunk | acc]
    end
  end

  @spec add_overlap([String.t()], non_neg_integer()) :: [String.t()]
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

  @spec calculate_offsets(String.t(), String.t(), non_neg_integer(), [String.t()]) ::
          {non_neg_integer(), non_neg_integer()}
  defp calculate_offsets(_text, content, 0, _chunks) do
    {0, byte_size(content)}
  end

  defp calculate_offsets(_text, content, index, chunks) do
    # Sum of byte sizes of previous chunks (approximate due to overlap)
    start_offset =
      chunks
      |> Enum.take(index)
      |> Enum.map(&byte_size/1)
      |> Enum.sum()

    {start_offset, start_offset + byte_size(content)}
  end

  @spec find_separator_used(String.t(), [String.t()]) :: String.t() | nil
  defp find_separator_used(_content, []), do: nil

  defp find_separator_used(content, [sep | rest]) do
    if sep != "" and String.contains?(content, sep) do
      sep
    else
      find_separator_used(content, rest)
    end
  end
end
