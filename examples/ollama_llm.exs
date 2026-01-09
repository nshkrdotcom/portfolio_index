# Ollama LLM Adapter Example
#
# Requirements:
#   - Ollama running locally (default: http://localhost:11434)
#   - Model pulled, e.g.: ollama pull llama3.2
#
# Optional:
#   - OLLAMA_BASE_URL (default: http://localhost:11434/api)
#   - OLLAMA_MODEL (default: llama3.2)
#
# Usage:
#   mix run examples/ollama_llm.exs

alias PortfolioIndex.Adapters.LLM.Ollama

Code.require_file(Path.join(__DIR__, "support/ollama_helpers.exs"))

IO.puts("=== Ollama LLM Adapter Example ===\n")

model = System.get_env("OLLAMA_MODEL") || "llama3.2"
base_url = System.get_env("OLLAMA_BASE_URL")

PortfolioIndex.Examples.OllamaHelpers.ensure_model!(model, base_url)

opts = [model: model, max_tokens: 128, temperature: 0.2]
opts = if base_url, do: Keyword.put(opts, :base_url, base_url), else: opts

messages = [
  %{role: :user, content: "Say hello in one short sentence."}
]

case Ollama.complete(messages, opts) do
  {:ok, result} ->
    IO.puts("Model: #{result.model}")
    IO.puts("Tokens: #{result.usage.input_tokens} in / #{result.usage.output_tokens} out")
    IO.puts("\nResponse:\n#{result.content}")

  {:error, reason} ->
    IO.puts("Ollama error: #{inspect(reason)}")
    System.halt(1)
end

IO.puts("\n--- Streaming Completion ---")

stream_messages = [
  %{role: :user, content: "Count from 1 to 5, separating with commas."}
]

case Ollama.stream(stream_messages, opts) do
  {:ok, stream} ->
    IO.write("Streaming: ")

    try do
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
    rescue
      error ->
        IO.puts("\nStream error: #{inspect(error)}")
        System.halt(1)
    end

  {:error, reason} ->
    IO.puts("Stream error: #{inspect(reason)}")
    System.halt(1)
end
