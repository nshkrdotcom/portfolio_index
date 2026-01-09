defmodule PortfolioIndex.Adapters.LLM.Codex do
  @behaviour PortfolioCore.Ports.LLM

  @moduledoc """
  OpenAI GPT LLM adapter using codex_sdk.

  This is a thin wrapper around the codex_sdk Hex library.
  Uses the SDK's default model unless overridden via opts.

  ## Configuration

      config :portfolio_index, :codex,
        model: "gpt-4o-mini"  # Default to a low-cost model; override if needed

  ## Manifest

      adapters:
        llm:
          module: PortfolioIndex.Adapters.LLM.Codex
          config:
            model: null  # Uses SDK default
  """

  require Logger

  alias PortfolioIndex.Adapters.RateLimiter
  alias PortfolioIndex.Telemetry.Context

  @default_model "gpt-4o-mini"

  @default_model_info %{
    context_window: 128_000,
    max_output: 4096,
    supports_tools: true
  }

  @impl true
  def complete(messages, opts \\ []) do
    # Wait for rate limiter before making request (uses openai provider since Codex is OpenAI-based)
    RateLimiter.wait(:openai, :chat)

    sdk = sdk_module()

    result =
      cond do
        function_exported?(sdk, :complete, 2) ->
          complete_via_sdk(sdk, messages, opts)

        function_exported?(sdk, :start_thread, 2) ->
          complete_via_codex(sdk, messages, opts)

        Code.ensure_loaded?(Codex) and function_exported?(Codex, :start_thread, 2) ->
          complete_via_codex(Codex, messages, opts)

        true ->
          {:error, :unsupported_sdk}
      end

    case result do
      {:ok, _} = success ->
        RateLimiter.record_success(:openai, :chat)
        success

      {:error, :rate_limited} = error ->
        RateLimiter.record_failure(:openai, :chat, :rate_limited)
        error

      {:error, _} = error ->
        RateLimiter.record_failure(:openai, :chat, :server_error)
        error
    end
  end

  @impl true
  def stream(messages, opts \\ []) do
    sdk = sdk_module()

    cond do
      function_exported?(sdk, :stream, 2) or function_exported?(sdk, :stream, 3) ->
        stream_from_sdk(sdk, messages, opts)

      function_exported?(sdk, :start_thread, 2) ->
        stream_via_codex(sdk, messages, opts)

      Code.ensure_loaded?(Codex) and function_exported?(Codex, :start_thread, 2) ->
        stream_via_codex(Codex, messages, opts)

      function_exported?(sdk, :complete, 2) ->
        stream_from_complete(sdk, messages, opts)

      true ->
        {:error, :stream_not_supported}
    end
  end

  @impl true
  def supported_models do
    sdk = sdk_module()

    if function_exported?(sdk, :supported_models, 0) do
      sdk.supported_models()
    else
      codex_models()
    end
  end

  defp codex_models do
    if Code.ensure_loaded?(Codex.Models) and function_exported?(Codex.Models, :list, 0) do
      Codex.Models.list()
      |> Enum.map(& &1.model)
      |> Enum.uniq()
    else
      ["gpt-4o-mini", "gpt-4o", "gpt-4-turbo", "o1", "o3-mini"]
    end
  end

  @impl true
  def model_info(model) do
    sdk = sdk_module()

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

    sdk_opts =
      []
      |> maybe_add(:model, model)
      |> maybe_add(:max_tokens, max_tokens)

    converted_messages = convert_messages(messages)

    case sdk.complete(converted_messages, sdk_opts) do
      {:ok, response} ->
        emit_telemetry(:complete, %{model: response_model(response)}, opts)
        {:ok, normalize_response(response)}

      {:error, reason} ->
        Logger.error("Codex completion failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp complete_via_codex(sdk, messages, opts) do
    {system_prompt, prompt} = extract_system_prompt(messages, opts)
    prompt = apply_system_prompt(prompt, system_prompt)

    with {:ok, thread} <- start_thread(sdk, opts),
         {:ok, result} <- Codex.Thread.run(thread, prompt, build_run_opts(opts)) do
      response = normalize_codex_result(result)
      emit_telemetry(:complete, %{model: response.model}, opts)
      {:ok, response}
    else
      {:error, reason} ->
        Logger.error("Codex completion failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp stream_from_sdk(sdk, messages, opts) do
    model = Keyword.get(opts, :model, configured_model())
    max_tokens = Keyword.get(opts, :max_tokens)

    sdk_opts =
      []
      |> maybe_add(:model, model)
      |> maybe_add(:max_tokens, max_tokens)

    converted_messages = convert_messages(messages)

    stream_from_sdk_module(sdk, converted_messages, sdk_opts)
  end

  defp stream_via_codex(sdk, messages, opts) do
    {system_prompt, prompt} = extract_system_prompt(messages, opts)
    prompt = apply_system_prompt(prompt, system_prompt)

    with {:ok, thread} <- start_thread(sdk, opts),
         {:ok, result} <- Codex.Thread.run_streamed(thread, prompt, build_run_opts(opts)) do
      {:ok, codex_stream(result)}
    else
      {:error, reason} ->
        Logger.error("Codex streaming failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp stream_from_complete(sdk, messages, opts) do
    case complete_via_sdk(sdk, messages, opts) do
      {:ok, %{content: content, finish_reason: reason}} ->
        {:ok, response_stream(content, reason)}

      {:error, _} = error ->
        error
    end
  end

  defp start_thread(sdk, opts) do
    model = codex_model_opt(opts)

    codex_opts =
      %{}
      |> maybe_put_map(:model, model)

    sdk.start_thread(codex_opts, %{})
  end

  defp build_run_opts(opts) do
    model = codex_model_opt(opts)
    max_tokens = Keyword.get(opts, :max_tokens)

    run_config =
      %{}
      |> Map.put(:max_turns, 1)
      |> maybe_put_map(:model, model)
      |> maybe_put_map(:model_settings, build_model_settings(max_tokens))

    %{run_config: run_config}
  end

  defp build_model_settings(nil), do: nil

  defp build_model_settings(tokens) when is_integer(tokens) and tokens > 0 do
    %{max_tokens: tokens}
  end

  defp build_model_settings(_), do: nil

  defp codex_stream(result) do
    Codex.RunResultStreaming.events(result)
    |> Stream.transform(%{emitted?: false}, &handle_codex_event/2)
    |> Stream.concat([%{delta: "", finish_reason: :stop}])
  end

  defp handle_codex_event(
         %Codex.StreamEvent.RunItem{event: %Codex.Events.ItemAgentMessageDelta{item: item}},
         state
       ) do
    case extract_delta(item) do
      nil -> {[], state}
      delta -> {[%{delta: delta, finish_reason: nil}], %{state | emitted?: true}}
    end
  end

  defp handle_codex_event(
         %Codex.StreamEvent.RunItem{event: %Codex.Events.ItemCompleted{item: item}},
         state
       ) do
    case {state.emitted?, extract_item_text(item)} do
      {false, text} when is_binary(text) and text != "" ->
        {[%{delta: text, finish_reason: nil}], %{state | emitted?: true}}

      _ ->
        {[], state}
    end
  end

  defp handle_codex_event(_event, state), do: {[], state}

  defp extract_delta(%{"text" => text}) when is_binary(text), do: text
  defp extract_delta(%{text: text}) when is_binary(text), do: text

  defp extract_delta(%{"content" => %{"type" => "text", "text" => text}})
       when is_binary(text),
       do: text

  defp extract_delta(%{content: %{type: "text", text: text}}) when is_binary(text), do: text
  defp extract_delta(_), do: nil

  defp extract_item_text(%Codex.Items.AgentMessage{text: text}) when is_binary(text), do: text
  defp extract_item_text(%{"text" => text}) when is_binary(text), do: text
  defp extract_item_text(%{text: text}) when is_binary(text), do: text
  defp extract_item_text(_), do: nil

  defp normalize_codex_result(%Codex.Turn.Result{} = result) do
    %{
      content: codex_content(result),
      model: codex_model(result),
      usage: normalize_usage(result.usage),
      finish_reason: codex_finish_reason(result.events)
    }
  end

  defp codex_content(%Codex.Turn.Result{final_response: %Codex.Items.AgentMessage{text: text}})
       when is_binary(text),
       do: text

  defp codex_content(%Codex.Turn.Result{final_response: %{"text" => text}})
       when is_binary(text),
       do: text

  defp codex_content(%Codex.Turn.Result{final_response: %{text: text}}) when is_binary(text),
    do: text

  defp codex_content(_), do: ""

  defp codex_model(%Codex.Turn.Result{
         thread: %Codex.Thread{codex_opts: %Codex.Options{model: model}}
       })
       when is_binary(model) and model != "",
       do: model

  defp codex_model(_), do: configured_model()

  defp codex_finish_reason(events) do
    events
    |> List.wrap()
    |> Enum.find(&match?(%Codex.Events.TurnCompleted{}, &1))
    |> case do
      %Codex.Events.TurnCompleted{status: status} -> normalize_codex_status(status)
      _ -> :stop
    end
  end

  defp normalize_codex_status(status) when status in ["early_exit", :early_exit], do: :length
  defp normalize_codex_status(_), do: :stop

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

  defp apply_system_prompt(prompt, nil), do: prompt

  defp apply_system_prompt(prompt, system_prompt)
       when is_binary(system_prompt) and system_prompt != "" do
    if prompt == "" do
      system_prompt
    else
      "System: #{system_prompt}\n\n#{prompt}"
    end
  end

  defp apply_system_prompt(prompt, _system_prompt), do: prompt

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

  defp normalize_usage(%{} = usage) do
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

  defp normalize_model_info(info) do
    %{
      context_window: map_fetch(info, :context_window, 128_000),
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
    |> Application.get_env(:codex, [])
    |> Keyword.get(:model, @default_model)
  end

  defp codex_model_opt(opts) do
    case Keyword.fetch(opts, :model) do
      {:ok, model} -> ensure_codex_model(model, warn: true)
      :error -> ensure_codex_model(configured_model(), warn: false)
    end
  end

  defp ensure_codex_model(nil, _opts), do: nil

  defp ensure_codex_model(model, opts) when is_binary(model) do
    if codex_model_supported?(model) do
      model
    else
      if Keyword.get(opts, :warn, false) do
        Logger.warning("Codex SDK does not recognize model #{model}; using SDK default")
      end

      nil
    end
  end

  defp ensure_codex_model(model, _opts), do: model

  defp codex_model_supported?(model) when is_binary(model) do
    Code.ensure_loaded?(Codex.Models) and
      function_exported?(Codex.Models, :display_name, 1) and
      not is_nil(Codex.Models.display_name(model))
  end

  defp maybe_add(opts, _key, nil), do: opts
  defp maybe_add(opts, key, value), do: Keyword.put(opts, key, value)

  defp maybe_put_map(map, _key, nil), do: map
  defp maybe_put_map(map, key, value), do: Map.put(map, key, value)

  defp stream_from_sdk_module(sdk, messages, sdk_opts) do
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

  defp blank?(value), do: value in [nil, ""]

  defp sdk_module do
    Application.get_env(:portfolio_index, :codex_sdk, CodexSdk)
  end

  defp emit_telemetry(event, metadata, opts) do
    metadata = Context.merge(metadata, opts)

    :telemetry.execute(
      [:portfolio_index, :llm, :codex, event],
      %{count: 1},
      metadata
    )
  end
end
