defmodule PortfolioIndex.Embedder.Config do
  @moduledoc """
  Unified configuration for embedder selection and initialization.
  Supports shorthand syntax and automatic adapter resolution.

  ## Configuration Examples

      # Shorthand - provider atom
      config :portfolio_index, :embedder, :openai

      # Shorthand with model
      config :portfolio_index, :embedder, {:openai, model: "text-embedding-3-large"}

      # Full module specification
      config :portfolio_index, :embedder, PortfolioIndex.Adapters.Embedder.OpenAI

      # Module with options
      config :portfolio_index, :embedder, {PortfolioIndex.Adapters.Embedder.OpenAI, api_key: "..."}

      # Custom function (requires dimensions)
      embed_fn = fn text -> {:ok, MyEmbed.embed(text)} end
      config :portfolio_index, :embedder, {embed_fn, dimensions: 768}

  ## Usage

      # Get resolved embedder
      {module, opts} = PortfolioIndex.Embedder.Config.current()

      # Get dimensions for current embedder
      dims = PortfolioIndex.Embedder.Config.current_dimensions()
  """

  alias PortfolioIndex.Adapters.Embedder
  alias PortfolioIndex.Embedder.Registry

  @type embedder_config ::
          atom()
          | {atom(), keyword()}
          | module()
          | {module(), keyword()}
          | {function(), keyword()}

  @provider_modules %{
    openai: Embedder.OpenAI,
    bumblebee: Embedder.Bumblebee,
    ollama: Embedder.Ollama,
    gemini: Embedder.Gemini,
    function: Embedder.Function
  }

  @default_models %{
    openai: "text-embedding-3-small",
    bumblebee: "BAAI/bge-small-en-v1.5",
    ollama: "nomic-embed-text"
  }

  @doc """
  Resolve embedder config to a module and options.

  Accepts various configuration formats and normalizes them to `{module, opts}`.

  ## Examples

      iex> Config.resolve(:openai)
      {:ok, {PortfolioIndex.Adapters.Embedder.OpenAI, []}}

      iex> Config.resolve({:openai, model: "text-embedding-3-large"})
      {:ok, {PortfolioIndex.Adapters.Embedder.OpenAI, [model: "text-embedding-3-large"]}}
  """
  @spec resolve(embedder_config()) :: {:ok, {module(), keyword()}} | {:error, term()}
  def resolve(config)

  # Provider atom: :openai, :bumblebee, etc.
  def resolve(provider) when is_atom(provider) and not is_nil(provider) do
    case Map.get(@provider_modules, provider) do
      nil ->
        # Check if it's a module
        if Code.ensure_loaded?(provider) and
             function_exported?(provider, :embed, 2) do
          {:ok, {provider, []}}
        else
          {:error, {:unknown_provider, provider}}
        end

      module ->
        {:ok, {module, []}}
    end
  end

  # Provider with options: {:openai, model: "..."}
  def resolve({provider, opts}) when is_atom(provider) and is_list(opts) do
    case Map.get(@provider_modules, provider) do
      nil ->
        # Check if it's a module
        if Code.ensure_loaded?(provider) and
             function_exported?(provider, :embed, 2) do
          {:ok, {provider, opts}}
        else
          {:error, {:unknown_provider, provider}}
        end

      module ->
        {:ok, {module, opts}}
    end
  end

  # Function with options: {fn -> ... end, dimensions: 768}
  def resolve({func, opts}) when is_function(func, 1) and is_list(opts) do
    {:ok, {Embedder.Function, Keyword.put(opts, :embed_fn, func)}}
  end

  def resolve(nil) do
    {:error, :no_config}
  end

  @doc """
  Get the current embedder from application config.

  Falls back to OpenAI if not configured.
  """
  @spec current() :: {module(), keyword()}
  def current do
    config = Application.get_env(:portfolio_index, :embedder, :openai)

    case resolve(config) do
      {:ok, {module, opts}} -> {module, opts}
      {:error, _} -> {Embedder.OpenAI, []}
    end
  end

  @doc """
  Get dimensions for current embedder.

  Uses the Registry to look up dimensions based on the configured model,
  or falls back to the module's dimensions function.
  """
  @spec current_dimensions() :: pos_integer()
  def current_dimensions do
    {module, opts} = current()

    model =
      case Keyword.get(opts, :model) do
        nil -> get_default_model(module)
        model -> model
      end

    case Registry.dimensions(model) do
      nil ->
        # Fall back to module's dimensions function
        if function_exported?(module, :dimensions, 1) do
          module.dimensions(model) || 1536
        else
          1536
        end

      dims ->
        dims
    end
  end

  @doc """
  Validate embedder configuration.

  Returns `:ok` if valid, `{:error, reason}` otherwise.
  """
  @spec validate(embedder_config()) :: :ok | {:error, term()}
  def validate(config) do
    case resolve(config) do
      {:ok, {module, _opts}} ->
        if Code.ensure_loaded?(module) do
          :ok
        else
          {:error, {:module_not_loaded, module}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  defp get_default_model(module) do
    provider =
      @provider_modules
      |> Enum.find(fn {_k, v} -> v == module end)
      |> case do
        {provider, _module} -> provider
        nil -> nil
      end

    Map.get(@default_models, provider, "text-embedding-3-small")
  end
end
