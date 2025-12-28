defmodule PortfolioIndex.RAG.AdapterResolver do
  @moduledoc false

  alias PortfolioCore.Registry

  @spec resolve(map(), atom(), module()) :: {module(), keyword()}
  def resolve(context, port_name, default_module) do
    case adapter_from_context(context, port_name) || adapter_from_registry(port_name) do
      {module, opts} -> {module, normalize_opts(opts)}
      nil -> {default_module, []}
    end
  end

  defp adapter_from_context(%{adapters: adapters}, port_name) when is_map(adapters) do
    case Map.get(adapters, port_name) do
      {module, opts} when is_atom(module) and not is_nil(module) -> {module, opts}
      module when is_atom(module) and not is_nil(module) -> {module, []}
      _ -> nil
    end
  end

  defp adapter_from_context(_context, _port_name), do: nil

  defp adapter_from_registry(port_name) do
    case Registry.get(port_name) do
      {:ok, %{module: module, config: opts}} -> {module, opts}
      {:error, :not_found} -> nil
    end
  end

  defp normalize_opts(opts) when is_list(opts), do: opts
  defp normalize_opts(opts) when is_map(opts), do: Map.to_list(opts)
  defp normalize_opts(_opts), do: []
end
