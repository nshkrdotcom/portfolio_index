# Ollama Model Setup
#
# Ensures required Ollama models are installed for local examples.
#
# Usage:
#   mix run examples/ollama_setup.exs

models = [
  "llama3.2",
  "nomic-embed-text"
]

base_url = System.get_env("OLLAMA_BASE_URL")

client =
  if base_url do
    Ollixir.init(base_url: base_url)
  else
    Ollixir.init()
  end

names =
  case Ollixir.list_models(client, response_format: :struct) do
    {:ok, list} ->
      Ollixir.Types.ListResponse.names(list)

    {:error, reason} ->
      location = base_url || "http://localhost:11434"
      IO.puts("Ollama server not reachable at #{location}.")
      IO.puts("Start Ollama (ollama serve) and retry.")
      IO.puts("Error: #{inspect(reason)}")
      System.halt(1)
  end

normalize = fn name ->
  name
  |> to_string()
  |> String.replace_suffix(":latest", "")
end

installed = MapSet.new(Enum.map(names, normalize))

missing =
  models
  |> Enum.reject(fn model -> MapSet.member?(installed, normalize.(model)) end)

if missing == [] do
  IO.puts("All required Ollama models are already installed.")
  System.halt(0)
end

Enum.each(missing, fn model ->
  IO.puts("Pulling #{model} (this may take a while on first run)...")

  case Ollixir.pull_model(client, name: model, stream: true) do
    {:ok, stream} ->
      stream
      |> Enum.each(fn chunk ->
        status = chunk["status"] || "working"

        line =
          case {chunk["completed"], chunk["total"]} do
            {completed, total} when is_number(completed) and is_number(total) and total > 0 ->
              percent = Float.round(completed / total * 100, 1)
              "#{status} (#{percent}%)"

            _ ->
              status
          end

        IO.puts(line)
      end)

    {:error, reason} ->
      IO.puts("Failed to pull #{model}: #{inspect(reason)}")
      System.halt(1)
  end
end)

IO.puts("Done.")
