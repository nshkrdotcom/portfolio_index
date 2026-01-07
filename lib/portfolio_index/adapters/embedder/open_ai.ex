defmodule PortfolioIndex.Adapters.Embedder.OpenAI do
  @moduledoc """
  OpenAI embeddings adapter using the text-embedding API.

  Implements the `PortfolioCore.Ports.Embedder` behaviour.

  ## Configuration

  Set the API key via environment variable or config:

      config :portfolio_index, PortfolioIndex.Adapters.Embedder.OpenAI,
        api_key: System.get_env("OPENAI_API_KEY"),
        model: "text-embedding-3-small"

  ## Models

  - `text-embedding-3-small` - 1536 dimensions (default)
  - `text-embedding-3-large` - 3072 dimensions
  - `text-embedding-ada-002` - 1536 dimensions (legacy)

  ## Example

      {:ok, result} = OpenAI.embed("Hello, world!", [])
      # => {:ok, %{vector: [...], model: "text-embedding-3-small", dimensions: 1536, token_count: 3}}

      {:ok, result} = OpenAI.embed("Hello", model: "text-embedding-3-large")
      # => {:ok, %{vector: [...], dimensions: 3072, ...}}
  """

  @behaviour PortfolioCore.Ports.Embedder

  require Logger

  alias PortfolioIndex.Adapters.RateLimiter

  @default_model "text-embedding-3-small"
  @default_api_url "https://api.openai.com/v1/embeddings"

  @model_dimensions %{
    "text-embedding-3-small" => 1536,
    "text-embedding-3-large" => 3072,
    "text-embedding-ada-002" => 1536
  }

  @impl true
  @spec embed(String.t(), keyword()) ::
          {:ok, PortfolioCore.Ports.Embedder.embedding_result()} | {:error, term()}
  def embed(text, opts \\ []) do
    # Wait for rate limiter before making request
    RateLimiter.wait(:openai_embeddings, :embed)

    start_time = System.monotonic_time(:millisecond)

    result =
      with {:ok, api_key} <- get_api_key(opts),
           {:ok, response} <- call_api([text], api_key, opts) do
        model = Keyword.get(opts, :model, @default_model)
        [embedding_data | _] = response["data"]
        usage = response["usage"]

        duration = System.monotonic_time(:millisecond) - start_time

        emit_telemetry(
          :embed,
          %{
            duration_ms: duration,
            tokens: usage["total_tokens"],
            dimensions: length(embedding_data["embedding"])
          },
          %{model: model}
        )

        {:ok,
         %{
           vector: embedding_data["embedding"],
           model: model,
           dimensions: length(embedding_data["embedding"]),
           token_count: usage["total_tokens"]
         }}
      end

    case result do
      {:ok, _} = success ->
        RateLimiter.record_success(:openai_embeddings, :embed)
        success

      {:error, reason} = error ->
        failure_type = detect_failure_type(reason)
        RateLimiter.record_failure(:openai_embeddings, :embed, failure_type)
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
    start_time = System.monotonic_time(:millisecond)

    with {:ok, api_key} <- get_api_key(opts),
         {:ok, response} <- call_api(texts, api_key, opts) do
      model = Keyword.get(opts, :model, @default_model)
      usage = response["usage"]

      # Sort by index to maintain order
      sorted_data =
        response["data"]
        |> Enum.sort_by(& &1["index"])

      embeddings =
        Enum.map(sorted_data, fn data ->
          %{
            vector: data["embedding"],
            model: model,
            dimensions: length(data["embedding"]),
            token_count: div(usage["total_tokens"], length(texts))
          }
        end)

      duration = System.monotonic_time(:millisecond) - start_time

      emit_telemetry(
        :embed_batch,
        %{
          duration_ms: duration,
          count: length(texts),
          total_tokens: usage["total_tokens"]
        },
        %{model: model}
      )

      {:ok,
       %{
         embeddings: embeddings,
         total_tokens: usage["total_tokens"]
       }}
    end
  end

  @impl true
  @spec dimensions(String.t()) :: pos_integer() | nil
  def dimensions(model) do
    Map.get(@model_dimensions, model)
  end

  @impl true
  @spec supported_models() :: [String.t()]
  def supported_models do
    Map.keys(@model_dimensions)
  end

  @doc """
  Get dimension for a specific model.

  Returns `nil` for unknown models.
  """
  @spec model_dimensions(String.t()) :: pos_integer() | nil
  def model_dimensions(model) do
    Map.get(@model_dimensions, model)
  end

  # Private functions

  defp get_api_key(opts) do
    # If api_key is explicitly set to nil in opts, return error
    if Keyword.has_key?(opts, :api_key) and Keyword.get(opts, :api_key) == nil do
      {:error, :missing_api_key}
    else
      case Keyword.get(opts, :api_key) do
        nil ->
          config_key =
            Application.get_env(:portfolio_index, __MODULE__, [])
            |> Keyword.get(:api_key)

          env_key = System.get_env("OPENAI_API_KEY")

          case config_key || env_key do
            nil -> {:error, :missing_api_key}
            key -> {:ok, key}
          end

        key ->
          {:ok, key}
      end
    end
  end

  defp call_api(texts, api_key, opts) do
    model = Keyword.get(opts, :model, @default_model)
    api_url = Keyword.get(opts, :api_url, @default_api_url)

    input = if length(texts) == 1, do: hd(texts), else: texts

    body =
      %{
        "model" => model,
        "input" => input
      }
      |> Jason.encode!()

    headers = [
      {"authorization", "Bearer #{api_key}"},
      {"content-type", "application/json"}
    ]

    case Req.post(api_url, body: body, headers: headers) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        error_message = get_in(body, ["error", "message"]) || "API error"
        Logger.error("OpenAI API error (#{status}): #{error_message}")
        {:error, {:api_error, status, error_message}}

      {:error, reason} ->
        Logger.error("OpenAI API request failed: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  defp emit_telemetry(operation, measurements, metadata) do
    :telemetry.execute(
      [:portfolio_index, :embedder, operation],
      measurements,
      metadata
    )
  end

  defp detect_failure_type(reason) do
    reason_str = inspect(reason) |> String.downcase()

    cond do
      String.contains?(reason_str, "rate") or String.contains?(reason_str, "429") or
          String.contains?(reason_str, "quota") ->
        :rate_limited

      String.contains?(reason_str, "timeout") ->
        :timeout

      true ->
        :server_error
    end
  end
end
