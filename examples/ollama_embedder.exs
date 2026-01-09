# Ollama Embedder Example
#
# Requirements:
#   - Ollama running locally (default: http://localhost:11434)
#   - Model pulled, e.g.: ollama pull nomic-embed-text
#
# Optional:
#   - OLLAMA_BASE_URL (default: http://localhost:11434/api)
#
# Usage:
#   mix run examples/ollama_embedder.exs

alias PortfolioIndex.Adapters.Embedder.Ollama

Code.require_file(Path.join(__DIR__, "support/ollama_helpers.exs"))

IO.puts("=== Ollama Embedder Example ===\n")

model = "nomic-embed-text"
base_url = System.get_env("OLLAMA_BASE_URL")

PortfolioIndex.Examples.OllamaHelpers.ensure_model!(model, base_url)

opts = [model: model]
opts = if base_url, do: Keyword.put(opts, :base_url, base_url), else: opts

text = "Elixir is a functional language that runs on the BEAM VM."

case Ollama.embed(text, opts) do
  {:ok, result} ->
    IO.puts("Model: #{result.model}")
    IO.puts("Dimensions: #{result.dimensions}")
    IO.puts("Token count: #{result.token_count}")

  {:error, reason} ->
    IO.puts("Ollama embedder error: #{inspect(reason)}")
    System.halt(1)
end
