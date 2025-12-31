defmodule PortfolioIndex.Adapters.Embedder.Function do
  @moduledoc """
  Wrapper adapter that delegates to a custom function.
  Useful for quick integration of custom embedding logic.

  Note: This adapter does not implement the `PortfolioCore.Ports.Embedder`
  behaviour directly since it requires a struct instance as the first argument.
  Use it for ad-hoc embedding needs or testing.

  ## Usage

      # With a function
      embedder = PortfolioIndex.Adapters.Embedder.Function.new(
        fn text -> MyEmbedder.embed(text) end,
        dimensions: 768
      )

      # Use in pipeline
      {:ok, result} = PortfolioIndex.Adapters.Embedder.Function.embed(embedder, "hello", [])

  ## With Batch Function

      embedder = PortfolioIndex.Adapters.Embedder.Function.new(
        fn text -> MyEmbedder.embed(text) end,
        dimensions: 768,
        batch_fn: fn texts -> MyEmbedder.embed_batch(texts) end
      )
  """

  # Note: We don't use @behaviour PortfolioCore.Ports.Embedder here because
  # this adapter has a different signature - it takes an embedder struct as
  # the first argument rather than text/opts.

  require Logger

  @type embed_fn :: (String.t() -> {:ok, [float()]} | {:error, term()})
  @type batch_fn :: ([String.t()] -> {:ok, [[float()]]} | {:error, term()})

  @type t :: %__MODULE__{
          embed_fn: embed_fn(),
          batch_fn: batch_fn() | nil,
          dimensions: pos_integer()
        }

  defstruct [:embed_fn, :batch_fn, :dimensions]

  @doc """
  Create a new function embedder.

  ## Options

    * `:dimensions` - Required. The output dimensions of the embeddings.
    * `:batch_fn` - Optional. A function for batch embedding.

  ## Examples

      embedder = Function.new(
        fn text -> {:ok, my_embed(text)} end,
        dimensions: 768
      )
  """
  @spec new(embed_fn(), keyword()) :: t()
  def new(embed_fn, opts) do
    dimensions = Keyword.get(opts, :dimensions)

    unless dimensions do
      raise ArgumentError,
            "dimensions option is required for Function embedder"
    end

    %__MODULE__{
      embed_fn: embed_fn,
      batch_fn: Keyword.get(opts, :batch_fn),
      dimensions: dimensions
    }
  end

  @doc """
  Generate an embedding for a single text using the wrapped function.
  """
  @spec embed(t(), String.t(), keyword()) ::
          {:ok, PortfolioCore.Ports.Embedder.embedding_result()} | {:error, term()}
  def embed(%__MODULE__{} = embedder, text, _opts \\ []) do
    start_time = System.monotonic_time(:millisecond)

    try do
      case embedder.embed_fn.(text) do
        {:ok, vector} when is_list(vector) ->
          token_count = estimate_tokens(text)
          duration = System.monotonic_time(:millisecond) - start_time

          emit_telemetry(
            :embed,
            %{
              duration_ms: duration,
              tokens: token_count,
              dimensions: length(vector)
            },
            %{model: "custom"}
          )

          {:ok,
           %{
             vector: vector,
             model: "custom",
             dimensions: length(vector),
             token_count: token_count
           }}

        {:error, reason} ->
          {:error, reason}

        other ->
          {:error, {:invalid_result, other}}
      end
    rescue
      e ->
        Logger.error("Function embedder failed: #{inspect(e)}")
        {:error, {:embed_failed, e}}
    end
  end

  @doc """
  Generate embeddings for multiple texts.

  Uses the batch function if provided, otherwise falls back to sequential embedding.
  """
  @spec embed_batch(t(), [String.t()], keyword()) ::
          {:ok, PortfolioCore.Ports.Embedder.batch_result()} | {:error, term()}
  def embed_batch(embedder, texts, opts \\ [])

  def embed_batch(%__MODULE__{}, [], _opts) do
    {:ok, %{embeddings: [], total_tokens: 0}}
  end

  def embed_batch(%__MODULE__{batch_fn: nil} = embedder, texts, opts) do
    # Fall back to sequential embedding
    results =
      Enum.reduce_while(texts, [], fn text, acc ->
        case embed(embedder, text, opts) do
          {:ok, result} -> {:cont, [result | acc]}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case results do
      {:error, reason} ->
        {:error, reason}

      embeddings when is_list(embeddings) ->
        embeddings = Enum.reverse(embeddings)
        total_tokens = Enum.sum(Enum.map(embeddings, & &1.token_count))

        {:ok,
         %{
           embeddings: embeddings,
           total_tokens: total_tokens
         }}
    end
  end

  def embed_batch(%__MODULE__{batch_fn: batch_fn}, texts, _opts)
      when is_function(batch_fn, 1) do
    start_time = System.monotonic_time(:millisecond)

    try do
      case batch_fn.(texts) do
        {:ok, vectors} when is_list(vectors) ->
          embeddings =
            Enum.zip(texts, vectors)
            |> Enum.map(fn {text, vector} ->
              %{
                vector: vector,
                model: "custom",
                dimensions: length(vector),
                token_count: estimate_tokens(text)
              }
            end)

          total_tokens = Enum.sum(Enum.map(embeddings, & &1.token_count))
          duration = System.monotonic_time(:millisecond) - start_time

          emit_telemetry(
            :embed_batch,
            %{
              duration_ms: duration,
              count: length(texts),
              total_tokens: total_tokens
            },
            %{model: "custom"}
          )

          {:ok,
           %{
             embeddings: embeddings,
             total_tokens: total_tokens
           }}

        {:error, reason} ->
          {:error, reason}

        other ->
          {:error, {:invalid_result, other}}
      end
    rescue
      e ->
        Logger.error("Function embedder batch failed: #{inspect(e)}")
        {:error, {:embed_batch_failed, e}}
    end
  end

  @doc """
  Get the dimensions for this embedder.
  """
  @spec dimensions(t(), keyword()) :: pos_integer()
  def dimensions(%__MODULE__{dimensions: dims}, _opts \\ []) do
    dims
  end

  @doc """
  Get the list of supported models (always returns ["custom"]).
  """
  @spec supported_models() :: [String.t()]
  def supported_models, do: ["custom"]

  # Private functions

  defp estimate_tokens(text) do
    # Rough estimation: ~4 characters per token for English
    div(String.length(text), 4) + 1
  end

  defp emit_telemetry(operation, measurements, metadata) do
    :telemetry.execute(
      [:portfolio_index, :embedder, operation],
      measurements,
      metadata
    )
  end
end
