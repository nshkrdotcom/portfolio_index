defmodule PortfolioIndex.Examples.OllamaHelpers do
  @moduledoc false

  @setup_command "mix run examples/ollama_setup.exs"

  def ensure_model!(model, base_url \\ nil) do
    client = build_client(base_url)

    case Ollixir.list_models(client, response_format: :struct) do
      {:ok, list} ->
        names = Ollixir.Types.ListResponse.names(list)

        if model_available?(names, model) do
          :ok
        else
          print_missing_model(model)
          System.halt(1)
        end

      {:error, reason} ->
        print_unreachable(reason, base_url)
        System.halt(1)
    end
  end

  defp model_available?(names, model) do
    normalized = Enum.map(names, &normalize_name/1)
    Enum.member?(normalized, normalize_name(model))
  end

  defp normalize_name(name) do
    name
    |> to_string()
    |> String.replace_suffix(":latest", "")
  end

  defp build_client(nil), do: Ollixir.init()
  defp build_client(base_url), do: Ollixir.init(base_url: base_url)

  defp print_missing_model(model) do
    IO.puts("Ollama model not found: #{model}")
    IO.puts("Install with: ollama pull #{model}")
    IO.puts("Or run: #{@setup_command}")
  end

  defp print_unreachable(reason, base_url) do
    location = base_url || "http://localhost:11434"

    IO.puts("Ollama server not reachable at #{location}.")
    IO.puts("Start Ollama (ollama serve) and retry.")
    IO.puts("Error: #{inspect(reason)}")
  end
end
