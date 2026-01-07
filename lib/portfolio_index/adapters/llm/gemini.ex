defmodule PortfolioIndex.Adapters.LLM.Gemini do
  @moduledoc """
  Google Gemini LLM adapter using gemini_ex.

  Implements the `PortfolioCore.Ports.LLM` behaviour.

  ## Features

  - Chat completions with message history
  - Streaming support
  - Token usage tracking
  - Model information

  ## Model

  Uses the gemini_ex registry defaults unless a model is supplied via options.

  ## Example

      messages = [
        %{role: :system, content: "You are a helpful assistant."},
        %{role: :user, content: "What is Elixir?"}
      ]

      {:ok, result} = Gemini.complete(messages, [])
      # => {:ok, %{content: "Elixir is...", model: "gemini-...", usage: %{...}}}
  """

  @behaviour PortfolioCore.Ports.LLM

  # Suppress dialyzer warnings for gemini_ex calls which may not be fully typed
  @dialyzer [
    :no_return,
    :no_match,
    :no_fail_call
  ]

  require Logger
  alias Gemini.Types.Response.GenerateContentResponse
  alias PortfolioIndex.Adapters.RateLimiter

  @impl true
  def complete(messages, opts) do
    # Wait for rate limiter before making request
    RateLimiter.wait(:gemini, :chat)

    start_time = System.monotonic_time(:millisecond)
    {model_opt, effective_model} = resolve_generation_model(opts)
    max_tokens = Keyword.get(opts, :max_tokens, 4096)
    temperature = Keyword.get(opts, :temperature, 0.7)

    {system_prompt, user_messages} = extract_system_prompt(messages)
    prompt = format_messages(user_messages)

    gemini_opts =
      []
      |> maybe_put(:model, model_opt)
      |> maybe_put(:system_instruction, system_prompt)
      |> Keyword.put(:max_output_tokens, max_tokens)
      |> Keyword.put(:temperature, temperature)
      |> put_default(:response_mime_type, "text/plain")
      |> put_default(:response_modalities, [:text])

    case generate_with_retry(prompt, gemini_opts, effective_model, _attempt = 1) do
      {:ok, response, content} ->
        RateLimiter.record_success(:gemini, :chat)
        usage = extract_usage(response, prompt, content)

        duration = System.monotonic_time(:millisecond) - start_time

        emit_telemetry(
          :complete,
          %{
            duration_ms: duration,
            input_tokens: usage.input_tokens,
            output_tokens: usage.output_tokens
          },
          %{model: effective_model}
        )

        {:ok,
         %{
           content: content,
           model: effective_model,
           usage: usage,
           finish_reason: extract_finish_reason(response)
         }}

      {:error, :rate_limited} = error ->
        RateLimiter.record_failure(:gemini, :chat, :rate_limited)
        Logger.error("LLM completion rate limited")
        error

      {:error, reason} ->
        RateLimiter.record_failure(:gemini, :chat, :server_error)
        Logger.error("LLM completion failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def stream(messages, opts) do
    {model_opt, _effective_model} = resolve_generation_model(opts)
    max_tokens = Keyword.get(opts, :max_tokens, 4096)
    temperature = Keyword.get(opts, :temperature, 0.7)

    {system_prompt, user_messages} = extract_system_prompt(messages)
    prompt = format_messages(user_messages)

    # Create a stream using gemini_ex streaming
    stream =
      Stream.resource(
        fn -> start_streaming(prompt, model_opt, max_tokens, temperature, system_prompt) end,
        &continue_streaming/1,
        fn _ -> :ok end
      )

    {:ok, stream}
  end

  @impl true
  def supported_models do
    Gemini.Config.models_for(Gemini.Config.current_api_type())
    |> Map.values()
    |> Enum.reject(&embedding_model?/1)
  end

  @impl true
  def model_info(_model) do
    llm_config =
      case Application.get_env(:portfolio_index, :llm, []) do
        config when is_list(config) -> config
        _ -> []
      end

    %{
      context_window: Keyword.get(llm_config, :context_window, 128_000),
      max_output: Keyword.get(llm_config, :max_output, 4096),
      supports_tools: Keyword.get(llm_config, :supports_tools, true)
    }
  end

  # Private functions

  defp extract_system_prompt(messages) do
    case Enum.split_with(messages, &(&1.role == :system)) do
      {[%{content: system} | _], rest} -> {system, rest}
      {[], messages} -> {nil, messages}
    end
  end

  defp format_messages(messages) do
    # For Gemini, we need to format as a conversation
    # The gemini_ex library may handle this differently
    Enum.map_join(messages, "\n\n", fn msg ->
      role =
        case msg.role do
          :user -> "User"
          :assistant -> "Assistant"
          :system -> "System"
          other -> to_string(other)
        end

      "#{role}: #{msg.content}"
    end)
  end

  defp extract_usage(%GenerateContentResponse{} = response, prompt, content) do
    usage = GenerateContentResponse.token_usage(response)

    input_tokens = usage_value(usage, :input, "promptTokenCount") || estimate_tokens(prompt)

    output_tokens =
      usage_value(usage, :output, "candidatesTokenCount") || estimate_tokens(content)

    %{
      input_tokens: input_tokens,
      output_tokens: output_tokens
    }
  end

  defp extract_finish_reason(response) do
    response
    |> extract_finish_reason_raw()
    |> normalize_finish_reason()
  end

  defp extract_finish_reason_raw(%GenerateContentResponse{} = response) do
    GenerateContentResponse.finish_reason(response)
  end

  defp extract_finish_reason_raw(_), do: nil

  defp usage_value(nil, _atom_key, _camel_key), do: nil

  defp usage_value(usage, atom_key, camel_key) when is_map(usage) do
    Map.get(usage, atom_key) ||
      Map.get(usage, Atom.to_string(atom_key)) ||
      Map.get(usage, camel_key)
  end

  defp generate_with_retry(prompt, gemini_opts, model, attempt) do
    case gemini_module().generate(prompt, gemini_opts) do
      {:ok, response} ->
        case extract_text(response) do
          {:ok, text} when is_binary(text) and text != "" ->
            {:ok, response, text}

          {:ok, _empty} ->
            handle_missing_text(response, :empty, prompt, gemini_opts, model, attempt)

          {:error, reason} ->
            handle_missing_text(response, reason, prompt, gemini_opts, model, attempt)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_text(response) do
    if is_binary(response) do
      {:ok, response}
    else
      gemini_module().extract_text(response)
    end
  end

  defp handle_missing_text(response, reason, prompt, gemini_opts, model, attempt) do
    diagnostics = missing_text_diagnostics(response, reason, model)
    Logger.warning("Gemini response missing text: #{inspect(diagnostics)}")

    if diagnostics.blocked do
      {:error, {:blocked, diagnostics}}
    else
      retry_or_fail(prompt, gemini_opts, model, attempt, diagnostics)
    end
  end

  defp retry_or_fail(prompt, gemini_opts, model, attempt, _diagnostics) when attempt < 2 do
    retry_opts =
      gemini_opts
      |> Keyword.put(:temperature, 0.0)
      |> Keyword.put(:top_p, 1.0)

    generate_with_retry(prompt, retry_opts, model, attempt + 1)
  end

  defp retry_or_fail(_prompt, _gemini_opts, _model, _attempt, diagnostics) do
    {:error, {:no_text, diagnostics}}
  end

  defp missing_text_diagnostics(response, reason, model) do
    finish_reason = extract_finish_reason_raw(response)
    prompt_feedback = extract_prompt_feedback(response)
    prompt_info = prompt_feedback_info(prompt_feedback)
    candidate_ratings = extract_candidate_safety_ratings(response)
    safety_ratings = prompt_info.safety_ratings ++ candidate_ratings

    %{
      reason: reason,
      model: model,
      finish_reason: finish_reason,
      blocked: blocked_response?(finish_reason, prompt_info.block_reason, safety_ratings),
      block_reason: prompt_info.block_reason,
      block_reason_message: prompt_info.block_reason_message,
      safety_ratings: summarize_safety_ratings(safety_ratings)
    }
  end

  defp extract_prompt_feedback(%GenerateContentResponse{prompt_feedback: pf}),
    do: pf

  defp extract_prompt_feedback(%{prompt_feedback: pf}), do: pf
  defp extract_prompt_feedback(%{"promptFeedback" => pf}), do: pf
  defp extract_prompt_feedback(_), do: nil

  defp prompt_feedback_info(nil) do
    %{block_reason: nil, block_reason_message: nil, safety_ratings: []}
  end

  defp prompt_feedback_info(feedback) do
    %{
      block_reason:
        Map.get(feedback, :block_reason) ||
          Map.get(feedback, "blockReason") ||
          Map.get(feedback, "block_reason"),
      block_reason_message:
        Map.get(feedback, :block_reason_message) ||
          Map.get(feedback, "blockReasonMessage") ||
          Map.get(feedback, "block_reason_message"),
      safety_ratings:
        Map.get(feedback, :safety_ratings) ||
          Map.get(feedback, "safetyRatings") ||
          Map.get(feedback, "safety_ratings") ||
          []
    }
  end

  defp extract_candidate_safety_ratings(response) do
    case extract_first_candidate(response) do
      nil ->
        []

      candidate ->
        Map.get(candidate, :safety_ratings) ||
          Map.get(candidate, "safetyRatings") ||
          Map.get(candidate, "safety_ratings") ||
          []
    end
  end

  defp extract_first_candidate(%GenerateContentResponse{candidates: [first | _]}),
    do: first

  defp extract_first_candidate(%{candidates: [first | _]}), do: first
  defp extract_first_candidate(%{"candidates" => [first | _]}), do: first
  defp extract_first_candidate(_), do: nil

  defp summarize_safety_ratings(ratings) do
    Enum.map(ratings, fn rating ->
      %{
        category: Map.get(rating, :category) || Map.get(rating, "category"),
        probability: Map.get(rating, :probability) || Map.get(rating, "probability"),
        blocked: Map.get(rating, :blocked) || Map.get(rating, "blocked"),
        severity: Map.get(rating, :severity) || Map.get(rating, "severity")
      }
    end)
  end

  defp blocked_response?(finish_reason, block_reason, safety_ratings) do
    finish_reason in ["SAFETY", :SAFETY] or
      not is_nil(block_reason) or
      Enum.any?(safety_ratings, &safety_blocked?/1)
  end

  defp safety_blocked?(rating) do
    Map.get(rating, :blocked) || Map.get(rating, "blocked") || false
  end

  defp resolve_generation_model(opts) do
    case Keyword.get(opts, :model) do
      nil ->
        {nil, Gemini.Config.default_model()}

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

  defp embedding_model?(model) when is_binary(model) do
    not is_nil(Gemini.Config.embedding_config(model))
  end

  defp embedding_model?(_), do: false

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp put_default(opts, key, value) do
    if Keyword.has_key?(opts, key) do
      opts
    else
      Keyword.put(opts, key, value)
    end
  end

  defp normalize_finish_reason("STOP"), do: :stop
  defp normalize_finish_reason("MAX_TOKENS"), do: :length
  defp normalize_finish_reason("SAFETY"), do: :stop
  defp normalize_finish_reason(:STOP), do: :stop
  defp normalize_finish_reason(:MAX_TOKENS), do: :length
  defp normalize_finish_reason(_), do: :stop

  defp start_streaming(prompt, model_opt, max_tokens, temperature, system_prompt) do
    # Start the streaming process
    # gemini_ex uses callbacks for streaming
    parent = self()
    ref = make_ref()

    spawn_link(fn ->
      opts =
        []
        |> maybe_put(:model, model_opt)
        |> maybe_put(:system_instruction, system_prompt)
        |> Keyword.put(:max_output_tokens, max_tokens)
        |> Keyword.put(:temperature, temperature)
        |> put_default(:response_mime_type, "text/plain")
        |> put_default(:response_modalities, [:text])
        |> Keyword.merge(
          on_chunk: fn chunk ->
            send(parent, {:chunk, ref, chunk})
          end,
          on_complete: fn ->
            send(parent, {:complete, ref})
          end,
          on_error: fn error ->
            send(parent, {:error, ref, error})
          end
        )

      case gemini_module().stream_generate(prompt, opts) do
        {:ok, _stream_id} -> :ok
        {:error, reason} -> send(parent, {:error, ref, reason})
      end
    end)

    {:streaming, ref}
  end

  defp continue_streaming({:streaming, ref}) do
    receive do
      {:chunk, ^ref, chunk} ->
        {[%{delta: chunk, finish_reason: nil}], {:streaming, ref}}

      {:complete, ^ref} ->
        {[%{delta: "", finish_reason: :stop}], {:done, ref}}

      {:error, ^ref, reason} ->
        Logger.error("Streaming error: #{inspect(reason)}")
        {:halt, {:error, reason}}
    after
      30_000 ->
        {:halt, {:error, :timeout}}
    end
  end

  defp continue_streaming({:done, _ref}) do
    {:halt, :done}
  end

  defp continue_streaming({:error, _reason} = state) do
    {:halt, state}
  end

  defp estimate_tokens(text) when is_binary(text) do
    # Rough estimation: ~4 characters per token
    div(String.length(text), 4) + 1
  end

  defp estimate_tokens(_), do: 0

  defp gemini_module do
    Application.get_env(:portfolio_index, :gemini_sdk, Gemini)
  end

  defp emit_telemetry(operation, measurements, metadata) do
    :telemetry.execute(
      [:portfolio_index, :llm, operation],
      measurements,
      metadata
    )
  end
end
