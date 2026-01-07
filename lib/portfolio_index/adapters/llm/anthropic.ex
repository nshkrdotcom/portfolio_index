defmodule PortfolioIndex.Adapters.LLM.Anthropic do
  @behaviour PortfolioCore.Ports.LLM

  @moduledoc """
  Anthropic Claude LLM adapter using claude_agent_sdk.

  This is a thin wrapper around the claude_agent_sdk Hex library.
  Uses the SDK's default model unless overridden via opts.

  ## Configuration

      config :portfolio_index, :anthropic,
        model: nil  # Uses SDK default, or specify override

  ## Manifest

      adapters:
        llm:
          module: PortfolioIndex.Adapters.LLM.Anthropic
          config:
            model: null  # Uses SDK default
  """

  require Logger

  alias ClaudeAgentSDK.{ContentExtractor, Message, Options}
  alias PortfolioIndex.Adapters.RateLimiter

  @default_model_info %{
    context_window: 200_000,
    max_output: 4096,
    supports_tools: true
  }

  @impl true
  def complete(messages, opts \\ []) do
    # Wait for rate limiter before making request
    RateLimiter.wait(:anthropic, :chat)

    sdk = sdk_module()
    _ = Code.ensure_loaded?(sdk)

    result =
      cond do
        function_exported?(sdk, :complete, 2) ->
          complete_via_sdk(sdk, messages, opts)

        function_exported?(sdk, :query, 2) ->
          complete_via_query(sdk, messages, opts)

        true ->
          {:error, :unsupported_sdk}
      end

    case result do
      {:ok, _} = success ->
        RateLimiter.record_success(:anthropic, :chat)
        success

      {:error, :rate_limited} = error ->
        RateLimiter.record_failure(:anthropic, :chat, :rate_limited)
        error

      {:error, _} = error ->
        RateLimiter.record_failure(:anthropic, :chat, :server_error)
        error
    end
  end

  @impl true
  def stream(messages, opts \\ []) do
    sdk = sdk_module()
    _ = Code.ensure_loaded?(sdk)

    cond do
      function_exported?(sdk, :stream, 2) or function_exported?(sdk, :stream, 3) ->
        stream_from_sdk(messages, opts)

      sdk == ClaudeAgentSDK and function_exported?(ClaudeAgentSDK.Streaming, :start_session, 1) ->
        stream_via_streaming(messages, opts)

      function_exported?(sdk, :query, 2) ->
        stream_from_complete(messages, opts)

      true ->
        {:error, :stream_not_supported}
    end
  end

  @impl true
  def supported_models do
    sdk = sdk_module()
    _ = Code.ensure_loaded?(sdk)

    if function_exported?(sdk, :supported_models, 0) do
      sdk.supported_models()
    else
      [
        "claude-sonnet-4-20250514",
        "claude-opus-4-20250514",
        "claude-3-haiku-20240307"
      ]
    end
  end

  @impl true
  def model_info(model) do
    sdk = sdk_module()
    _ = Code.ensure_loaded?(sdk)

    if function_exported?(sdk, :model_info, 1) do
      case sdk.model_info(model) do
        %{} = info -> normalize_model_info(info)
        {:ok, info} when is_map(info) -> normalize_model_info(info)
        _ -> @default_model_info
      end
    else
      @default_model_info
    end
  end

  defp complete_via_sdk(sdk, messages, opts) do
    model = Keyword.get(opts, :model, configured_model())
    max_tokens = Keyword.get(opts, :max_tokens)
    max_turns = Keyword.get(opts, :max_turns)
    system = Keyword.get(opts, :system)

    sdk_opts =
      []
      |> maybe_add(:model, model)
      |> maybe_add(:max_tokens, max_tokens)
      |> maybe_add(:max_turns, max_turns)
      |> maybe_add(:system, system)

    converted_messages = convert_messages(messages)

    case sdk.complete(converted_messages, sdk_opts) do
      {:ok, response} ->
        emit_telemetry(:complete, %{model: response_model(response)})
        {:ok, normalize_response(response)}

      {:error, reason} ->
        Logger.error("Anthropic completion failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp complete_via_query(sdk, messages, opts) do
    {system_prompt, prompt} = extract_system_prompt(messages, opts)
    options = build_query_options(opts, system_prompt)
    prompt = ensure_prompt(prompt, system_prompt)

    response_messages =
      try do
        sdk.query(prompt, options) |> Enum.to_list()
      rescue
        error ->
          Logger.error("Anthropic query failed: #{inspect(error)}")
          return_error(error)
      end

    case response_messages do
      {:error, _} = error ->
        error

      _ ->
        case extract_query_response(response_messages, options) do
          {:ok, response} ->
            emit_telemetry(:complete, %{model: response.model})
            {:ok, response}

          {:error, reason} ->
            Logger.error("Anthropic completion failed: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  defp stream_from_sdk(messages, opts) do
    model = Keyword.get(opts, :model, configured_model())
    max_tokens = Keyword.get(opts, :max_tokens)
    max_turns = Keyword.get(opts, :max_turns)
    system = Keyword.get(opts, :system)

    sdk_opts =
      []
      |> maybe_add(:model, model)
      |> maybe_add(:max_tokens, max_tokens)
      |> maybe_add(:max_turns, max_turns)
      |> maybe_add(:system, system)

    converted_messages = convert_messages(messages)

    stream_from_sdk_module(converted_messages, sdk_opts)
  end

  defp stream_via_streaming(messages, opts) do
    {system_prompt, prompt} = extract_system_prompt(messages, opts)
    options = build_query_options(opts, system_prompt)
    prompt = ensure_prompt(prompt, system_prompt)

    case ClaudeAgentSDK.Streaming.start_session(options) do
      {:ok, session} ->
        stream = streaming_session_stream(session, prompt)
        {:ok, stream}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp stream_from_complete(messages, opts) do
    case complete(messages, opts) do
      {:ok, %{content: content, finish_reason: reason}} ->
        {:ok, response_stream(content, reason)}

      {:error, _} = error ->
        error
    end
  end

  defp streaming_session_stream(session, prompt) do
    Stream.resource(
      fn -> start_session_stream(session, prompt) end,
      &continue_session_stream/1,
      &close_session_stream/1
    )
  end

  defp start_session_stream(session, prompt) do
    parent = self()
    ref = make_ref()

    _pid =
      spawn(fn ->
        ClaudeAgentSDK.Streaming.send_message(session, prompt)
        |> Enum.each(fn event -> send(parent, {:event, ref, event}) end)

        send(parent, {:done, ref})
      end)

    %{session: session, ref: ref, done: false}
  end

  defp continue_session_stream(%{done: true} = state), do: {:halt, state}

  defp continue_session_stream(%{ref: ref} = state) do
    receive do
      {:event, ^ref, %{type: :text_delta, text: text}} ->
        {[%{delta: text, finish_reason: nil}], state}

      {:event, ^ref, %{type: :message_stop}} ->
        {[%{delta: "", finish_reason: :stop}], %{state | done: true}}

      {:event, ^ref, %{type: :error, error: reason}} ->
        {:halt, {:error, reason}}

      {:done, ^ref} ->
        {:halt, %{state | done: true}}
    after
      30_000 ->
        {:halt, {:error, :timeout}}
    end
  end

  defp close_session_stream(%{session: session}) do
    _ = ClaudeAgentSDK.Streaming.close_session(session)
    :ok
  end

  defp close_session_stream(_), do: :ok

  defp extract_query_response(messages, %Options{} = options) do
    case find_assistant_error(messages) do
      {:error, reason} ->
        {:error, reason}

      :ok ->
        result_message = Enum.find(messages, &(&1.type == :result))
        system_message = Enum.find(messages, &(&1.type == :system))

        content = extract_assistant_content(messages, result_message)
        usage = normalize_usage(result_message)
        finish_reason = finish_reason(result_message)
        model = extract_model(system_message, result_message, options)

        {:ok,
         %{
           content: content,
           model: model,
           usage: usage,
           finish_reason: finish_reason
         }}
    end
  end

  defp extract_assistant_content(messages, result_message) do
    assistant_texts =
      messages
      |> Enum.filter(&(&1.type == :assistant))
      |> Enum.map(&ContentExtractor.extract_text/1)
      |> Enum.reject(&blank?/1)

    case assistant_texts do
      [] ->
        case result_message do
          %Message{} -> ContentExtractor.extract_text(result_message) || ""
          _ -> ""
        end

      _ ->
        Enum.join(assistant_texts, "\n")
    end
  end

  defp find_assistant_error(messages) do
    case Enum.find(messages, &assistant_error?/1) do
      %Message{data: %{error: error}} when not is_nil(error) ->
        {:error, error}

      _ ->
        case Enum.find(messages, &result_error?/1) do
          %Message{data: %{error: error}} when is_binary(error) -> {:error, error}
          _ -> :ok
        end
    end
  end

  defp assistant_error?(%Message{type: :assistant, data: %{error: error}})
       when not is_nil(error),
       do: true

  defp assistant_error?(_), do: false

  defp result_error?(%Message{type: :result, subtype: subtype})
       when subtype in [:error_max_turns, :error_during_execution],
       do: true

  defp result_error?(_), do: false

  defp extract_model(%Message{type: :system, data: %{model: model}}, _result_message, %Options{})
       when is_binary(model) and model != "" do
    model
  end

  defp extract_model(_system_message, _result_message, %Options{model: fallback})
       when is_binary(fallback),
       do: fallback

  defp extract_model(_system_message, %Message{raw: raw}, _options) when is_map(raw) do
    model_usage = Map.get(raw, "modelUsage") || Map.get(raw, "model_usage")

    case model_usage do
      usage when is_map(usage) and map_size(usage) > 0 ->
        usage
        |> Map.keys()
        |> List.first()

      _ ->
        configured_model()
    end
  end

  defp extract_model(_system_message, _result_message, _options), do: configured_model()

  defp normalize_usage(%Message{type: :result, data: %{usage: usage}}), do: normalize_usage(usage)

  defp normalize_usage(usage) when is_map(usage) do
    %{
      input_tokens:
        fetch_token_value(usage, [
          :input_tokens,
          "input_tokens",
          :prompt_tokens,
          "prompt_tokens",
          :inputTokens,
          "inputTokens"
        ]),
      output_tokens:
        fetch_token_value(usage, [
          :output_tokens,
          "output_tokens",
          :completion_tokens,
          "completion_tokens",
          :outputTokens,
          "outputTokens"
        ])
    }
  end

  defp normalize_usage(_), do: %{}

  defp fetch_token_value(usage, keys) do
    Enum.find_value(keys, 0, &Map.get(usage, &1))
  end

  defp finish_reason(%Message{type: :result, subtype: :success}), do: :stop
  defp finish_reason(%Message{type: :result, subtype: :error_max_turns}), do: :length
  defp finish_reason(_), do: nil

  defp build_query_options(opts, system_prompt) do
    model = Keyword.get(opts, :model, configured_model())
    max_thinking_tokens = Keyword.get(opts, :max_thinking_tokens)
    max_turns = Keyword.get(opts, :max_turns, 1)

    %Options{}
    |> maybe_put_struct(:model, model)
    |> maybe_put_struct(:system_prompt, system_prompt)
    |> maybe_put_struct(:output_format, :json)
    |> maybe_put_struct(:max_turns, max_turns)
    |> maybe_put_struct(:max_thinking_tokens, max_thinking_tokens)
  end

  defp extract_system_prompt(messages, opts) do
    system_opt = Keyword.get(opts, :system)

    {system_messages, rest} = Enum.split_with(messages, &system_message?/1)
    system_prompt = system_opt || first_system_content(system_messages)
    prompt = format_conversation(rest)

    {system_prompt, prompt}
  end

  defp system_message?(%{role: role}), do: to_string(role) == "system"
  defp system_message?(%{"role" => role}), do: to_string(role) == "system"
  defp system_message?(_), do: false

  defp first_system_content([]), do: nil
  defp first_system_content([message | _]), do: message_content(message)

  defp format_conversation(messages) do
    messages
    |> Enum.map(&format_message/1)
    |> Enum.reject(&blank?/1)
    |> Enum.join("\n\n")
  end

  defp format_message(message) do
    role = message_role(message) || "user"
    content = message_content(message)

    if is_binary(content) and content != "" do
      "#{String.capitalize(to_string(role))}: #{content}"
    else
      ""
    end
  end

  defp message_role(%{role: role}), do: role
  defp message_role(%{"role" => role}), do: role
  defp message_role(_), do: nil

  defp message_content(%{content: content}), do: content
  defp message_content(%{"content" => content}), do: content
  defp message_content(_), do: nil

  defp ensure_prompt("", system_prompt) when is_binary(system_prompt) and system_prompt != "",
    do: system_prompt

  defp ensure_prompt(prompt, _system_prompt), do: prompt

  defp convert_messages(messages) do
    Enum.map(messages, fn
      %{role: role, content: content} ->
        %{role: to_string(role), content: content}

      %{"role" => role, "content" => content} ->
        %{role: role, content: content}

      msg when is_map(msg) ->
        msg
    end)
  end

  defp normalize_response(response) do
    %{
      content: response_content(response),
      model: response_model(response),
      usage: response_usage(response),
      finish_reason: normalize_finish_reason(response_finish_reason(response))
    }
  end

  defp response_content(response) when is_map(response) do
    Map.get(response, :content) || Map.get(response, "content") || ""
  end

  defp response_model(response) when is_map(response) do
    Map.get(response, :model) || Map.get(response, "model")
  end

  defp response_usage(response) when is_map(response) do
    Map.get(response, :usage) || Map.get(response, "usage") || %{}
  end

  defp response_finish_reason(response) when is_map(response) do
    Map.get(response, :finish_reason) ||
      Map.get(response, "finish_reason") ||
      Map.get(response, :stop_reason) ||
      Map.get(response, "stop_reason")
  end

  defp normalize_finish_reason(nil), do: nil
  defp normalize_finish_reason(:stop), do: :stop
  defp normalize_finish_reason(:length), do: :length
  defp normalize_finish_reason(:tool_use), do: :tool_use
  defp normalize_finish_reason("stop"), do: :stop
  defp normalize_finish_reason("length"), do: :length
  defp normalize_finish_reason("tool_use"), do: :tool_use
  defp normalize_finish_reason(other) when is_atom(other), do: other
  defp normalize_finish_reason(_), do: nil

  defp normalize_model_info(info) do
    %{
      context_window: map_fetch(info, :context_window, 200_000),
      max_output: map_fetch(info, :max_output, 4096),
      supports_tools: map_fetch(info, :supports_tools, true)
    }
  end

  defp map_fetch(map, key, default) when is_map(map) do
    Map.get(map, key) ||
      Map.get(map, Atom.to_string(key)) ||
      default
  end

  defp configured_model do
    :portfolio_index
    |> Application.get_env(:anthropic, [])
    |> Keyword.get(:model)
  end

  defp maybe_add(opts, _key, nil), do: opts
  defp maybe_add(opts, key, value), do: Keyword.put(opts, key, value)

  defp maybe_put_struct(struct, _key, nil), do: struct
  defp maybe_put_struct(struct, key, value), do: Map.put(struct, key, value)

  defp stream_from_sdk_module(messages, sdk_opts) do
    sdk = sdk_module()

    cond do
      function_exported?(sdk, :stream, 2) ->
        case sdk.stream(messages, sdk_opts) do
          {:ok, stream} -> {:ok, normalize_stream(stream)}
          {:error, _} = error -> error
          stream -> {:ok, normalize_stream(stream)}
        end

      function_exported?(sdk, :stream, 3) ->
        {:ok, callback_stream(sdk, messages, sdk_opts)}

      true ->
        {:error, :stream_not_supported}
    end
  end

  defp callback_stream(sdk, messages, sdk_opts) do
    Stream.resource(
      fn -> start_streaming(sdk, messages, sdk_opts) end,
      &continue_streaming/1,
      fn _ -> :ok end
    )
  end

  defp start_streaming(sdk, messages, sdk_opts) do
    parent = self()
    ref = make_ref()

    _pid =
      spawn(fn ->
        result =
          sdk.stream(
            messages,
            fn chunk ->
              send(parent, {:chunk, ref, chunk})
            end,
            sdk_opts
          )

        send(parent, {:done, ref, result})
      end)

    {:streaming, ref}
  end

  defp continue_streaming({:streaming, ref}) do
    receive do
      {:chunk, ^ref, chunk} ->
        {[%{delta: normalize_stream_chunk(chunk), finish_reason: nil}], {:streaming, ref}}

      {:done, ^ref, {:error, reason}} ->
        {:halt, {:error, reason}}

      {:done, ^ref, _} ->
        {[%{delta: "", finish_reason: :stop}], {:done, ref}}
    after
      30_000 ->
        {:halt, {:error, :timeout}}
    end
  end

  defp continue_streaming({:done, _ref}) do
    {:halt, :done}
  end

  defp normalize_stream(stream) do
    Stream.map(stream, fn chunk ->
      case chunk do
        %{delta: _} = existing -> existing
        %{content: delta} -> %{delta: delta, finish_reason: nil}
        delta when is_binary(delta) -> %{delta: delta, finish_reason: nil}
        _ -> %{delta: "", finish_reason: nil}
      end
    end)
  end

  defp normalize_stream_chunk(%{delta: delta}), do: delta
  defp normalize_stream_chunk(%{content: delta}), do: delta
  defp normalize_stream_chunk(delta) when is_binary(delta), do: delta
  defp normalize_stream_chunk(_), do: ""

  defp response_stream(content, reason) do
    finish_reason = reason || :stop

    Stream.concat([
      [%{delta: content, finish_reason: nil}],
      [%{delta: "", finish_reason: finish_reason}]
    ])
  end

  defp return_error(error), do: {:error, error}

  defp blank?(value), do: value in [nil, ""]

  defp sdk_module do
    Application.get_env(:portfolio_index, :anthropic_sdk, ClaudeAgentSDK)
  end

  defp emit_telemetry(event, metadata) do
    :telemetry.execute(
      [:portfolio_index, :llm, :anthropic, event],
      %{count: 1},
      metadata
    )
  end
end
