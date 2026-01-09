defmodule PortfolioIndex.Adapters.LLM.Ollama do
  @behaviour PortfolioCore.Ports.LLM

  @moduledoc """
  Ollama LLM adapter using the `ollixir` client library.

  ## Configuration

      config :portfolio_index, :ollama,
        base_url: "http://localhost:11434/api",
        model: "llama3.2",
        models: ["llama3.2", "phi4"],
        model_info: %{
          "llama3.2" => %{context_window: 8192, max_output: 2048, supports_tools: true}
        }
  """

  require Logger

  alias PortfolioIndex.Adapters.RateLimiter
  alias PortfolioIndex.Telemetry.Context

  @default_model "llama3.2"
  @default_model_info %{
    context_window: 8192,
    max_output: 2048,
    supports_tools: true
  }

  @impl true
  def complete(messages, opts \\ []) do
    RateLimiter.wait(:ollama, :chat)

    with {:ok, client} <- build_client(opts),
         params <- build_chat_params(messages, opts),
         {:ok, response} <- sdk().chat(client, params) do
      RateLimiter.record_success(:ollama, :chat)
      emit_telemetry(:complete, %{model: response_model(response) || params[:model]}, opts)
      {:ok, normalize_response(response)}
    else
      {:error, reason} ->
        RateLimiter.record_failure(:ollama, :chat, detect_failure_type(reason))
        Logger.error("Ollama completion failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def stream(messages, opts \\ []) do
    opts = Keyword.put(opts, :stream, true)

    with {:ok, client} <- build_client(opts),
         params <- build_chat_params(messages, opts),
         {:ok, stream} <- sdk().chat(client, params) do
      {:ok, normalize_stream(stream)}
    else
      {:error, reason} ->
        Logger.error("Ollama streaming failed: #{inspect(reason)}")
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
    client_opts =
      []
      |> maybe_put(:base_url, Keyword.get(opts, :base_url) || configured_base_url())
      |> maybe_put(:receive_timeout, Keyword.get(opts, :receive_timeout) || configured_timeout())
      |> maybe_put(:headers, Keyword.get(opts, :headers) || configured_headers())

    {:ok, sdk().init(client_opts)}
  end

  defp build_chat_params(messages, opts) do
    model = Keyword.get(opts, :model) || configured_model() || @default_model
    options = build_options(opts)

    []
    |> Keyword.put(:model, model)
    |> Keyword.put(:messages, convert_messages(messages))
    |> maybe_put(:options, empty_map_to_nil(options))
    |> maybe_put(:tools, Keyword.get(opts, :tools))
    |> maybe_put(:format, Keyword.get(opts, :format))
    |> maybe_put(:keep_alive, Keyword.get(opts, :keep_alive))
    |> maybe_put(:stream, Keyword.get(opts, :stream))
  end

  defp build_options(opts) do
    max_tokens = Keyword.get(opts, :num_predict) || Keyword.get(opts, :max_tokens)

    options =
      %{}
      |> maybe_put_map(:temperature, Keyword.get(opts, :temperature))
      |> maybe_put_map(:top_p, Keyword.get(opts, :top_p))
      |> maybe_put_map(:top_k, Keyword.get(opts, :top_k))
      |> maybe_put_map(:frequency_penalty, Keyword.get(opts, :frequency_penalty))
      |> maybe_put_map(:presence_penalty, Keyword.get(opts, :presence_penalty))
      |> maybe_put_map(:repeat_penalty, Keyword.get(opts, :repeat_penalty))
      |> maybe_put_map(:seed, Keyword.get(opts, :seed))
      |> maybe_put_map(:stop, Keyword.get(opts, :stop))
      |> maybe_put_map(:num_predict, max_tokens)

    case Keyword.get(opts, :extra) do
      extra when is_map(extra) -> Map.merge(extra, options)
      extra when is_list(extra) -> Map.merge(Map.new(extra), options)
      _ -> options
    end
  end

  defp convert_messages(messages) do
    Enum.map(messages, &convert_message/1)
  end

  defp convert_message(%{} = msg) do
    role = Map.get(msg, :role) || Map.get(msg, "role") || "user"
    content = Map.get(msg, :content) || Map.get(msg, "content")

    msg
    |> Map.drop([:role, "role", :content, "content"])
    |> Map.merge(%{role: to_string(role), content: content})
  end

  defp convert_message(content) when is_binary(content) do
    %{role: "user", content: content}
  end

  defp convert_message(_), do: %{role: "user", content: ""}

  defp normalize_response(response) do
    message = fetch_value(response, [:message, "message"], %{})

    %{
      content: fetch_value(message, [:content, "content"], ""),
      model: response_model(response),
      usage: normalize_usage(response),
      finish_reason: normalize_finish_reason(fetch_value(response, [:done_reason, "done_reason"]))
    }
  end

  defp response_model(response) do
    fetch_value(response, [:model, "model"])
  end

  defp normalize_usage(response) do
    %{
      input_tokens: fetch_value(response, [:prompt_eval_count, "prompt_eval_count"], 0),
      output_tokens: fetch_value(response, [:eval_count, "eval_count"], 0)
    }
  end

  defp normalize_finish_reason("stop"), do: :stop
  defp normalize_finish_reason("length"), do: :length
  defp normalize_finish_reason("tool_calls"), do: :tool_use
  defp normalize_finish_reason("tool_use"), do: :tool_use
  defp normalize_finish_reason(nil), do: nil
  defp normalize_finish_reason(_), do: :stop

  defp normalize_stream(stream) do
    stream
    |> Stream.flat_map(fn chunk ->
      case extract_delta(chunk) do
        nil -> []
        delta -> [%{delta: delta, finish_reason: nil}]
      end
    end)
    |> Stream.concat([%{delta: "", finish_reason: :stop}])
  end

  defp extract_delta(%{delta: delta}) when is_binary(delta), do: delta

  defp extract_delta(%{"message" => %{"content" => content}}) when is_binary(content),
    do: content

  defp extract_delta(%{message: %{content: content}}) when is_binary(content), do: content

  defp extract_delta(%{"content" => content}) when is_binary(content), do: content
  defp extract_delta(%{content: content}) when is_binary(content), do: content
  defp extract_delta(_), do: nil

  defp config do
    Application.get_env(:portfolio_index, :ollama, [])
  end

  defp configured_base_url do
    config()[:base_url]
  end

  defp configured_model do
    config()[:model]
  end

  defp configured_timeout do
    config()[:receive_timeout]
  end

  defp configured_headers do
    config()[:headers]
  end

  defp sdk do
    Application.get_env(:portfolio_index, :ollama_sdk, Ollixir)
  end

  defp emit_telemetry(event, metadata, opts) do
    metadata = Context.merge(metadata, opts)

    :telemetry.execute(
      [:portfolio_index, :llm, :ollama, event],
      %{count: 1},
      metadata
    )
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

  defp fetch_model_info(info_map, model) when is_map(info_map) do
    Map.get(info_map, model) || Map.get(info_map, to_string(model)) || @default_model_info
  end

  defp fetch_model_info(_, _model), do: @default_model_info

  defp fetch_value(map, keys, default \\ nil)

  defp fetch_value(map, keys, default) when is_map(map) do
    Enum.find_value(keys, default, &Map.get(map, &1))
  end

  defp fetch_value(_map, _keys, default), do: default

  defp maybe_put(keyword, _key, nil), do: keyword
  defp maybe_put(keyword, key, value), do: Keyword.put(keyword, key, value)

  defp maybe_put_map(map, _key, nil), do: map
  defp maybe_put_map(map, key, value), do: Map.put(map, key, value)

  defp empty_map_to_nil(map) when map_size(map) == 0, do: nil
  defp empty_map_to_nil(map), do: map
end
