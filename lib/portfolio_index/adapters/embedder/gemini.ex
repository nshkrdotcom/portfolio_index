defmodule PortfolioIndex.Adapters.Embedder.Gemini do
  @moduledoc """
  Google Gemini embeddings adapter using gemini_ex.

  Implements the `PortfolioCore.Ports.Embedder` behaviour.

  ## Features

  - Single and batch embedding generation
  - Configurable output dimensions (128-3072)
  - Automatic normalization when required by the model
  - Rate limiting support

  ## Models

  Uses the gemini_ex registry defaults unless a model is supplied via options.

  ## Example

      {:ok, result} = Gemini.embed("Hello, world!", [])
      # => {:ok, %{vector: [...], model: "gemini-...", dimensions: 768, token_count: 3}}

      {:ok, result} = Gemini.embed("Hello", dimensions: 256)
      # => {:ok, %{vector: [...], dimensions: 256, ...}}
  """

  @behaviour PortfolioCore.Ports.Embedder

  # Suppress dialyzer warnings for gemini_ex API calls
  # The library's typespec may not fully represent runtime behavior
  @dialyzer [
    :no_return,
    :no_unused,
    {:no_fail_call, embed: 2}
  ]

  require Logger
  alias Gemini.Types.Response.ContentEmbedding
  alias Gemini.Types.Response.EmbedContentResponse

  @impl true
  def embed(text, opts) do
    start_time = System.monotonic_time(:millisecond)
    {model_opt, effective_model} = resolve_embedding_model(opts)
    dims = resolve_dimensions(opts, effective_model)

    gemini_opts =
      opts
      |> Keyword.delete(:model)
      |> Keyword.delete(:dimensions)
      |> Keyword.put(:output_dimensionality, dims)
      |> maybe_put(:model, model_opt)

    case Gemini.embed_content(text, gemini_opts) do
      {:ok, response} ->
        vector = extract_embedding(response)
        normalized_vector = maybe_normalize(vector, effective_model, dims)

        duration = System.monotonic_time(:millisecond) - start_time
        token_count = estimate_tokens(text)

        emit_telemetry(
          :embed,
          %{
            duration_ms: duration,
            tokens: token_count,
            dimensions: dims
          },
          %{model: effective_model}
        )

        {:ok,
         %{
           vector: normalized_vector,
           model: effective_model,
           dimensions: length(normalized_vector),
           token_count: token_count
         }}

      {:error, reason} ->
        Logger.error("Embedding failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def embed_batch(texts, opts) when is_list(texts) do
    start_time = System.monotonic_time(:millisecond)
    {_model_opt, effective_model} = resolve_embedding_model(opts)
    # dims is used in the individual embed calls via opts passthrough

    # Gemini supports batch embedding via multiple calls
    # gemini_ex may have batch support - check and use if available
    results =
      Enum.map(texts, fn text ->
        case embed(text, opts) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:error, reason}
        end
      end)

    # Check if any failed
    errors = Enum.filter(results, &match?({:error, _}, &1))

    if Enum.empty?(errors) do
      embeddings = Enum.map(results, fn {:ok, result} -> result end)
      total_tokens = Enum.sum(Enum.map(embeddings, & &1.token_count))

      duration = System.monotonic_time(:millisecond) - start_time

      emit_telemetry(
        :embed_batch,
        %{
          duration_ms: duration,
          count: length(texts),
          total_tokens: total_tokens
        },
        %{model: effective_model}
      )

      {:ok,
       %{
         embeddings: embeddings,
         total_tokens: total_tokens
       }}
    else
      # Return first error
      List.first(errors)
    end
  end

  @impl true
  def dimensions(model) do
    Gemini.Config.default_embedding_dimensions(model) || default_dimensions()
  end

  @impl true
  def supported_models do
    Gemini.Config.models_for(Gemini.Config.current_api_type())
    |> Map.values()
    |> Enum.filter(&embedding_model?/1)
  end

  # Private functions

  defp extract_embedding(%EmbedContentResponse{embedding: embedding}),
    do: extract_embedding(embedding)

  defp extract_embedding(%ContentEmbedding{values: values}), do: values

  defp resolve_embedding_model(opts) do
    case Keyword.get(opts, :model) do
      nil ->
        {nil, Gemini.Config.default_embedding_model()}

      model_key when is_atom(model_key) ->
        resolved =
          Gemini.Config.get_model(model_key,
            api: Gemini.Config.current_api_type(),
            strict: true
          )

        {resolved, resolved}

      model_name when is_binary(model_name) ->
        {model_name, model_name}
    end
  end

  defp resolve_dimensions(opts, model) do
    case Keyword.get(opts, :dimensions) do
      nil ->
        default_dimensions() || Gemini.Config.default_embedding_dimensions(model) || 768

      dims ->
        dims
    end
  end

  defp default_dimensions do
    Application.get_env(:portfolio_index, :embedding, [])
    |> Keyword.get(:default_dimensions)
  end

  defp embedding_model?(model) when is_binary(model) do
    not is_nil(Gemini.Config.embedding_config(model))
  end

  defp embedding_model?(_), do: false

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp maybe_normalize(vector, model, dims) do
    if Gemini.Config.needs_normalization?(model, dims) do
      normalize(vector)
    else
      vector
    end
  end

  defp normalize([_ | _] = vector) do
    magnitude = :math.sqrt(Enum.reduce(vector, 0, fn x, acc -> acc + x * x end))

    if magnitude > 0 do
      Enum.map(vector, fn x -> x / magnitude end)
    else
      vector
    end
  end

  defp normalize(vector), do: vector

  defp estimate_tokens(text) do
    # Rough estimation: ~4 characters per token for English
    # This is an approximation - actual token count would require tokenizer
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
