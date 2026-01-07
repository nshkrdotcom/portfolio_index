# Gemini LLM Adapter Example
#
# Usage:
#   mix run examples/gemini_llm.exs

alias PortfolioIndex.Adapters.LLM.Gemini

messages = [
  %{role: :user, content: "Say hello in one short sentence."}
]

case Gemini.complete(messages, max_tokens: 64) do
  {:ok, result} ->
    IO.puts("Model: #{result.model}")
    IO.puts("\nResponse:\n#{result.content}")

  {:error, reason} ->
    IO.puts("Gemini error: #{inspect(reason)}")
end
