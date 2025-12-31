defmodule PortfolioIndex.Adapters.QueryRewriter.LLM do
  @moduledoc """
  LLM-based query rewriter that cleans conversational input.
  Removes greetings, filler words, and extracts the core question.

  Implements the `PortfolioCore.Ports.QueryRewriter` behaviour.

  ## Usage

      # With AdapterResolver context
      opts = [context: %{adapters: %{llm: MyLLM}}]
      {:ok, result} = LLM.rewrite("Hey, what is Elixir?", opts)
      result.rewritten
      # => "what is Elixir"

      # With custom prompt
      custom_prompt = fn query -> "Clean this: \#{query}" end
      {:ok, result} = LLM.rewrite(query, prompt: custom_prompt, context: ctx)

  ## Prompt Customization

  The default prompt removes:
  - Greetings (Hey, Hi, Hello)
  - Politeness markers (Can you, Could you, Please)
  - Filler phrases (I was wondering, I want to know)

  Provide a `:prompt` option as a function `(query -> prompt_string)` to customize.
  """

  @behaviour PortfolioCore.Ports.QueryRewriter

  require Logger

  alias PortfolioIndex.RAG.AdapterResolver

  @default_prompt """
  You are a search query optimizer. Your task is to rewrite conversational user input into a clear, standalone search query.

  Rules:
  - Remove conversational filler (greetings, "I want to", "Can you tell me", "Hey", etc.)
  - Extract the core question or topic
  - Keep ALL entity names, technical terms, and specific details
  - Keep the query concise but complete
  - If the input is already a clear query, return it unchanged
  - Return ONLY the rewritten query, nothing else

  Examples:
  Input: "Hey, so I was wondering if you could help me understand how Phoenix LiveView works"
  Rewritten: "how Phoenix LiveView works"

  Input: "I want to compare Elixir and Go lang for building web services"
  Rewritten: "compare Elixir and Go for building web services"

  Input: "Can you tell me about the advantages of using GenServer?"
  Rewritten: "advantages of using GenServer"

  Input: "What is pattern matching?"
  Rewritten: "What is pattern matching?"

  Now rewrite this input:
  "{query}"
  """

  @impl true
  @spec rewrite(String.t(), keyword()) ::
          {:ok, PortfolioCore.Ports.QueryRewriter.rewrite_result()} | {:error, term()}
  def rewrite(query, opts \\ []) do
    {llm, llm_opts} = resolve_llm(opts)
    prompt_fn = Keyword.get(opts, :prompt)

    prompt = build_prompt(query, prompt_fn)
    messages = [%{role: :user, content: prompt}]

    case llm.complete(messages, llm_opts) do
      {:ok, %{content: rewritten}} ->
        rewritten_clean = String.trim(rewritten)

        # Fall back to original if LLM returns empty
        final_rewritten = if rewritten_clean == "", do: query, else: rewritten_clean

        emit_telemetry(:rewrite, %{original_length: String.length(query)}, %{})

        {:ok,
         %{
           original: query,
           rewritten: final_rewritten,
           changes_made: detect_changes(query, final_rewritten)
         }}

      {:error, reason} = error ->
        Logger.warning("Query rewriting failed: #{inspect(reason)}")
        error
    end
  end

  @spec resolve_llm(keyword()) :: {module(), keyword()}
  defp resolve_llm(opts) do
    context = Keyword.get(opts, :context, %{})
    default_llm = PortfolioIndex.Adapters.LLM.Gemini
    AdapterResolver.resolve(context, :llm, default_llm)
  end

  @spec build_prompt(String.t(), (String.t() -> String.t()) | nil) :: String.t()
  defp build_prompt(query, nil) do
    String.replace(@default_prompt, "{query}", query)
  end

  defp build_prompt(query, prompt_fn) when is_function(prompt_fn, 1) do
    prompt_fn.(query)
  end

  @spec detect_changes(String.t(), String.t()) :: [String.t()]
  defp detect_changes(original, rewritten) do
    changes = []

    # Detect common changes
    changes =
      if String.length(rewritten) < String.length(original) do
        ["shortened query" | changes]
      else
        changes
      end

    changes =
      if String.match?(original, ~r/^(hey|hi|hello)/i) and
           not String.match?(rewritten, ~r/^(hey|hi|hello)/i) do
        ["removed greeting" | changes]
      else
        changes
      end

    changes =
      if String.match?(original, ~r/(can you|could you|please)/i) and
           not String.match?(rewritten, ~r/(can you|could you|please)/i) do
        ["removed politeness markers" | changes]
      else
        changes
      end

    Enum.reverse(changes)
  end

  @spec emit_telemetry(atom(), map(), map()) :: :ok
  defp emit_telemetry(event, measurements, metadata) do
    :telemetry.execute(
      [:portfolio_index, :query_rewriter, :llm, event],
      measurements,
      metadata
    )
  end
end
