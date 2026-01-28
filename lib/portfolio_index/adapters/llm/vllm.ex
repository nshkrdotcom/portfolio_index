defmodule PortfolioIndex.Adapters.LLM.VLLM do
  @behaviour PortfolioCore.Ports.LLM

  @moduledoc """
  vLLM adapter using the `vllm` Elixir library (SnakeBridge).

  This adapter runs vLLM locally via Python and requires a CUDA-capable NVIDIA GPU.

  ## Configuration

      config :portfolio_index, :vllm,
        model: "Qwen/Qwen2-0.5B-Instruct",
        models: ["Qwen/Qwen2-0.5B-Instruct"],
        llm: [max_model_len: 2048, gpu_memory_utilization: 0.8],
        sampling: [temperature: 0.2, max_tokens: 128],
        run: [],
        model_info: %{
          "Qwen/Qwen2-0.5B-Instruct" => %{
            context_window: 2048,
            max_output: 2048,
            supports_tools: false
          }
        }
  """

  require Logger

  alias PortfolioIndex.Adapters.RateLimiter
  alias PortfolioIndex.Telemetry.Context

  @default_model "Qwen/Qwen2-0.5B-Instruct"

  @default_model_info %{
    context_window: 2048,
    max_output: 2048,
    supports_tools: false
  }

  @default_llm_opts [
    max_model_len: 2048,
    gpu_memory_utilization: 0.8
  ]

  @default_sampling_opts [
    temperature: 0.2,
    max_tokens: 128
  ]

  @sampling_keys [
    :temperature,
    :top_p,
    :top_k,
    :max_tokens,
    :min_tokens,
    :presence_penalty,
    :frequency_penalty,
    :repetition_penalty,
    :stop,
    :stop_token_ids,
    :n,
    :best_of,
    :seed
  ]

  @impl true
  def complete(messages, opts \\ []) do
    RateLimiter.wait(:vllm, :chat)

    result =
      try do
        sdk().run(fn -> complete_in_runtime(messages, opts) end, run_opts(opts))
      rescue
        error -> {:error, error}
      end

    case normalize_run_result(result) do
      {:ok, response} ->
        RateLimiter.record_success(:vllm, :chat)
        emit_telemetry(:complete, %{model: response.model}, opts)
        {:ok, response}

      {:error, reason} ->
        RateLimiter.record_failure(:vllm, :chat, detect_failure_type(reason))
        Logger.error("vLLM completion failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def stream(messages, opts \\ []) do
    case complete(messages, opts) do
      {:ok, result} ->
        chunks =
          case result.content do
            "" -> []
            content -> [%{delta: content, finish_reason: nil}]
          end

        stream = Stream.concat([chunks, [%{delta: "", finish_reason: :stop}]])
        {:ok, stream}

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

  defp complete_in_runtime(messages, opts) do
    model = Keyword.get(opts, :model) || configured_model() || @default_model
    llm = sdk().llm!(model, llm_opts(opts))
    sampling_params = build_sampling_params(opts)

    chat_opts =
      []
      |> maybe_put(:sampling_params, sampling_params)
      |> maybe_put(:use_tqdm, Keyword.get(opts, :use_tqdm))

    outputs = sdk().chat!(llm, [convert_messages(messages)], chat_opts)
    output = List.first(outputs) || %{}
    completion = first_completion(output)

    content = fetch_attr(completion, "text") || ""
    finish_reason = normalize_finish_reason(fetch_attr(completion, "finish_reason"))

    input_tokens =
      fetch_attr(output, "prompt_token_ids")
      |> token_count_from_ids()
      |> fallback_tokens(estimate_message_tokens(messages))

    output_tokens =
      fetch_attr(completion, "token_ids")
      |> token_count_from_ids()
      |> fallback_tokens(estimate_tokens(content))

    response_model = fetch_attr(output, "model") || model

    {:ok,
     %{
       content: content,
       model: response_model,
       usage: %{
         input_tokens: input_tokens,
         output_tokens: output_tokens
       },
       finish_reason: finish_reason,
       response_id: nil
     }}
  end

  defp first_completion(output) do
    case fetch_attr(output, "outputs") do
      [first | _] -> first
      _ -> %{}
    end
  end

  defp convert_messages(messages) do
    Enum.map(messages, &convert_message/1)
  end

  defp convert_message(%{role: role, content: content}) do
    %{"role" => to_string(role), "content" => content}
  end

  defp convert_message(%{"role" => role, "content" => content}) do
    %{"role" => to_string(role), "content" => content}
  end

  defp convert_message(msg) when is_map(msg) do
    role = Map.get(msg, :role) || Map.get(msg, "role") || "user"
    content = Map.get(msg, :content) || Map.get(msg, "content") || ""
    %{"role" => to_string(role), "content" => content}
  end

  defp convert_message(content) when is_binary(content) do
    %{"role" => "user", "content" => content}
  end

  defp convert_message(_), do: %{"role" => "user", "content" => ""}

  defp build_sampling_params(opts) do
    sampling_opts =
      @default_sampling_opts
      |> Keyword.merge(configured_sampling_opts())
      |> Keyword.merge(Keyword.get(opts, :sampling, []))
      |> Keyword.merge(Keyword.get(opts, :sampling_params, []))
      |> Keyword.merge(take_present(opts, @sampling_keys))
      |> compact_opts()

    if sampling_opts == [] do
      nil
    else
      sdk().sampling_params!(sampling_opts)
    end
  end

  defp llm_opts(opts) do
    base =
      @default_llm_opts
      |> Keyword.merge(configured_llm_opts())

    overrides =
      opts
      |> Keyword.get(:llm, Keyword.get(opts, :llm_options, []))

    base
    |> Keyword.merge(overrides)
    |> Keyword.delete(:model)
  end

  defp run_opts(opts) do
    configured_run_opts()
    |> Keyword.merge(Keyword.get(opts, :run, Keyword.get(opts, :run_opts, [])))
  end

  defp configured_llm_opts do
    config()[:llm] || config()[:llm_options] || []
  end

  defp configured_sampling_opts do
    config()[:sampling] || config()[:sampling_params] || []
  end

  defp configured_run_opts do
    config()[:run] || config()[:run_opts] || []
  end

  defp normalize_run_result({:ok, _} = ok), do: ok
  defp normalize_run_result({:error, _} = error), do: error
  defp normalize_run_result(%{} = response), do: {:ok, response}
  defp normalize_run_result(other), do: {:error, other}

  defp fetch_attr(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, to_string(key)) || Map.get(map, String.to_atom(key))
  end

  defp fetch_attr(ref, key) do
    sdk().attr!(ref, to_string(key))
  end

  defp token_count_from_ids(ids) when is_list(ids), do: length(ids)
  defp token_count_from_ids(_), do: 0

  defp fallback_tokens(0, fallback), do: fallback
  defp fallback_tokens(value, _fallback), do: value

  defp estimate_message_tokens(messages) do
    messages
    |> Enum.map(&extract_content/1)
    |> Enum.join(" ")
    |> estimate_tokens()
  end

  defp extract_content(%{content: content}) when is_binary(content), do: content
  defp extract_content(%{"content" => content}) when is_binary(content), do: content
  defp extract_content(content) when is_binary(content), do: content
  defp extract_content(_), do: ""

  defp estimate_tokens(text) do
    div(String.length(text), 4) + 1
  end

  defp normalize_finish_reason("stop"), do: :stop
  defp normalize_finish_reason("length"), do: :length
  defp normalize_finish_reason(nil), do: :stop
  defp normalize_finish_reason(_), do: :stop

  defp config do
    Application.get_env(:portfolio_index, :vllm, [])
  end

  defp configured_model do
    config()[:model]
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

  defp sdk do
    Application.get_env(:portfolio_index, :vllm_sdk, VLLM)
  end

  defp maybe_put(keyword, _key, nil), do: keyword
  defp maybe_put(keyword, key, value), do: Keyword.put(keyword, key, value)

  defp take_present(opts, keys) do
    opts
    |> Keyword.take(keys)
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp compact_opts(opts) do
    Enum.reject(opts, fn {_key, value} -> is_nil(value) end)
  end
end
