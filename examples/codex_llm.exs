# Codex SDK LLM Adapter Example
#
# This example demonstrates using the Codex adapter which uses the
# codex_sdk library (OpenAI's agentic SDK).
#
# Note: This is different from the OpenAI adapter which uses openai_ex
# for direct API access. The Codex adapter provides agentic features.
#
# Usage:
#   mix run examples/codex_llm.exs

alias PortfolioIndex.Adapters.LLM.Codex

IO.puts("=== Codex SDK LLM Adapter Example ===\n")

messages = [
  %{role: :user, content: "Summarize Elixir in one short sentence."}
]

case Codex.complete(messages, max_tokens: 64) do
  {:ok, result} ->
    IO.puts("Model: #{result.model}")
    IO.puts("\nResponse:\n#{result.content}")

  {:error, reason} ->
    IO.puts("Codex error: #{inspect(reason)}")
end
