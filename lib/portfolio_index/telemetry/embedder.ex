defmodule PortfolioIndex.Telemetry.Embedder do
  @moduledoc """
  Embedder-specific telemetry utilities.

  Provides utilities for wrapping embedding calls with telemetry instrumentation.

  ## Usage

      alias PortfolioIndex.Telemetry.Embedder

      Embedder.span(
        model: "text-embedding-3-small",
        provider: :openai,
        text_length: String.length(text)
      ], fn ->
        OpenAI.embed(text)
      end)

  ## Metadata Fields

  The span automatically includes:
  - `:model` - Embedding model identifier
  - `:dimensions` - Embedding vector dimensions
  - `:text_length` - Character count of input
  - `:batch_size` - Number of texts (for batch operations)
  - `:provider` - Embedder provider
  """

  @doc """
  Wrap an embedding call with telemetry.

  Emits `[:portfolio, :embedder, :embed, :start]`, `[:portfolio, :embedder, :embed, :stop]`,
  and `[:portfolio, :embedder, :embed, :exception]` events.

  ## Parameters

    - `metadata` - Keyword list with embedding context:
      - `:model` - Model identifier
      - `:provider` - Embedder provider (:openai, :voyage, :bumblebee, etc.)
      - `:text_length` - Character count of input text
      - `:text` - The input text (will extract length)
    - `fun` - Function that performs the embedding

  ## Example

      Embedder.span([model: "text-embedding-3-small", text_length: 100], fn ->
        OpenAI.embed(text)
      end)
  """
  @spec span(keyword(), (-> result)) :: result when result: any()
  def span(metadata, fun) when is_function(fun, 0) do
    enriched_metadata = enrich_start_metadata(metadata)

    :telemetry.span(
      [:portfolio, :embedder, :embed],
      Map.new(enriched_metadata),
      fn ->
        result = fun.()
        stop_meta = enrich_stop_metadata(result, enriched_metadata)
        {result, stop_meta}
      end
    )
  end

  @doc """
  Wrap a batch embedding call with telemetry.

  Emits `[:portfolio, :embedder, :embed_batch, :start]`, `[:portfolio, :embedder, :embed_batch, :stop]`,
  and `[:portfolio, :embedder, :embed_batch, :exception]` events.

  ## Parameters

    - `metadata` - Keyword list with embedding context:
      - `:model` - Model identifier
      - `:provider` - Embedder provider
      - `:batch_size` - Number of texts in batch
      - `:texts` - List of input texts (will extract batch_size)
    - `fun` - Function that performs the batch embedding

  ## Example

      Embedder.batch_span([model: "text-embedding-3-small", batch_size: 10], fn ->
        OpenAI.embed_batch(texts)
      end)
  """
  @spec batch_span(keyword(), (-> result)) :: result when result: any()
  def batch_span(metadata, fun) when is_function(fun, 0) do
    enriched_metadata = enrich_batch_metadata(metadata)

    :telemetry.span(
      [:portfolio, :embedder, :embed_batch],
      Map.new(enriched_metadata),
      fn ->
        result = fun.()
        stop_meta = enrich_batch_stop_metadata(result, enriched_metadata)
        {result, stop_meta}
      end
    )
  end

  # Private functions

  defp enrich_start_metadata(metadata) do
    base =
      metadata
      |> Keyword.take([:model, :provider, :text_length])
      |> Keyword.put_new(:model, "unknown")

    # Calculate text length if text provided
    case Keyword.get(metadata, :text) do
      text when is_binary(text) ->
        Keyword.put_new(base, :text_length, String.length(text))

      _ ->
        base
    end
  end

  defp enrich_stop_metadata({:ok, result}, _start_metadata) when is_map(result) do
    %{
      dimensions: result[:dimensions] || length(result[:vector] || []),
      token_count: result[:token_count]
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp enrich_stop_metadata({:error, _reason}, _start_metadata) do
    %{success: false}
  end

  defp enrich_stop_metadata(_result, _start_metadata) do
    %{}
  end

  defp enrich_batch_metadata(metadata) do
    base =
      metadata
      |> Keyword.take([:model, :provider, :batch_size])
      |> Keyword.put_new(:model, "unknown")

    # Calculate batch size if texts provided
    case Keyword.get(metadata, :texts) do
      texts when is_list(texts) ->
        Keyword.put_new(base, :batch_size, length(texts))

      _ ->
        base
    end
  end

  defp enrich_batch_stop_metadata({:ok, result}, _start_metadata) when is_map(result) do
    count = length(result[:embeddings] || [])

    %{
      count: count,
      total_tokens: result[:total_tokens]
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp enrich_batch_stop_metadata({:error, _reason}, _start_metadata) do
    %{success: false}
  end

  defp enrich_batch_stop_metadata(_result, _start_metadata) do
    %{}
  end
end
