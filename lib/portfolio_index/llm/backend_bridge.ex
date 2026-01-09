defmodule PortfolioIndex.LLM.BackendBridge do
  @moduledoc """
  Optional bridge for CrucibleIR backend prompts and completions.

  Converts backend prompt structs into PortfolioCore-compatible message
  lists plus adapter options, and builds completion maps from adapter results.
  """

  @type message :: %{role: atom() | String.t(), content: String.t()}

  @spec prompt_to_messages(map()) :: {:ok, {list(message()), keyword()}} | {:error, term()}
  def prompt_to_messages(prompt) when is_map(prompt) do
    messages = build_messages(prompt)
    opts = build_opts(prompt)
    {:ok, {messages, opts}}
  end

  def prompt_to_messages(_), do: {:error, :invalid_prompt}

  @spec completion_from_result(map(), map(), keyword()) :: map()
  def completion_from_result(result, prompt, opts \\ [])

  def completion_from_result(result, prompt, opts) when is_map(result) do
    usage = normalize_usage(fetch_value(result, :usage, %{}))

    completion = %{
      model: fetch_value(result, :model),
      trace_id: fetch_value(prompt, :trace_id),
      request_id: fetch_value(prompt, :request_id),
      raw_response: Keyword.get(opts, :raw_response),
      usage: usage,
      choices: [
        %{
          index: 0,
          message: %{role: :assistant, content: fetch_value(result, :content, "")},
          finish_reason: fetch_value(result, :finish_reason)
        }
      ]
    }

    drop_nil(completion, :raw_response)
  end

  def completion_from_result(_result, _prompt, _opts), do: %{}

  defp build_messages(prompt) do
    system = fetch_value(prompt, :system)
    messages = fetch_value(prompt, :messages, []) |> List.wrap()
    normalized = Enum.map(messages, &normalize_message/1)

    if is_binary(system) and system != "" do
      [%{role: :system, content: system} | normalized]
    else
      normalized
    end
  end

  defp normalize_message(%{} = msg) do
    role = fetch_value(msg, :role, :user)
    content = fetch_value(msg, :content, "")

    msg
    |> Map.drop([:role, "role", :content, "content"])
    |> Map.merge(%{role: normalize_role(role), content: content})
  end

  defp normalize_message(content) when is_binary(content) do
    %{role: :user, content: content}
  end

  defp normalize_message(_), do: %{role: :user, content: ""}

  defp normalize_role(role) when is_atom(role), do: role

  defp normalize_role(role) when is_binary(role) do
    case String.downcase(role) do
      "system" -> :system
      "user" -> :user
      "assistant" -> :assistant
      "tool" -> :tool
      _ -> role
    end
  end

  defp normalize_role(_), do: :user

  defp build_opts(prompt) do
    options = fetch_value(prompt, :options, %{})

    []
    |> maybe_put(:model, fetch_value(options, :model))
    |> maybe_put(:temperature, fetch_value(options, :temperature))
    |> maybe_put(:max_tokens, fetch_value(options, :max_tokens))
    |> maybe_put(:top_p, fetch_value(options, :top_p))
    |> maybe_put(:stop, fetch_value(options, :stop))
    |> maybe_put(:receive_timeout, fetch_value(options, :timeout_ms))
    |> maybe_put(:extra, normalize_map(fetch_value(options, :extra)))
    |> maybe_put(:tools, fetch_value(prompt, :tools))
    |> maybe_put(:tool_choice, fetch_value(prompt, :tool_choice))
    |> maybe_put(:trace_id, fetch_value(prompt, :trace_id))
    |> maybe_put(:request_id, fetch_value(prompt, :request_id))
    |> maybe_put(:telemetry_metadata, normalize_map(fetch_value(prompt, :metadata)))
  end

  defp normalize_usage(usage) when is_map(usage) do
    prompt_tokens =
      fetch_value(usage, :input_tokens) || fetch_value(usage, :prompt_tokens) || 0

    completion_tokens =
      fetch_value(usage, :output_tokens) || fetch_value(usage, :completion_tokens) || 0

    %{
      prompt_tokens: prompt_tokens,
      completion_tokens: completion_tokens,
      total_tokens: prompt_tokens + completion_tokens
    }
  end

  defp normalize_usage(_), do: %{prompt_tokens: 0, completion_tokens: 0, total_tokens: 0}

  defp normalize_map(nil), do: nil
  defp normalize_map(%{} = map), do: map
  defp normalize_map(list) when is_list(list), do: Map.new(list)
  defp normalize_map(_), do: nil

  defp fetch_value(map, key, default \\ nil)

  defp fetch_value(map, key, default) when is_map(map) do
    key_string = Atom.to_string(key)

    cond do
      Map.has_key?(map, key) -> Map.get(map, key)
      Map.has_key?(map, key_string) -> Map.get(map, key_string)
      true -> default
    end
  end

  defp fetch_value(_map, _key, default), do: default

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp drop_nil(map, key) do
    if Map.get(map, key) == nil do
      Map.delete(map, key)
    else
      map
    end
  end
end
