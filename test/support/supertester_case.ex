defmodule PortfolioIndex.SupertesterCase do
  @moduledoc """
  ExUnit case template with Supertester isolation and ETS table injection.
  """

  use ExUnit.CaseTemplate

  using opts do
    async? = Keyword.get(opts, :async, true)
    isolation = Keyword.get(opts, :isolation, :full_isolation)

    quote do
      use ExUnit.Case, async: unquote(async?)

      import Supertester.Assertions
      import Supertester.ETSIsolation
      import Supertester.GenServerHelpers
      import Supertester.OTPHelpers
      import PortfolioIndex.SupertesterCase

      setup context do
        {:ok, base_context} =
          Supertester.UnifiedTestFoundation.setup_isolation(unquote(isolation), context)

        :ok = PortfolioIndex.SupertesterCase.setup_ets_isolation()

        {:ok, %{isolation_context: base_context.isolation_context}}
      end
    end
  end

  @doc false
  def setup_ets_isolation do
    :ok = Supertester.ETSIsolation.setup_ets_isolation()

    {:ok, stats_table} =
      Supertester.ETSIsolation.create_isolated(:set, [
        :public,
        {:read_concurrency, true},
        {:write_concurrency, true}
      ])

    {:ok, registry_table} =
      Supertester.ETSIsolation.create_isolated(:set, [
        :public,
        {:read_concurrency, true},
        {:write_concurrency, true}
      ])

    {:ok, _} =
      Supertester.ETSIsolation.inject_table(
        PortfolioIndex.Adapters.RateLimiter,
        :stats_table,
        stats_table,
        create: false
      )

    {:ok, _} =
      Supertester.ETSIsolation.inject_table(
        PortfolioIndex.Adapters.RateLimiter,
        :registry_name,
        registry_table,
        create: false
      )

    {:ok, embedding_table} =
      Supertester.ETSIsolation.create_isolated(:ordered_set, [
        :public,
        {:read_concurrency, true},
        {:write_concurrency, true}
      ])

    {:ok, _} =
      Supertester.ETSIsolation.inject_table(
        PortfolioIndex.Pipelines.Embedding,
        :queue_name,
        embedding_table,
        create: false
      )

    :ok
  end
end
