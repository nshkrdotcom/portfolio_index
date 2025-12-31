defmodule PortfolioIndex.Telemetry.LLM do
  @moduledoc """
  LLM-specific telemetry utilities with enriched metadata.

  Provides utilities for wrapping LLM calls with telemetry instrumentation
  that tracks token usage, timing, and other LLM-specific metrics.

  ## Usage

      alias PortfolioIndex.Telemetry.LLM

      LLM.span(
        model: "claude-sonnet-4",
        provider: :anthropic,
        prompt_length: String.length(prompt)
      ], fn ->
        Anthropic.complete(messages)
      end)

  ## Metadata Fields

  The span automatically enriches metadata with:
  - `:model` - Model identifier
  - `:prompt_length` - Character count of prompt
  - `:prompt_tokens` - Estimated token count (if available)
  - `:response_length` - Character count of response
  - `:response_tokens` - Estimated token count (if available)
  - `:provider` - LLM provider (openai, anthropic, etc.)
  """

  @type token_usage :: %{
          optional(:input_tokens) => non_neg_integer(),
          optional(:output_tokens) => non_neg_integer(),
          optional(:total_tokens) => non_neg_integer()
        }

  @doc """
  Wrap an LLM call with telemetry, including token tracking.

  Emits `[:portfolio, :llm, :complete, :start]`, `[:portfolio, :llm, :complete, :stop]`,
  and `[:portfolio, :llm, :complete, :exception]` events.

  ## Parameters

    - `metadata` - Keyword list with LLM call context:
      - `:model` - Model identifier (required)
      - `:provider` - LLM provider (:anthropic, :openai, :gemini, etc.)
      - `:prompt_length` - Character count of prompt
      - `:prompt` - The prompt text (will extract length)
      - `:system` - System prompt (optional)
    - `fun` - Function that performs the LLM call

  ## Example

      LLM.span([model: "claude-sonnet-4", prompt_length: 892], fn ->
        Anthropic.complete(messages)
      end)
  """
  @spec span(keyword(), (-> result)) :: result when result: any()
  def span(metadata, fun) when is_function(fun, 0) do
    enriched_metadata = enrich_start_metadata(metadata)

    :telemetry.span(
      [:portfolio, :llm, :complete],
      Map.new(enriched_metadata),
      fn ->
        result = fun.()
        stop_meta = enrich_stop_metadata(result, enriched_metadata)
        {result, stop_meta}
      end
    )
  end

  @doc """
  Estimate token count for text.

  Uses simple heuristic: ~4 chars per token for English.
  This is a rough approximation; actual token counts vary by model and tokenizer.

  ## Examples

      LLM.estimate_tokens("Hello, world!")
      # => 3
  """
  @spec estimate_tokens(String.t()) :: non_neg_integer()
  def estimate_tokens(""), do: 0

  def estimate_tokens(text) when is_binary(text) do
    # Simple heuristic: ~4 chars per token for English text
    max(1, div(String.length(text), 4))
  end

  def estimate_tokens(_), do: 0

  @doc """
  Extract token usage from LLM response if available.

  Handles various response formats from different providers.

  ## Examples

      LLM.extract_usage(%{usage: %{input_tokens: 100, output_tokens: 50}})
      # => %{input_tokens: 100, output_tokens: 50, total_tokens: 150}
  """
  @spec extract_usage(map()) :: token_usage()
  def extract_usage(%{usage: usage}) when is_map(usage) do
    normalize_usage(usage)
  end

  def extract_usage(%{"usage" => usage}) when is_map(usage) do
    normalize_usage(usage)
  end

  def extract_usage(_), do: %{}

  # Private functions

  defp enrich_start_metadata(metadata) do
    base =
      metadata
      |> Keyword.take([:model, :provider, :prompt_length, :max_tokens, :temperature])
      |> Keyword.put_new(:model, "unknown")

    # Calculate prompt length if prompt provided
    base =
      case Keyword.get(metadata, :prompt) do
        prompt when is_binary(prompt) ->
          Keyword.put_new(base, :prompt_length, String.length(prompt))

        _ ->
          base
      end

    # Estimate tokens if we have prompt length
    case Keyword.get(base, :prompt_length) do
      len when is_integer(len) and len > 0 ->
        Keyword.put(base, :prompt_tokens, estimate_tokens_from_chars(len))

      _ ->
        base
    end
  end

  defp enrich_stop_metadata({:ok, response}, start_metadata) when is_map(response) do
    content = extract_content(response)
    usage = extract_usage(response)

    Map.new(start_metadata)
    |> Map.put(:success, true)
    |> Map.put(:response_length, String.length(content || ""))
    |> Map.put(:response_tokens, usage[:output_tokens] || estimate_tokens(content || ""))
    |> maybe_put(:input_tokens, usage[:input_tokens])
    |> maybe_put(:output_tokens, usage[:output_tokens])
    |> maybe_put(:total_tokens, usage[:total_tokens])
  end

  defp enrich_stop_metadata({:error, reason}, start_metadata) do
    Map.new(start_metadata)
    |> Map.put(:success, false)
    |> Map.put(:error, format_error(reason))
  end

  defp enrich_stop_metadata(response, start_metadata) when is_binary(response) do
    Map.new(start_metadata)
    |> Map.put(:success, true)
    |> Map.put(:response_length, String.length(response))
    |> Map.put(:response_tokens, estimate_tokens(response))
  end

  defp enrich_stop_metadata(_response, start_metadata) do
    Map.new(start_metadata)
    |> Map.put(:success, true)
  end

  defp extract_content(%{content: content}) when is_binary(content), do: content
  defp extract_content(%{"content" => content}) when is_binary(content), do: content
  defp extract_content(_), do: nil

  defp normalize_usage(usage) when is_map(usage) do
    input =
      get_token_value(usage, [:input_tokens, "input_tokens", :prompt_tokens, "prompt_tokens"])

    output =
      get_token_value(usage, [
        :output_tokens,
        "output_tokens",
        :completion_tokens,
        "completion_tokens"
      ])

    total =
      get_token_value(usage, [:total_tokens, "total_tokens"]) || (input || 0) + (output || 0)

    %{}
    |> maybe_put(:input_tokens, input)
    |> maybe_put(:output_tokens, output)
    |> maybe_put(:total_tokens, if(input || output, do: total, else: nil))
  end

  defp get_token_value(usage, keys) do
    Enum.find_value(keys, fn key ->
      case Map.get(usage, key) do
        nil -> nil
        val when is_integer(val) -> val
        _ -> nil
      end
    end)
  end

  defp estimate_tokens_from_chars(char_count) when is_integer(char_count) do
    max(1, div(char_count, 4))
  end

  defp format_error(reason) when is_binary(reason), do: reason

  defp format_error(reason) when is_atom(reason), do: Atom.to_string(reason)

  defp format_error(%{message: message}) when is_binary(message), do: message

  defp format_error(reason), do: inspect(reason)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
