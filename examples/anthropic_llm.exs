alias PortfolioIndex.Adapters.LLM.Anthropic

messages = [
  %{role: :user, content: "Say hello in one short sentence."}
]

case Anthropic.complete(messages, max_tokens: 64) do
  {:ok, result} ->
    IO.puts("Model: #{result.model}")
    IO.puts("\nResponse:\n#{result.content}")

  {:error, reason} ->
    IO.puts("Anthropic error: #{inspect(reason)}")
end
