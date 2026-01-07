defmodule PortfolioIndex.Adapters.LLM.OpenAI do
  @behaviour PortfolioCore.Ports.LLM

  @moduledoc """
  OpenAI LLM adapter using openai_ex library for direct OpenAI API access.

  This adapter communicates directly with the OpenAI API using the openai_ex
  Hex library. It supports chat completions, streaming, and the Responses API.

  ## Configuration

      config :portfolio_index, :openai,
        api_key: System.get_env("OPENAI_API_KEY"),
        model: "gpt-4o-mini",
        receive_timeout: 30_000,
        base_url: nil  # Optional, for proxies or local LLMs

  ## Environment Variables

  - `OPENAI_API_KEY` - Your OpenAI API key (required)
  - `OPENAI_ORGANIZATION` - Optional organization ID

  ## Manifest

      adapters:
        llm:
          module: PortfolioIndex.Adapters.LLM.OpenAI
          config:
            model: "gpt-4o-mini"

  ## Example

      messages = [
        %{role: :system, content: "You are a helpful assistant."},
        %{role: :user, content: "What is Elixir?"}
      ]

      {:ok, result} = PortfolioIndex.Adapters.LLM.OpenAI.complete(messages, [])
  """

  require Logger

  alias OpenaiEx.Chat
  alias OpenaiEx.ChatMessage
  alias PortfolioIndex.Adapters.RateLimiter

  @default_model "gpt-4o-mini"
  @default_timeout 30_000

  @default_model_info %{
    context_window: 128_000,
    max_output: 16_384,
    supports_tools: true
  }

  @model_info %{
    "gpt-4o" => %{context_window: 128_000, max_output: 16_384, supports_tools: true},
    "gpt-4o-mini" => %{context_window: 128_000, max_output: 16_384, supports_tools: true},
    "gpt-4-turbo" => %{context_window: 128_000, max_output: 4096, supports_tools: true},
    "gpt-4" => %{context_window: 8_192, max_output: 8_192, supports_tools: true},
    "gpt-3.5-turbo" => %{context_window: 16_385, max_output: 4096, supports_tools: true},
    "o1" => %{context_window: 200_000, max_output: 100_000, supports_tools: false},
    "o1-mini" => %{context_window: 128_000, max_output: 65_536, supports_tools: false},
    "o3-mini" => %{context_window: 200_000, max_output: 100_000, supports_tools: true}
  }

  @impl true
  def complete(messages, opts \\ []) do
    # Wait for rate limiter before making request
    RateLimiter.wait(:openai, :chat)

    with {:ok, client} <- build_client(opts),
         {:ok, request} <- build_chat_request(messages, opts),
         {:ok, response} <- Chat.Completions.create(client, request) do
      RateLimiter.record_success(:openai, :chat)
      emit_telemetry(:complete, %{model: response["model"]})
      {:ok, normalize_response(response)}
    else
      {:error, :live_api_disabled} = error ->
        Logger.debug("OpenAI live API disabled; set base_url or allow_live_api to enable.")
        error

      {:error, reason} ->
        failure_type = detect_failure_type(reason)
        RateLimiter.record_failure(:openai, :chat, failure_type)
        Logger.error("OpenAI completion failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def stream(messages, opts \\ []) do
    with {:ok, client} <- build_client(opts),
         {:ok, request} <- build_chat_request(messages, opts) do
      request_with_stream = Map.put(request, :stream_options, %{include_usage: true})

      case Chat.Completions.create(client, request_with_stream, stream: true) do
        {:ok, stream_response} ->
          stream = build_stream(stream_response)
          {:ok, stream}

        {:error, reason} ->
          Logger.error("OpenAI streaming failed: #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def supported_models do
    Map.keys(@model_info)
  end

  @impl true
  def model_info(model) do
    Map.get(@model_info, model, @default_model_info)
  end

  # Client construction

  defp build_client(opts) do
    if live_api_allowed?(opts) do
      api_key = Keyword.get(opts, :api_key) || configured_api_key()

      if is_nil(api_key) or api_key == "" do
        {:error, :missing_api_key}
      else
        organization = Keyword.get(opts, :organization) || configured_organization()

        client =
          OpenaiEx.new(api_key, organization)
          |> apply_client_options(opts)

        {:ok, client}
      end
    else
      {:error, :live_api_disabled}
    end
  end

  defp apply_client_options(client, opts) do
    client
    |> maybe_set_timeout(opts)
    |> maybe_set_base_url(opts)
  end

  defp maybe_set_timeout(client, opts) do
    timeout =
      Keyword.get(opts, :receive_timeout) ||
        configured_timeout() ||
        @default_timeout

    OpenaiEx.with_receive_timeout(client, timeout)
  end

  defp maybe_set_base_url(client, opts) do
    case Keyword.get(opts, :base_url) || configured_base_url() do
      nil -> client
      url -> OpenaiEx.with_base_url(client, url)
    end
  end

  # Request building

  defp build_chat_request(messages, opts) do
    model = Keyword.get(opts, :model) || configured_model() || @default_model
    max_tokens = Keyword.get(opts, :max_tokens)
    temperature = Keyword.get(opts, :temperature)

    converted_messages = convert_messages(messages)

    request =
      Chat.Completions.new(
        model: model,
        messages: converted_messages
      )
      |> maybe_put(:max_tokens, max_tokens)
      |> maybe_put(:temperature, temperature)

    {:ok, request}
  end

  defp convert_messages(messages) do
    Enum.map(messages, &convert_message/1)
  end

  defp convert_message(%{role: role, content: content}) do
    build_chat_message(to_string(role), content)
  end

  defp convert_message(%{"role" => role, "content" => content}) do
    build_chat_message(role, content)
  end

  defp convert_message(msg) when is_map(msg) do
    role = Map.get(msg, :role) || Map.get(msg, "role") || "user"
    content = Map.get(msg, :content) || Map.get(msg, "content") || ""
    build_chat_message(to_string(role), content)
  end

  defp build_chat_message("system", content), do: ChatMessage.system(content)
  defp build_chat_message("user", content), do: ChatMessage.user(content)
  defp build_chat_message("assistant", content), do: ChatMessage.assistant(content)
  defp build_chat_message(_, content), do: ChatMessage.user(content)

  # Response normalization

  defp normalize_response(response) do
    choice = List.first(response["choices"] || []) || %{}
    message = choice["message"] || %{}

    %{
      content: message["content"] || "",
      model: response["model"],
      usage: normalize_usage(response["usage"]),
      finish_reason: normalize_finish_reason(choice["finish_reason"])
    }
  end

  defp normalize_usage(nil), do: %{input_tokens: 0, output_tokens: 0}

  defp normalize_usage(usage) do
    %{
      input_tokens: usage["prompt_tokens"] || 0,
      output_tokens: usage["completion_tokens"] || 0
    }
  end

  defp normalize_finish_reason("stop"), do: :stop
  defp normalize_finish_reason("length"), do: :length
  defp normalize_finish_reason("tool_calls"), do: :tool_use
  defp normalize_finish_reason("content_filter"), do: :content_filter
  defp normalize_finish_reason(nil), do: nil
  defp normalize_finish_reason(_), do: :stop

  # Streaming

  defp build_stream(stream_response) do
    stream_response.body_stream
    |> Stream.flat_map(& &1)
    |> Stream.transform(:init, &handle_stream_event/2)
    |> Stream.concat([%{delta: "", finish_reason: :stop}])
  end

  defp handle_stream_event(event, state) do
    case event do
      %{data: "[DONE]"} ->
        {:halt, state}

      %{data: data} when is_map(data) ->
        handle_stream_data(data, state)

      _ ->
        {[], state}
    end
  end

  defp handle_stream_data(data, state) do
    choice = List.first(data["choices"] || []) || %{}
    delta = choice["delta"] || %{}
    content = delta["content"]
    finish_reason = choice["finish_reason"]

    cond do
      is_binary(content) and content != "" ->
        {[%{delta: content, finish_reason: nil}], state}

      not is_nil(finish_reason) ->
        {[%{delta: "", finish_reason: normalize_finish_reason(finish_reason)}], state}

      true ->
        {[], state}
    end
  end

  # Configuration helpers

  defp configured_api_key do
    config()[:api_key] || System.get_env("OPENAI_API_KEY")
  end

  defp configured_model do
    config()[:model]
  end

  defp configured_timeout do
    config()[:receive_timeout]
  end

  defp configured_base_url do
    config()[:base_url]
  end

  defp configured_organization do
    config()[:organization] || System.get_env("OPENAI_ORGANIZATION")
  end

  defp config do
    Application.get_env(:portfolio_index, :openai, [])
  end

  defp live_api_allowed?(opts) do
    base_url = Keyword.get(opts, :base_url) || configured_base_url()
    allow_live = config()[:allow_live_api] || false

    not test_env?() or not is_nil(base_url) or allow_live
  end

  defp test_env? do
    Application.get_env(:portfolio_index, :env, :prod) == :test
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp emit_telemetry(event, metadata) do
    :telemetry.execute(
      [:portfolio_index, :llm, :openai, event],
      %{count: 1},
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
