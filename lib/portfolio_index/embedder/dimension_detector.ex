defmodule PortfolioIndex.Embedder.DimensionDetector do
  @moduledoc """
  Utilities for detecting embedding dimensions from various sources.

  ## Detection Order

  When detecting dimensions, this module tries in order:
  1. Explicit `:dimensions` option
  2. Model registry lookup
  3. Module's `dimensions/1` function
  4. Probe embedding (generate test embedding and measure)

  ## Examples

      # From options
      {:ok, 768} = DimensionDetector.detect(MyEmbedder, dimensions: 768)

      # From registry
      {:ok, 1536} = DimensionDetector.detect(OpenAI, model: "text-embedding-3-small")

      # Probe unknown embedder
      {:ok, dims} = DimensionDetector.probe(embedder, [])
  """

  alias PortfolioIndex.Embedder.Registry

  @doc """
  Detect dimensions for an embedder configuration.

  Tries in order:
  1. Explicit :dimensions option
  2. Model registry lookup
  3. Module's dimensions function

  For probing (embedding a test string), use `probe/2`.
  """
  @spec detect(module() | struct(), keyword()) :: {:ok, pos_integer() | nil} | {:error, term()}
  def detect(embedder, opts \\ [])

  def detect(_embedder, opts) when is_list(opts) do
    # 1. Check explicit dimensions option
    case Keyword.get(opts, :dimensions) do
      dims when is_integer(dims) and dims > 0 ->
        {:ok, dims}

      nil ->
        # 2. Try to detect from model
        model = Keyword.get(opts, :model)
        detect_from_model(model, opts)

      _other ->
        {:ok, nil}
    end
  end

  @doc """
  Probe an embedder by generating an embedding and measuring dimensions.

  This is a fallback when dimensions aren't known statically.
  Uses an empty string to minimize API costs.
  """
  @spec probe(module() | struct(), keyword()) :: {:ok, pos_integer()} | {:error, term()}
  def probe(embedder, opts \\ [])

  # Handle struct embedders (like Function)
  def probe(%module{} = embedder, opts) do
    case apply(module, :embed, [embedder, "test", opts]) do
      {:ok, %{vector: vector}} when is_list(vector) ->
        {:ok, length(vector)}

      {:ok, %{dimensions: dims}} when is_integer(dims) ->
        {:ok, dims}

      {:error, reason} ->
        {:error, {:probe_failed, reason}}
    end
  end

  # Handle module embedders
  def probe(module, opts) when is_atom(module) do
    case module.embed("test", opts) do
      {:ok, %{vector: vector}} when is_list(vector) ->
        {:ok, length(vector)}

      {:ok, %{dimensions: dims}} when is_integer(dims) ->
        {:ok, dims}

      {:error, reason} ->
        {:error, {:probe_failed, reason}}
    end
  end

  @doc """
  Validate that an embedding has the expected dimensions.
  """
  @spec validate_dimensions([float()], pos_integer()) :: :ok | {:error, term()}
  def validate_dimensions(embedding, expected_dimensions) when is_list(embedding) do
    actual = length(embedding)

    if actual == expected_dimensions do
      :ok
    else
      {:error, {:dimension_mismatch, expected_dimensions, actual}}
    end
  end

  @doc """
  Detect dimensions from the model registry.
  """
  @spec detect_from_registry(String.t()) :: {:ok, pos_integer() | nil}
  def detect_from_registry(model_name) when is_binary(model_name) do
    {:ok, Registry.dimensions(model_name)}
  end

  # Private functions

  defp detect_from_model(nil, _opts) do
    {:ok, nil}
  end

  defp detect_from_model(model, _opts) when is_binary(model) do
    case Registry.dimensions(model) do
      nil ->
        # Try module's dimensions function if we have a module
        {:ok, nil}

      dims ->
        {:ok, dims}
    end
  end

  defp detect_from_model(model, opts) when is_atom(model) do
    detect_from_model(Atom.to_string(model), opts)
  end
end
