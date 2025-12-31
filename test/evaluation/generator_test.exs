defmodule PortfolioIndex.Evaluation.GeneratorTest do
  use ExUnit.Case, async: true

  alias PortfolioIndex.Evaluation.Generator
  alias PortfolioIndex.Schemas.{Chunk, TestCase}

  describe "generate_question/2" do
    test "generates question using LLM" do
      chunk = %Chunk{
        id: Ecto.UUID.generate(),
        content: "Elixir is a functional programming language built on the Erlang VM.",
        chunk_index: 0
      }

      mock_llm = fn _prompt ->
        {:ok, "What programming paradigm does Elixir follow?"}
      end

      assert {:ok, question} = Generator.generate_question(chunk, llm: mock_llm)
      assert is_binary(question)
      assert question == "What programming paradigm does Elixir follow?"
    end

    test "handles LLM error" do
      chunk = %Chunk{
        id: Ecto.UUID.generate(),
        content: "Some content",
        chunk_index: 0
      }

      mock_llm = fn _prompt ->
        {:error, :rate_limited}
      end

      assert {:error, :rate_limited} = Generator.generate_question(chunk, llm: mock_llm)
    end

    test "uses custom prompt" do
      chunk = %Chunk{
        id: Ecto.UUID.generate(),
        content: "Test content",
        chunk_index: 0
      }

      custom_prompt = "Create a trivia question about: {chunk_text}"

      mock_llm = fn prompt ->
        send(self(), {:captured_prompt, prompt})
        {:ok, "A trivia question?"}
      end

      {:ok, _} = Generator.generate_question(chunk, llm: mock_llm, prompt: custom_prompt)

      assert_receive {:captured_prompt, prompt}
      assert String.contains?(prompt, "Create a trivia question about:")
      assert String.contains?(prompt, "Test content")
    end

    test "trims whitespace from generated question" do
      chunk = %Chunk{
        id: Ecto.UUID.generate(),
        content: "Content",
        chunk_index: 0
      }

      mock_llm = fn _prompt ->
        {:ok, "  What is this?  \n"}
      end

      {:ok, question} = Generator.generate_question(chunk, llm: mock_llm)
      assert question == "What is this?"
    end
  end

  describe "default_prompt/0" do
    test "returns prompt with {chunk_text} placeholder" do
      prompt = Generator.default_prompt()
      assert is_binary(prompt)
      assert String.contains?(prompt, "{chunk_text}")
    end
  end

  describe "build_prompt/2" do
    test "substitutes chunk text into prompt template" do
      template = "Generate a question for: {chunk_text}"
      chunk = %Chunk{content: "Hello World", chunk_index: 0}

      result = Generator.build_prompt(chunk, template)
      assert result == "Generate a question for: Hello World"
    end
  end

  describe "create_test_case_from_chunk/2" do
    test "creates test case struct from chunk and question" do
      chunk = %Chunk{
        id: Ecto.UUID.generate(),
        content: "Content",
        chunk_index: 0
      }

      question = "What does this explain?"

      result = Generator.create_test_case_from_chunk(chunk, question)

      assert %TestCase{} = result
      assert result.question == question
      assert result.source == :synthetic
      assert result.metadata.source_chunk_id == chunk.id
    end
  end
end
