alias PortfolioIndex.Adapters.LLM.OpenAI

messages = [
  %{role: :user, content: "Summarize Elixir in one short sentence."}
]

case OpenAI.complete(messages, max_tokens: 64) do
  {:ok, result} ->
    IO.puts("Model: #{result.model}")
    IO.puts("\nResponse:\n#{result.content}")

  {:error, reason} ->
    IO.puts("OpenAI error: #{inspect(reason)}")
end
