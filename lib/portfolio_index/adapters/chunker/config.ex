defmodule PortfolioIndex.Adapters.Chunker.Config do
  @moduledoc """
  Configuration validation for chunker adapters using NimbleOptions.

  Provides schema-based validation with sensible defaults for all chunking
  configuration options. Supports both map and keyword list inputs for
  backwards compatibility.

  ## Options

    * `:chunk_size` - Target size for each chunk (default: 1000)
    * `:chunk_overlap` - Overlap between adjacent chunks (default: 200)
    * `:get_chunk_size` - Function to measure chunk size (default: `&String.length/1`)
    * `:format` - Content format hint (default: `:plain`)
    * `:separators` - Custom separator list (default: `nil`, uses format-based)

  ## Examples

      # Validate with defaults
      {:ok, config} = Config.validate(%{})
      config.chunk_size  #=> 1000

      # Validate with custom options
      {:ok, config} = Config.validate(%{
        chunk_size: 512,
        get_chunk_size: &MyTokenizer.count_tokens/1
      })

      # Validate and raise on error
      config = Config.validate!(%{chunk_size: 500})

      # Merge user config with defaults (no validation)
      config = Config.merge_with_defaults(%{chunk_size: 500})
  """

  alias PortfolioIndex.Adapters.Chunker.Separators

  @default_chunk_size 1000
  @default_chunk_overlap 200

  # Get supported formats from Separators module
  @supported_formats Separators.supported_formats()

  @schema [
    chunk_size: [
      type: :pos_integer,
      default: @default_chunk_size,
      doc: "Target size for each chunk. Must be a positive integer."
    ],
    chunk_overlap: [
      type: :non_neg_integer,
      default: @default_chunk_overlap,
      doc: "Overlap between adjacent chunks. Must be zero or positive."
    ],
    get_chunk_size: [
      type: {:fun, 1},
      default: &String.length/1,
      doc: "Function to measure chunk size. Takes text, returns integer."
    ],
    format: [
      type: {:in, @supported_formats},
      default: :plain,
      doc: "Content format hint for separator selection."
    ],
    separators: [
      type: {:or, [nil, {:list, :string}]},
      default: nil,
      doc: "Custom separator list. Overrides format-based separators if provided."
    ]
  ]

  @type t :: %__MODULE__{
          chunk_size: pos_integer(),
          chunk_overlap: non_neg_integer(),
          get_chunk_size: (String.t() -> non_neg_integer()),
          format: atom(),
          separators: [String.t()] | nil
        }

  defstruct [
    :chunk_size,
    :chunk_overlap,
    :get_chunk_size,
    :format,
    :separators
  ]

  @doc """
  Returns the NimbleOptions schema for chunker configuration.
  """
  @spec schema() :: keyword()
  def schema, do: @schema

  @doc """
  Returns the default chunk size.
  """
  @spec default_chunk_size() :: pos_integer()
  def default_chunk_size, do: @default_chunk_size

  @doc """
  Returns the default chunk overlap.
  """
  @spec default_chunk_overlap() :: non_neg_integer()
  def default_chunk_overlap, do: @default_chunk_overlap

  @doc """
  Validates configuration and returns a Config struct.

  Accepts either a map or keyword list of options. Missing options are
  filled with defaults.

  ## Examples

      {:ok, config} = Config.validate(%{chunk_size: 500})
      {:error, "invalid value..."} = Config.validate(%{chunk_size: -1})
  """
  @spec validate(map() | keyword()) :: {:ok, t()} | {:error, String.t()}
  def validate(opts) when is_map(opts) do
    opts
    |> Map.to_list()
    |> validate_from_keyword()
  end

  def validate(opts) when is_list(opts) do
    validate_from_keyword(opts)
  end

  @doc """
  Validates configuration from a keyword list.

  ## Examples

      {:ok, config} = Config.validate_from_keyword(chunk_size: 500)
  """
  @spec validate_from_keyword(keyword()) :: {:ok, t()} | {:error, String.t()}
  def validate_from_keyword(opts) do
    case NimbleOptions.validate(opts, @schema) do
      {:ok, validated} ->
        {:ok, struct(__MODULE__, validated)}

      {:error, %NimbleOptions.ValidationError{message: message}} ->
        {:error, message}
    end
  end

  @doc """
  Validates configuration and raises on error.

  ## Examples

      config = Config.validate!(%{chunk_size: 500})

  ## Raises

      ArgumentError - if validation fails
  """
  @spec validate!(map() | keyword()) :: t()
  def validate!(opts) do
    case validate(opts) do
      {:ok, config} -> config
      {:error, message} -> raise ArgumentError, message
    end
  end

  @doc """
  Merges user configuration with defaults without strict validation.

  This is a convenience function for backwards compatibility with code
  that expects to access config values directly without validation errors.
  Invalid values will still be replaced with defaults.

  ## Examples

      config = Config.merge_with_defaults(%{chunk_size: 500})
      config.chunk_size  #=> 500
      config.chunk_overlap  #=> 200 (default)
  """
  @spec merge_with_defaults(map() | keyword()) :: t()
  def merge_with_defaults(opts) when is_map(opts) do
    opts
    |> Map.to_list()
    |> merge_with_defaults()
  end

  def merge_with_defaults(opts) when is_list(opts) do
    defaults = [
      chunk_size: @default_chunk_size,
      chunk_overlap: @default_chunk_overlap,
      get_chunk_size: &String.length/1,
      format: :plain,
      separators: nil
    ]

    merged = Keyword.merge(defaults, opts)
    struct(__MODULE__, merged)
  end
end
