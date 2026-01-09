defmodule PortfolioIndex.Adapters.LLM.VLLM do
  @behaviour PortfolioCore.Ports.LLM

  @moduledoc """
  vLLM adapter using the OpenAI-compatible chat completions API.

  ## Configuration

      config :portfolio_index, :vllm,
        base_url: "http://localhost:8000/v1",
        api_key: System.get_env("VLLM_API_KEY"),
        model: "llama3",
        models: ["llama3", "mistral"],
        model_info: %{
          "llama3" => %{context_window: 32768, max_output: 4096, supports_tools: true}
        }
  """

  require Logger

  alias OpenaiEx.Chat
  alias OpenaiEx.ChatMessage
  alias PortfolioIndex.Adapters.RateLimiter
  alias PortfolioIndex.Telemetry.Context

  @default_model "llama3"
  @default_timeout 30_000
  @default_base_url "http://localhost:8000/v1"

  @default_model_info %{
    context_window: 8192,
    max_output: 2048,
    supports_tools: true
  }

  @impl true
  def complete(messages, opts \\ []) do
    RateLimiter.wait(:vllm, :chat)

    with {:ok, client} <- build_client(opts),
         {:ok, request} <- build_chat_request(messages, opts),
         {:ok, response} <- Chat.Completions.create(client, request) do
      RateLimiter.record_success(:vllm, :chat)
      emit_telemetry(:complete, %{model: response["model"]}, opts)
      {:ok, normalize_response(response)}
    else
      {:error, reason} ->
        RateLimiter.record_failure(:vllm, :chat, detect_failure_type(reason))
        Logger.error("vLLM completion failed: #{inspect(reason)}")
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
          {:ok, build_stream(stream_response)}

        {:error, reason} ->
          Logger.error("vLLM streaming failed: #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def supported_models do
    case config()[:models] do
      models when is_list(models) and models != [] ->
        models

      model when is_binary(model) ->
        [model]

      _ ->
        model = config()[:model] || @default_model
        [model]
    end
  end

  @impl true
  def model_info(model) do
    config()
    |> Keyword.get(:model_info, %{})
    |> fetch_model_info(model)
  end

  defp build_client(opts) do
    api_key =
      Keyword.get(opts, :api_key) ||
        configured_api_key() ||
        "vllm"

    organization = Keyword.get(opts, :organization) || configured_organization()

    client =
      OpenaiEx.new(api_key, organization)
      |> maybe_set_timeout(opts)
      |> maybe_set_base_url(opts)

    {:ok, client}
  end

  defp maybe_set_timeout(client, opts) do
    timeout =
      Keyword.get(opts, :receive_timeout) ||
        configured_timeout() ||
        @default_timeout

    OpenaiEx.with_receive_timeout(client, timeout)
  end

  defp maybe_set_base_url(client, opts) do
    base_url = Keyword.get(opts, :base_url) || configured_base_url() || @default_base_url
    OpenaiEx.with_base_url(client, base_url)
  end

  defp build_chat_request(messages, opts) do
    model = Keyword.get(opts, :model) || configured_model() || @default_model
    max_tokens = Keyword.get(opts, :max_tokens)
    temperature = Keyword.get(opts, :temperature)
    top_p = Keyword.get(opts, :top_p)
    stop = Keyword.get(opts, :stop)
    tools = Keyword.get(opts, :tools)
    tool_choice = Keyword.get(opts, :tool_choice)

    converted_messages = convert_messages(messages)

    request =
      Chat.Completions.new(
        model: model,
        messages: converted_messages
      )
      |> maybe_put(:max_tokens, max_tokens)
      |> maybe_put(:temperature, temperature)
      |> maybe_put(:top_p, top_p)
      |> maybe_put(:stop, stop)
      |> maybe_put(:tools, tools)
      |> maybe_put(:tool_choice, tool_choice)

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

  defp convert_message(content) when is_binary(content) do
    build_chat_message("user", content)
  end

  defp convert_message(_), do: build_chat_message("user", "")

  defp build_chat_message("system", content), do: ChatMessage.system(content)
  defp build_chat_message("user", content), do: ChatMessage.user(content)
  defp build_chat_message("assistant", content), do: ChatMessage.assistant(content)
  defp build_chat_message(_, content), do: ChatMessage.user(content)

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

  defp config do
    Application.get_env(:portfolio_index, :vllm, [])
  end

  defp configured_base_url do
    config()[:base_url] || System.get_env("VLLM_BASE_URL")
  end

  defp configured_api_key do
    config()[:api_key] || System.get_env("VLLM_API_KEY")
  end

  defp configured_model do
    config()[:model]
  end

  defp configured_timeout do
    config()[:receive_timeout]
  end

  defp configured_organization do
    config()[:organization]
  end

  defp emit_telemetry(event, metadata, opts) do
    metadata = Context.merge(metadata, opts)

    :telemetry.execute(
      [:portfolio_index, :llm, :vllm, event],
      %{count: 1},
      metadata
    )
  end

  defp detect_failure_type(reason) do
    reason_str = inspect(reason) |> String.downcase()

    cond do
      String.contains?(reason_str, "rate") or String.contains?(reason_str, "429") ->
        :rate_limited

      String.contains?(reason_str, "timeout") ->
        :timeout

      true ->
        :server_error
    end
  end

  defp fetch_model_info(info_map, model) when is_map(info_map) do
    Map.get(info_map, model) || Map.get(info_map, to_string(model)) || @default_model_info
  end

  defp fetch_model_info(_, _model), do: @default_model_info

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
