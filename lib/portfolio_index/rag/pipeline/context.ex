defmodule PortfolioIndex.RAG.Pipeline.Context do
  @moduledoc """
  Context struct that flows through the RAG pipeline, tracking all intermediate results.
  Enables functional composition with the pipe operator.

  ## Usage

      ctx =
        Context.new("What is Elixir?")
        |> QueryProcessor.rewrite()
        |> QueryProcessor.expand()
        |> QueryProcessor.decompose()
        |> Retriever.search()
        |> Reranker.rerank()
        |> Answerer.answer()

      ctx.answer
      # => "Elixir is a functional programming language..."

  ## Fields

  ### Input (set by `new/2`)
  - `:question` - The original question
  - `:opts` - Options passed through the pipeline

  ### Query Processing (populated by query processors)
  - `:rewritten_query` - Conversational input rewritten as clear search query
  - `:expanded_query` - Query expanded with synonyms and related terms
  - `:sub_questions` - Complex question decomposed into simpler parts

  ### Routing (populated by index selector)
  - `:selected_indexes` - List of index names to search
  - `:selection_reasoning` - LLM's reasoning for selection decision

  ### Retrieval (populated by search)
  - `:results` - List of retrieved chunks/documents
  - `:rerank_scores` - Map of chunk ID to rerank score

  ### Generation (populated by answerer)
  - `:answer` - The generated answer
  - `:context_used` - Chunks used to generate the answer

  ### Self-Correction (tracked during answer generation)
  - `:correction_count` - Number of self-corrections performed
  - `:corrections` - List of `{answer, feedback}` tuples

  ### Error Handling
  - `:error` - Error reason if any step fails
  - `:halted?` - Whether pipeline execution was halted
  """

  @type t :: %__MODULE__{
          # Input
          question: String.t() | nil,
          opts: keyword(),

          # Query Processing
          rewritten_query: String.t() | nil,
          expanded_query: String.t() | nil,
          sub_questions: [String.t()],

          # Routing
          selected_indexes: [String.t()],
          selection_reasoning: String.t() | nil,

          # Retrieval
          results: [map()],
          rerank_scores: %{String.t() => float()},

          # Generation
          answer: String.t() | nil,
          context_used: [map()],

          # Self-Correction
          correction_count: non_neg_integer(),
          corrections: [{String.t(), String.t()}],

          # Error Handling
          error: term() | nil,
          halted?: boolean()
        }

  defstruct question: nil,
            opts: [],
            rewritten_query: nil,
            expanded_query: nil,
            sub_questions: [],
            selected_indexes: [],
            selection_reasoning: nil,
            results: [],
            rerank_scores: %{},
            answer: nil,
            context_used: [],
            correction_count: 0,
            corrections: [],
            error: nil,
            halted?: false

  @doc """
  Create a new context with the given question and options.

  ## Parameters

    - `question` - The user's original question
    - `opts` - Pipeline options (passed through to all steps):
      - `:llm` - LLM module or function for query processing
      - `:max_tokens` - Maximum tokens for LLM responses
      - `:temperature` - Sampling temperature

  ## Examples

      Context.new("What is Elixir?")

      Context.new("Compare Elixir and Go", llm: MyLLM, temperature: 0.3)
  """
  @spec new(String.t(), keyword()) :: t()
  def new(question, opts \\ []) when is_binary(question) do
    %__MODULE__{
      question: question,
      opts: opts
    }
  end

  @doc """
  Mark context as halted with an error.

  When halted, subsequent pipeline steps should skip processing
  and return the context unchanged.

  ## Parameters

    - `ctx` - The context to halt
    - `error` - The error reason

  ## Examples

      ctx |> Context.halt(:llm_timeout)
      ctx |> Context.halt({:api_error, "Rate limited"})
  """
  @spec halt(t(), term()) :: t()
  def halt(%__MODULE__{} = ctx, error) do
    %{ctx | error: error, halted?: true}
  end

  @doc """
  Check if context has an error.

  Returns true if either `halted?` is true or `error` is not nil.

  ## Examples

      Context.error?(ctx)
      # => false

      Context.error?(Context.halt(ctx, :error))
      # => true
  """
  @spec error?(t()) :: boolean()
  def error?(%__MODULE__{halted?: true}), do: true
  def error?(%__MODULE__{error: error}) when not is_nil(error), do: true
  def error?(%__MODULE__{}), do: false
end
