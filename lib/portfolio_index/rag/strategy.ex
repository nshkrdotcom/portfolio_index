defmodule PortfolioIndex.RAG.Strategy do
  @moduledoc """
  Behaviour for RAG retrieval strategies.

  Strategies define how to retrieve and process information
  for Retrieval-Augmented Generation.

  ## Implementing a Strategy

      defmodule MyStrategy do
        @behaviour PortfolioIndex.RAG.Strategy

        @impl true
        def retrieve(query, context, opts) do
          # Implementation
        end

        @impl true
        def name, do: :my_strategy

        @impl true
        def required_adapters, do: [:vector_store, :embedder]
      end

  ## Built-in Strategies

  - `PortfolioIndex.RAG.Strategies.Hybrid` - Vector + keyword search with RRF
  - `PortfolioIndex.RAG.Strategies.SelfRAG` - Self-critique and refinement
  """

  @type query :: String.t()
  @type context :: map()
  @type opts :: keyword()

  @type retrieved_item :: %{
          content: String.t(),
          score: float(),
          source: String.t(),
          metadata: map()
        }

  @type result :: %{
          items: [retrieved_item()],
          query: query(),
          answer: String.t() | nil,
          strategy: atom(),
          timing_ms: non_neg_integer(),
          tokens_used: non_neg_integer()
        }

  @doc """
  Retrieve relevant content for a query.
  """
  @callback retrieve(query(), context(), opts()) :: {:ok, result()} | {:error, term()}

  @doc """
  Get the name of this strategy.
  """
  @callback name() :: atom()

  @doc """
  Get the list of required adapters for this strategy.
  """
  @callback required_adapters() :: [atom()]

  @optional_callbacks [required_adapters: 0]
end
