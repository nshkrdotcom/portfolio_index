# OpenAI LLM Adapter Example
#
# This example demonstrates using the OpenAI adapter which communicates
# directly with the OpenAI API via the openai_ex library.
#
# Prerequisites:
#   - Set OPENAI_API_KEY environment variable
#   - Run: mix deps.get
#
# Usage:
#   mix run examples/openai_llm.exs

alias PortfolioIndex.Adapters.LLM.OpenAI

IO.puts("=== OpenAI LLM Adapter Example ===\n")

# Basic completion
IO.puts("--- Basic Completion ---")

messages = [
  %{role: :system, content: "You are a concise technical assistant."},
  %{role: :user, content: "Explain Elixir's concurrency model in 2-3 sentences."}
]

case OpenAI.complete(messages, model: "gpt-4o-mini", max_tokens: 150) do
  {:ok, result} ->
    IO.puts("Model: #{result.model}")
    IO.puts("Tokens: #{result.usage.input_tokens} in / #{result.usage.output_tokens} out")
    IO.puts("\nResponse:\n#{result.content}")

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end

IO.puts("\n--- Streaming Completion ---")

stream_messages = [
  %{
    role: :user,
    content: "Count from 1 to 5, with a brief pause description between each number."
  }
]

case OpenAI.stream(stream_messages, model: "gpt-4o-mini", max_tokens: 100) do
  {:ok, stream} ->
    IO.write("Streaming: ")

    stream
    |> Enum.each(fn chunk ->
      case chunk do
        %{delta: delta, finish_reason: nil} when delta != "" ->
          IO.write(delta)

        %{finish_reason: reason} when not is_nil(reason) ->
          IO.puts("\n[Finished: #{reason}]")

        _ ->
          :ok
      end
    end)

  {:error, reason} ->
    IO.puts("Stream error: #{inspect(reason)}")
end

IO.puts("\n--- Model Information ---")

IO.puts("Supported models: #{Enum.join(OpenAI.supported_models(), ", ")}")

info = OpenAI.model_info("gpt-4o-mini")
IO.puts("gpt-4o-mini context window: #{info.context_window}")
IO.puts("gpt-4o-mini max output: #{info.max_output}")
IO.puts("gpt-4o-mini supports tools: #{info.supports_tools}")
