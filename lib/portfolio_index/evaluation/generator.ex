defmodule PortfolioIndex.Evaluation.Generator do
  @moduledoc """
  LLM-powered synthetic test case generation.
  Creates questions from document chunks for evaluation.

  ## Overview

  The Generator creates test cases by:
  1. Sampling chunks from the database
  2. Sending each chunk to an LLM with a prompt asking for a question
  3. Creating test cases with the question linked to the source chunk

  ## Usage

      # Generate test cases with a custom LLM
      {:ok, test_cases} = Generator.generate(repo, [
        sample_size: 50,
        collection: "docs",
        llm: fn prompt -> MyLLM.complete(prompt) end
      ])

      # Generate a single question
      {:ok, question} = Generator.generate_question(chunk, [
        llm: fn prompt -> MyLLM.complete(prompt) end
      ])
  """

  import Ecto.Query

  alias PortfolioIndex.Schemas.{Chunk, TestCase}

  @default_prompt """
  Based on the following text chunk, generate a specific question that could be answered using this content.
  The question should be clear, searchable, and directly related to the information in the chunk.
  Return ONLY the question, nothing else.

  Text chunk:
  {chunk_text}
  """

  @type generate_opts :: [
          sample_size: pos_integer(),
          collection: String.t() | nil,
          prompt: String.t() | (String.t() -> String.t()),
          llm: (String.t() -> {:ok, String.t()} | {:error, term()})
        ]

  @doc """
  Generate synthetic test cases from chunks.

  Samples chunks from the database and uses an LLM to generate
  questions for each chunk. Returns a list of unsaved TestCase structs.

  ## Options
    - `:sample_size` - Number of chunks to sample (default: 10)
    - `:collection` - Filter chunks by collection name
    - `:prompt` - Custom prompt template with {chunk_text} placeholder
    - `:llm` - LLM function for question generation (required)

  ## Returns
    - `{:ok, [TestCase.t()]}` - List of generated test case structs
    - `{:error, term()}` - If generation fails

  ## Example

      {:ok, test_cases} = Generator.generate(MyApp.Repo, [
        sample_size: 20,
        llm: fn prompt -> Anthropic.complete(prompt) end
      ])
  """
  @spec generate(Ecto.Repo.t(), generate_opts()) :: {:ok, [TestCase.t()]} | {:error, term()}
  def generate(repo, opts \\ []) do
    sample_size = Keyword.get(opts, :sample_size, 10)
    collection = Keyword.get(opts, :collection)
    llm = Keyword.get(opts, :llm)
    prompt = Keyword.get(opts, :prompt, @default_prompt)

    if is_nil(llm) do
      {:error, :llm_required}
    else
      chunks = sample_chunks(repo, sample_size, collection)

      test_cases =
        chunks
        |> Enum.map(fn chunk ->
          case generate_question(chunk, llm: llm, prompt: prompt) do
            {:ok, question} ->
              create_test_case_from_chunk(chunk, question)

            {:error, _} ->
              nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      {:ok, test_cases}
    end
  end

  @doc """
  Generate a question for a single chunk.

  ## Options
    - `:llm` - Function that takes a prompt and returns `{:ok, response}` (required)
    - `:prompt` - Custom prompt template with {chunk_text} placeholder

  ## Returns
    - `{:ok, question}` - Generated question string
    - `{:error, reason}` - If LLM call fails
  """
  @spec generate_question(Chunk.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def generate_question(chunk, opts) do
    llm = Keyword.fetch!(opts, :llm)
    prompt_template = Keyword.get(opts, :prompt, @default_prompt)

    prompt = build_prompt(chunk, prompt_template)

    case llm.(prompt) do
      {:ok, question} when is_binary(question) ->
        {:ok, String.trim(question)}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Returns the default prompt template.

  The template includes the `{chunk_text}` placeholder which is
  replaced with the chunk content when generating questions.
  """
  @spec default_prompt() :: String.t()
  def default_prompt, do: @default_prompt

  @doc """
  Build the prompt by substituting chunk content into the template.

  ## Parameters
    - `chunk` - The chunk to generate a question for
    - `prompt_template` - Template string with {chunk_text} placeholder
  """
  @spec build_prompt(Chunk.t(), String.t()) :: String.t()
  def build_prompt(chunk, prompt_template) do
    String.replace(prompt_template, "{chunk_text}", chunk.content)
  end

  @doc """
  Create a TestCase struct from a chunk and generated question.

  The test case is marked as `:synthetic` and includes metadata
  pointing to the source chunk.

  ## Parameters
    - `chunk` - The source chunk
    - `question` - The generated question

  ## Returns
    - `TestCase.t()` struct (not persisted)
  """
  @spec create_test_case_from_chunk(Chunk.t(), String.t()) :: TestCase.t()
  def create_test_case_from_chunk(chunk, question) do
    %TestCase{
      question: question,
      source: :synthetic,
      metadata: %{source_chunk_id: chunk.id}
    }
  end

  # Private helpers

  defp sample_chunks(repo, sample_size, collection) do
    query =
      from(c in Chunk,
        order_by: fragment("RANDOM()"),
        limit: ^sample_size
      )

    query =
      if collection do
        from([c] in query,
          join: d in assoc(c, :document),
          join: col in assoc(d, :collection),
          where: col.name == ^collection
        )
      else
        query
      end

    repo.all(query)
  end
end
