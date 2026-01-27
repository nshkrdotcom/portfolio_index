# vLLM LLM Adapter Example
#
# Requirements:
#   - CUDA-capable NVIDIA GPU
#   - Python runtime via SnakeBridge: mix snakebridge.setup
#
# Optional:
#   - VLLM_MODEL (default: Qwen/Qwen2-0.5B-Instruct)
#   - HF_TOKEN (for gated HuggingFace models)
#
# Usage:
#   mix run examples/vllm_llm.exs

alias PortfolioIndex.Adapters.LLM.VLLM

IO.puts("=== vLLM LLM Adapter Example ===\n")
IO.puts("Note: vLLM requires a CUDA-capable NVIDIA GPU.\n")

model = System.get_env("VLLM_MODEL") || "Qwen/Qwen2-0.5B-Instruct"

opts = [
  model: model,
  max_tokens: 128,
  temperature: 0.2,
  llm: [max_model_len: 2048, gpu_memory_utilization: 0.8]
]

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
IO.puts("(Streaming is returned as a single chunk for vLLM.)\n")

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
