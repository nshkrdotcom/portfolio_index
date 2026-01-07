defmodule PortfolioIndex.Embedder.Registry do
  @moduledoc """
  Registry of known embedding models and their dimensions.
  Used for auto-detection and validation.

  ## Built-in Models

  The registry includes pre-configured models from:
  - OpenAI (text-embedding-3-small/large, ada-002)
  - Voyage (voyage-3, voyage-code-3)
  - Bumblebee/HuggingFace (BGE, MiniLM)
  - Ollama (nomic-embed-text, mxbai-embed-large)

  ## Custom Models

  Register custom models at runtime:

      PortfolioIndex.Embedder.Registry.register("my-model", :custom, 768)
  """

  use Agent

  @builtin_models %{
    # OpenAI
    "text-embedding-3-small" => %{provider: :openai, dimensions: 1536},
    "text-embedding-3-large" => %{provider: :openai, dimensions: 3072},
    "text-embedding-ada-002" => %{provider: :openai, dimensions: 1536},

    # Voyage
    "voyage-3" => %{provider: :voyage, dimensions: 1024},
    "voyage-3-lite" => %{provider: :voyage, dimensions: 512},
    "voyage-code-3" => %{provider: :voyage, dimensions: 1024},

    # Bumblebee/HuggingFace
    "BAAI/bge-small-en-v1.5" => %{provider: :bumblebee, dimensions: 384},
    "BAAI/bge-base-en-v1.5" => %{provider: :bumblebee, dimensions: 768},
    "BAAI/bge-large-en-v1.5" => %{provider: :bumblebee, dimensions: 1024},
    "sentence-transformers/all-MiniLM-L6-v2" => %{provider: :bumblebee, dimensions: 384},

    # Ollama
    "nomic-embed-text" => %{provider: :ollama, dimensions: 768},
    "mxbai-embed-large" => %{provider: :ollama, dimensions: 1024}
  }

  @doc false
  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @doc false
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker
    }
  end

  @doc """
  Get model info by name.

  Returns a map with `:provider` and `:dimensions` keys, or `nil` if not found.

  ## Examples

      iex> Registry.get("text-embedding-3-small")
      %{provider: :openai, dimensions: 1536}

      iex> Registry.get("unknown")
      nil
  """
  @spec get(String.t()) :: map() | nil
  def get(model_name) do
    case Map.get(@builtin_models, model_name) do
      nil -> get_custom(model_name)
      info -> info
    end
  end

  @doc """
  Get dimensions for a model.

  ## Examples

      iex> Registry.dimensions("text-embedding-3-small")
      1536
  """
  @spec dimensions(String.t()) :: pos_integer() | nil
  def dimensions(model_name) do
    case get(model_name) do
      %{dimensions: dims} -> dims
      nil -> nil
    end
  end

  @doc """
  Get provider for a model.

  ## Examples

      iex> Registry.provider("text-embedding-3-small")
      :openai
  """
  @spec provider(String.t()) :: atom() | nil
  def provider(model_name) do
    case get(model_name) do
      %{provider: provider} -> provider
      nil -> nil
    end
  end

  @doc """
  List all known models.

  Returns both built-in and registered custom models.
  """
  @spec list() :: [String.t()]
  def list do
    builtin = Map.keys(@builtin_models)
    custom = get_custom_models() |> Map.keys()
    builtin ++ custom
  end

  @doc """
  List models by provider.

  ## Examples

      iex> Registry.list_by_provider(:openai)
      ["text-embedding-3-small", "text-embedding-3-large", "text-embedding-ada-002"]
  """
  @spec list_by_provider(atom()) :: [String.t()]
  def list_by_provider(provider) do
    builtin =
      @builtin_models
      |> Enum.filter(fn {_name, info} -> info.provider == provider end)
      |> Enum.map(fn {name, _info} -> name end)

    custom =
      get_custom_models()
      |> Enum.filter(fn {_name, info} -> info.provider == provider end)
      |> Enum.map(fn {name, _info} -> name end)

    builtin ++ custom
  end

  @doc """
  Register a custom model.

  ## Examples

      iex> Registry.register("my-model", :custom, 768)
      :ok
  """
  @spec register(String.t(), atom(), pos_integer()) :: :ok
  def register(model_name, provider, dimensions) do
    ensure_started()

    Agent.update(__MODULE__, fn models ->
      Map.put(models, model_name, %{provider: provider, dimensions: dimensions})
    end)
  end

  @doc """
  Unregister a custom model.

  Only removes custom models, not built-in ones.
  """
  @spec unregister(String.t()) :: :ok
  def unregister(model_name) do
    ensure_started()

    Agent.update(__MODULE__, fn models ->
      Map.delete(models, model_name)
    end)
  end

  # Private functions

  defp get_custom(model_name) do
    ensure_started()

    Agent.get(__MODULE__, fn models ->
      Map.get(models, model_name)
    end)
  end

  defp get_custom_models do
    ensure_started()
    Agent.get(__MODULE__, & &1)
  end

  defp ensure_started do
    case Process.whereis(__MODULE__) do
      nil ->
        case start_link([]) do
          {:ok, pid} ->
            Process.unlink(pid)
            :ok

          {:error, {:already_started, _pid}} ->
            :ok
        end

      _pid ->
        :ok
    end
  end
end
