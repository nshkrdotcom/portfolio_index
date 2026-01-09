# vLLM LLM Adapter Example
#
# Requirements:
#   - vLLM running with OpenAI-compatible API (default: http://localhost:8000/v1)
#
# Optional:
#   - VLLM_BASE_URL (default: http://localhost:8000/v1)
#   - VLLM_MODEL (default: llama3)
#   - VLLM_API_KEY (optional)
#
# Usage:
#   mix run examples/vllm_llm.exs

alias PortfolioIndex.Adapters.LLM.VLLM

IO.puts("=== vLLM LLM Adapter Example ===\n")

base_url = System.get_env("VLLM_BASE_URL") || "http://localhost:8000/v1"
model = System.get_env("VLLM_MODEL") || "llama3"

opts = [model: model, base_url: base_url, max_tokens: 128, temperature: 0.2]

messages = [
  %{role: :user, content: "Say hello in one short sentence."}
]

case VLLM.complete(messages, opts) do
  {:ok, result} ->
    IO.puts("Model: #{result.model}")
    IO.puts("Tokens: #{result.usage.input_tokens} in / #{result.usage.output_tokens} out")
    IO.puts("\nResponse:\n#{result.content}")

  {:error, reason} ->
    IO.puts("vLLM error: #{inspect(reason)}")
end

IO.puts("\n--- Streaming Completion ---")

stream_messages = [
  %{role: :user, content: "Count from 1 to 5, separating with commas."}
]

case VLLM.stream(stream_messages, opts) do
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
