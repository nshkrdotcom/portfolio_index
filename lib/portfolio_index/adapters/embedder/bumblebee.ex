defmodule PortfolioIndex.Adapters.Embedder.Bumblebee do
  @moduledoc """
  Local embeddings using Bumblebee and Nx.Serving.
  Runs HuggingFace models locally without API calls.

  Implements the `PortfolioCore.Ports.Embedder` behaviour.

  ## Configuration

      config :portfolio_index, PortfolioIndex.Adapters.Embedder.Bumblebee,
        model: "BAAI/bge-small-en-v1.5",
        serving_name: PortfolioIndex.EmbeddingServing

  ## Models

  - `BAAI/bge-small-en-v1.5` - 384 dimensions (default, fast)
  - `BAAI/bge-base-en-v1.5` - 768 dimensions
  - `BAAI/bge-large-en-v1.5` - 1024 dimensions
  - `sentence-transformers/all-MiniLM-L6-v2` - 384 dimensions

  ## Setup

  Add to your supervision tree:

      children = [
        {PortfolioIndex.Adapters.Embedder.Bumblebee, name: PortfolioIndex.EmbeddingServing}
      ]

  ## Requirements

  This adapter requires the following dependencies:

      {:bumblebee, "~> 0.5"},
      {:exla, "~> 0.7"},
      {:nx, "~> 0.7"}

  ## Example

      {:ok, result} = Bumblebee.embed("Hello, world!", [])
      # => {:ok, %{vector: [...], model: "BAAI/bge-small-en-v1.5", dimensions: 384, token_count: 3}}
  """

  @behaviour PortfolioCore.Ports.Embedder

  use GenServer

  require Logger

  # Suppress dialyzer warnings for optional Bumblebee/Nx dependencies
  @dialyzer [
    :no_return,
    :no_unused,
    {:nowarn_function, init: 1},
    {:nowarn_function, embed: 2},
    {:nowarn_function, embed_batch: 2}
  ]

  @default_model "BAAI/bge-small-en-v1.5"

  @model_dimensions %{
    "BAAI/bge-small-en-v1.5" => 384,
    "BAAI/bge-base-en-v1.5" => 768,
    "BAAI/bge-large-en-v1.5" => 1024,
    "sentence-transformers/all-MiniLM-L6-v2" => 384
  }

  # GenServer callbacks

  @doc """
  Returns the child spec for starting the embedding serving.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    model = Keyword.get(opts, :model, @default_model)
    serving_name = serving_name(model)

    %{
      id: serving_name,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker
    }
  end

  @doc """
  Starts the Nx.Serving for this embedder.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name))
  end

  @impl GenServer
  def init(opts) do
    model = Keyword.get(opts, :model, @default_model)

    # Check if Bumblebee is available
    unless Code.ensure_loaded?(Bumblebee) do
      raise """
      Bumblebee is required for local embeddings but is not available.

      Add these dependencies to your mix.exs:
        {:bumblebee, "~> 0.5"},
        {:exla, "~> 0.7"},
        {:nx, "~> 0.7"}
      """
    end

    Logger.info("Loading embedding model: #{model}")

    # Load model and tokenizer from HuggingFace Hub (using apply to avoid compile warnings)
    {:ok, model_info} = apply(Bumblebee, :load_model, [{:hf, model}])
    {:ok, tokenizer} = apply(Bumblebee, :load_tokenizer, [{:hf, model}])

    # Create the text embedding serving
    serving =
      apply(Bumblebee.Text.TextEmbedding, :text_embedding, [
        model_info,
        tokenizer,
        [
          compile: [batch_size: 32, sequence_length: 512],
          defn_options: [compiler: EXLA]
        ]
      ])

    # Start the Nx.Serving
    {:ok, serving_pid} =
      Nx.Serving.start_link(serving: serving, name: serving_name(model), batch_timeout: 100)

    Logger.info("Embedding serving started for model: #{model}")

    {:ok,
     %{
       model: model,
       serving_pid: serving_pid,
       serving_name: serving_name(model)
     }}
  end

  # Behaviour implementations

  @impl PortfolioCore.Ports.Embedder
  @spec embed(String.t(), keyword()) ::
          {:ok, PortfolioCore.Ports.Embedder.embedding_result()} | {:error, term()}
  def embed(text, opts \\ []) do
    model = Keyword.get(opts, :model, @default_model)
    serving_name = Keyword.get(opts, :serving_name, serving_name(model))

    start_time = System.monotonic_time(:millisecond)

    try do
      %{embedding: embedding} = Nx.Serving.batched_run(serving_name, text)
      vector = Nx.to_flat_list(embedding)
      token_count = estimate_tokens(text)

      duration = System.monotonic_time(:millisecond) - start_time

      emit_telemetry(
        :embed,
        %{
          duration_ms: duration,
          tokens: token_count,
          dimensions: length(vector)
        },
        %{model: model}
      )

      {:ok,
       %{
         vector: vector,
         model: model,
         dimensions: length(vector),
         token_count: token_count
       }}
    rescue
      ArgumentError ->
        {:error, {:serving_not_found, serving_name}}

      e ->
        Logger.error("Bumblebee embedding failed: #{inspect(e)}")
        {:error, {:embedding_failed, e}}
    catch
      :exit, {:noproc, _} ->
        {:error, {:serving_not_found, serving_name}}

      :exit, reason ->
        Logger.error("Bumblebee embedding exit: #{inspect(reason)}")
        {:error, {:embedding_failed, reason}}
    end
  end

  @impl PortfolioCore.Ports.Embedder
  @spec embed_batch([String.t()], keyword()) ::
          {:ok, PortfolioCore.Ports.Embedder.batch_result()} | {:error, term()}
  def embed_batch(texts, opts \\ [])

  def embed_batch([], _opts) do
    {:ok, %{embeddings: [], total_tokens: 0}}
  end

  def embed_batch(texts, opts) when is_list(texts) do
    model = Keyword.get(opts, :model, @default_model)
    serving_name = Keyword.get(opts, :serving_name, serving_name(model))

    start_time = System.monotonic_time(:millisecond)

    try do
      # Batch process all texts
      results =
        Enum.map(texts, fn text ->
          %{embedding: embedding} = Nx.Serving.batched_run(serving_name, text)
          vector = Nx.to_flat_list(embedding)
          token_count = estimate_tokens(text)

          %{
            vector: vector,
            model: model,
            dimensions: length(vector),
            token_count: token_count
          }
        end)

      total_tokens = Enum.sum(Enum.map(results, & &1.token_count))
      duration = System.monotonic_time(:millisecond) - start_time

      emit_telemetry(
        :embed_batch,
        %{
          duration_ms: duration,
          count: length(texts),
          total_tokens: total_tokens
        },
        %{model: model}
      )

      {:ok,
       %{
         embeddings: results,
         total_tokens: total_tokens
       }}
    rescue
      ArgumentError ->
        {:error, {:serving_not_found, serving_name}}

      e ->
        Logger.error("Bumblebee batch embedding failed: #{inspect(e)}")
        {:error, {:embedding_failed, e}}
    catch
      :exit, {:noproc, _} ->
        {:error, {:serving_not_found, serving_name}}

      :exit, reason ->
        Logger.error("Bumblebee batch embedding exit: #{inspect(reason)}")
        {:error, {:embedding_failed, reason}}
    end
  end

  @impl PortfolioCore.Ports.Embedder
  @spec dimensions(String.t()) :: pos_integer() | nil
  def dimensions(model) do
    Map.get(@model_dimensions, model)
  end

  @impl PortfolioCore.Ports.Embedder
  @spec supported_models() :: [String.t()]
  def supported_models do
    Map.keys(@model_dimensions)
  end

  @doc """
  Check if the serving is ready.
  """
  @spec ready?(atom()) :: boolean()
  def ready?(serving_name \\ serving_name(@default_model)) do
    case Process.whereis(serving_name) do
      nil -> false
      pid -> Process.alive?(pid)
    end
  end

  # Private functions

  defp serving_name(model) do
    Module.concat(__MODULE__, String.to_atom(model))
  end

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
