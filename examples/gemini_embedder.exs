alias PortfolioIndex.Adapters.Embedder.Gemini

case Gemini.embed("Hello from Gemini", []) do
  {:ok, result} ->
    IO.puts("Model: #{result.model}")
    IO.puts("Dimensions: #{result.dimensions}")
    IO.puts("Token count: #{result.token_count}")

  {:error, reason} ->
    IO.puts("Gemini error: #{inspect(reason)}")
end
