defmodule PortfolioIndex.Adapters.Embedder.Ollama do
  @moduledoc """
  Ollama embeddings adapter using the `ollixir` client library.

  Implements the `PortfolioCore.Ports.Embedder` behaviour.

  ## Configuration

      config :portfolio_index, PortfolioIndex.Adapters.Embedder.Ollama,
        base_url: "http://localhost:11434/api",
        model: "nomic-embed-text"

  ## Models

  - `nomic-embed-text` - 768 dimensions (default)
  - `mxbai-embed-large` - 1024 dimensions

  ## Example

      {:ok, result} = Ollama.embed("Hello, world!", [])
      # => {:ok, %{vector: [...], model: "nomic-embed-text", dimensions: 768, token_count: 3}}
  """

  @behaviour PortfolioCore.Ports.Embedder

  require Logger

  alias PortfolioIndex.Adapters.RateLimiter
  alias PortfolioIndex.Embedder.Registry

  @default_model "nomic-embed-text"

  @impl true
  @spec embed(String.t(), keyword()) ::
          {:ok, PortfolioCore.Ports.Embedder.embedding_result()} | {:error, term()}
  def embed(text, opts \\ []) do
    RateLimiter.wait(:ollama_embeddings, :embed)
    start_time = System.monotonic_time(:millisecond)

    result =
      with {:ok, client} <- build_client(opts),
           {:ok, response} <- sdk().embed(client, build_embed_params(text, opts)),
           {:ok, embedding} <- first_embedding(response) do
        model = response_model(response) || effective_model(opts)
        token_count = prompt_eval_count(response) || estimate_tokens(text)
        duration = System.monotonic_time(:millisecond) - start_time

        emit_telemetry(
          :embed,
          %{
            duration_ms: duration,
            tokens: token_count,
            dimensions: length(embedding)
          },
          %{model: model}
        )

        {:ok,
         %{
           vector: embedding,
           model: model,
           dimensions: length(embedding),
           token_count: token_count
         }}
      end

    case result do
      {:ok, _} = success ->
        RateLimiter.record_success(:ollama_embeddings, :embed)
        success

      {:error, reason} = error ->
        RateLimiter.record_failure(:ollama_embeddings, :embed, detect_failure_type(reason))
        Logger.error("Ollama embedding failed: #{inspect(reason)}")
        error
    end
  end

  @impl true
  @spec embed_batch([String.t()], keyword()) ::
          {:ok, PortfolioCore.Ports.Embedder.batch_result()} | {:error, term()}
  def embed_batch(texts, opts \\ [])

  def embed_batch([], _opts) do
    {:ok, %{embeddings: [], total_tokens: 0}}
  end

  def embed_batch(texts, opts) when is_list(texts) do
    RateLimiter.wait(:ollama_embeddings, :embed_batch)
    start_time = System.monotonic_time(:millisecond)

    result =
      with {:ok, client} <- build_client(opts),
           {:ok, response} <- sdk().embed(client, build_embed_params(texts, opts)) do
        model = response_model(response) || effective_model(opts)

        case normalize_embeddings(texts, response, model) do
          {:ok, normalized} ->
            total_tokens = batch_token_count(texts, response)
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
               embeddings: normalized,
               total_tokens: total_tokens
             }}

          {:error, reason} ->
            {:error, reason}
        end
      end

    case result do
      {:ok, _} = success ->
        RateLimiter.record_success(:ollama_embeddings, :embed_batch)
        success

      {:error, reason} = error ->
        RateLimiter.record_failure(:ollama_embeddings, :embed_batch, detect_failure_type(reason))
        Logger.error("Ollama batch embedding failed: #{inspect(reason)}")
        error
    end
  end

  @impl true
  @spec dimensions(String.t()) :: pos_integer() | nil
  def dimensions(model) do
    Registry.dimensions(model)
  end

  @impl true
  @spec supported_models() :: [String.t()]
  def supported_models do
    Registry.list_by_provider(:ollama)
  end

  defp build_client(opts) do
    client_opts =
      []
      |> maybe_put(:base_url, Keyword.get(opts, :base_url) || configured_base_url())
      |> maybe_put(:receive_timeout, Keyword.get(opts, :receive_timeout) || configured_timeout())
      |> maybe_put(:headers, Keyword.get(opts, :headers) || configured_headers())

    {:ok, sdk().init(client_opts)}
  end

  defp build_embed_params(input, opts) do
    model = effective_model(opts)
    options = build_options(opts)

    []
    |> Keyword.put(:model, model)
    |> Keyword.put(:input, input)
    |> Keyword.put(:response_format, :struct)
    |> maybe_put(:dimensions, Keyword.get(opts, :dimensions))
    |> maybe_put(:truncate, Keyword.get(opts, :truncate))
    |> maybe_put(:keep_alive, Keyword.get(opts, :keep_alive))
    |> maybe_put(:options, empty_map_to_nil(options))
  end

  defp build_options(opts) do
    base =
      case Keyword.get(opts, :options) do
        options when is_map(options) -> options
        options when is_list(options) -> Map.new(options)
        _ -> %{}
      end

    case Keyword.get(opts, :extra) do
      extra when is_map(extra) -> Map.merge(extra, base)
      extra when is_list(extra) -> Map.merge(Map.new(extra), base)
      _ -> base
    end
  end

  defp normalize_embeddings(texts, response, model) do
    embeddings = extract_embeddings(response)

    cond do
      embeddings == [] ->
        {:error, :no_embeddings}

      length(embeddings) != length(texts) ->
        {:error, :embedding_count_mismatch}

      true ->
        prompt_tokens = prompt_eval_count(response)
        per_item_tokens = per_item_tokens(prompt_tokens, length(texts))

        embedded =
          Enum.zip(texts, embeddings)
          |> Enum.map(fn {text, vector} ->
            %{
              vector: vector,
              model: model,
              dimensions: length(vector),
              token_count: per_item_tokens || estimate_tokens(text)
            }
          end)

        {:ok, embedded}
    end
  end

  defp batch_token_count(texts, response) do
    prompt_eval_count(response) ||
      Enum.reduce(texts, 0, fn text, acc -> acc + estimate_tokens(text) end)
  end

  defp per_item_tokens(nil, _count), do: nil
  defp per_item_tokens(_total, 0), do: nil
  defp per_item_tokens(total, count), do: div(total, count)

  defp first_embedding(response) do
    case extract_embeddings(response) do
      [embedding | _] -> {:ok, embedding}
      _ -> {:error, :no_embeddings}
    end
  end

  defp extract_embeddings(%Ollixir.Types.EmbedResponse{embeddings: embeddings}), do: embeddings
  defp extract_embeddings(%{"embeddings" => embeddings}) when is_list(embeddings), do: embeddings
  defp extract_embeddings(%{"embedding" => embedding}) when is_list(embedding), do: [embedding]
  defp extract_embeddings(_), do: []

  defp response_model(%Ollixir.Types.EmbedResponse{model: model}), do: model
  defp response_model(%{"model" => model}) when is_binary(model), do: model
  defp response_model(_), do: nil

  defp prompt_eval_count(%Ollixir.Types.EmbedResponse{prompt_eval_count: count})
       when is_integer(count) do
    count
  end

  defp prompt_eval_count(%{"prompt_eval_count" => count}) when is_integer(count), do: count
  defp prompt_eval_count(_), do: nil

  defp effective_model(opts) do
    Keyword.get(opts, :model) || configured_model() || @default_model
  end

  defp config do
    Application.get_env(:portfolio_index, __MODULE__, [])
  end

  defp shared_config do
    Application.get_env(:portfolio_index, :ollama, [])
  end

  defp configured_base_url do
    Keyword.get(config(), :base_url) || Keyword.get(shared_config(), :base_url)
  end

  defp configured_model do
    Keyword.get(config(), :model)
  end

  defp configured_timeout do
    Keyword.get(config(), :receive_timeout) || Keyword.get(shared_config(), :receive_timeout)
  end

  defp configured_headers do
    Keyword.get(config(), :headers) || Keyword.get(shared_config(), :headers)
  end

  defp sdk do
    Application.get_env(:portfolio_index, :ollama_embedder_sdk, Ollixir)
  end

  defp detect_failure_type(%{status: status}) when status in [429], do: :rate_limited

  defp detect_failure_type(%{status: status}) when is_integer(status) and status >= 500,
    do: :server_error

  defp detect_failure_type(reason) do
    reason
    |> inspect()
    |> String.downcase()
    |> failure_type_from_reason()
  end

  defp failure_type_from_reason(reason) do
    cond do
      String.contains?(reason, "rate") or String.contains?(reason, "429") ->
        :rate_limited

      String.contains?(reason, "timeout") ->
        :timeout

      true ->
        :server_error
    end
  end

  defp estimate_tokens(text) do
    div(String.length(text), 4) + 1
  end

  defp emit_telemetry(operation, measurements, metadata) do
    :telemetry.execute(
      [:portfolio_index, :embedder, operation],
      measurements,
      metadata
    )
  end

  defp maybe_put(keyword, _key, nil), do: keyword
  defp maybe_put(keyword, key, value), do: Keyword.put(keyword, key, value)

  defp empty_map_to_nil(map) when map_size(map) == 0, do: nil
  defp empty_map_to_nil(map), do: map
end
