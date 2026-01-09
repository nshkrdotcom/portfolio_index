defmodule PortfolioIndex.Telemetry.Context do
  @moduledoc """
  Helpers for merging lineage context fields into telemetry metadata.

  Standard context keys align with LineageIR and RunIndex conventions:
  `trace_id`, `work_id`, `plan_id`, and `step_id`.
  """

  @context_keys [:trace_id, :work_id, :plan_id, :step_id]

  @doc """
  Merge telemetry metadata with lineage context from opts.

  Precedence (highest last):
  1) context fields from opts
  2) telemetry_metadata from opts
  3) explicit metadata argument
  """
  @spec merge(map() | keyword(), keyword()) :: map()
  def merge(metadata, opts \\ [])

  def merge(metadata, opts) when is_list(metadata) do
    merge(Map.new(metadata), opts)
  end

  def merge(metadata, opts) when is_map(metadata) do
    context = context_from_opts(opts)
    extra = telemetry_metadata_from_opts(opts)

    context
    |> Map.merge(extra)
    |> Map.merge(metadata)
  end

  defp context_from_opts(opts) do
    opts
    |> Keyword.take(@context_keys)
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp telemetry_metadata_from_opts(opts) do
    case Keyword.get(opts, :telemetry_metadata) do
      nil -> %{}
      metadata when is_map(metadata) -> metadata
      metadata when is_list(metadata) -> Map.new(metadata)
      _ -> %{}
    end
  end
end
