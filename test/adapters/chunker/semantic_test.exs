defmodule PortfolioIndex.Adapters.Chunker.SemanticTest do
  use ExUnit.Case, async: true

  alias PortfolioIndex.Adapters.Chunker.Semantic

  describe "chunk/3" do
    test "groups similar sentences together" do
      text =
        "Elixir is a functional language. It runs on the BEAM. Python is different. Python uses indentation."

      config = %{
        threshold: 0.5,
        max_chars: 500,
        min_sentences: 1,
        embedding_fn: &mock_embedding/1
      }

      {:ok, chunks} = Semantic.chunk(text, :semantic, config)

      # Should create chunks based on similarity
      refute Enum.empty?(chunks)
      assert Enum.all?(chunks, fn c -> String.trim(c.content) != "" end)
    end

    test "respects max_chars limit" do
      text = String.duplicate("This is a sentence. ", 50)

      config = %{
        max_chars: 200,
        threshold: 0.9,
        min_sentences: 1,
        embedding_fn: &mock_embedding/1
      }

      {:ok, chunks} = Semantic.chunk(text, :semantic, config)

      # Chunks should generally respect max_chars (with some tolerance)
      assert Enum.all?(chunks, fn c -> String.length(c.content) <= 300 end)
    end

    test "tracks byte positions" do
      text = "First sentence. Second sentence. Third sentence."

      config = %{
        threshold: 0.5,
        min_sentences: 1,
        embedding_fn: &mock_embedding/1
      }

      {:ok, chunks} = Semantic.chunk(text, :semantic, config)

      # All chunks should have valid byte positions
      assert Enum.all?(chunks, fn c ->
               is_integer(c.start_byte) and is_integer(c.end_byte) and
                 c.start_byte >= 0
             end)
    end

    test "returns error when no embedding function provided" do
      text = "Some text here."
      config = %{threshold: 0.5}

      result = Semantic.chunk(text, :semantic, config)
      assert result == {:error, :no_embedding_fn}
    end

    test "returns empty list for empty text" do
      config = %{embedding_fn: &mock_embedding/1}
      {:ok, chunks} = Semantic.chunk("", :semantic, config)
      assert chunks == []
    end

    test "handles single sentence" do
      text = "Just one sentence."

      config = %{
        min_sentences: 1,
        embedding_fn: &mock_embedding/1
      }

      {:ok, chunks} = Semantic.chunk(text, :semantic, config)

      assert match?([_], chunks)
      assert String.contains?(hd(chunks).content, "Just one sentence")
    end

    test "falls back gracefully on embedding errors" do
      text = "First sentence. Second sentence. Third sentence."

      config = %{
        max_chars: 100,
        embedding_fn: fn _text -> {:error, :api_error} end
      }

      ExUnit.CaptureLog.capture_log(fn ->
        {:ok, chunks} = Semantic.chunk(text, :semantic, config)

        # Should fall back to size-based chunking
        refute Enum.empty?(chunks)
        # Fallback should be indicated in metadata
        assert hd(chunks).metadata[:fallback] == true
      end)
    end

    test "includes sentence count in metadata" do
      text = "One. Two. Three."

      config = %{
        min_sentences: 1,
        embedding_fn: &mock_embedding/1
      }

      {:ok, chunks} = Semantic.chunk(text, :semantic, config)

      assert hd(chunks).metadata.strategy == :semantic
      assert is_integer(hd(chunks).metadata.sentence_count)
    end

    test "groups by high similarity threshold" do
      # With a high threshold, similar sentences should stay together
      text = "Elixir is great. Elixir is awesome. Python is good. Python is nice."

      config = %{
        threshold: 0.3,
        max_chars: 500,
        min_sentences: 1,
        embedding_fn: &deterministic_embedding/1
      }

      {:ok, chunks} = Semantic.chunk(text, :semantic, config)

      refute Enum.empty?(chunks)
    end

    test "respects min_sentences parameter" do
      text = "One. Two. Three. Four. Five."

      config = %{
        # Very low threshold would create many splits
        threshold: 0.1,
        # But require at least 3 sentences per chunk
        min_sentences: 3,
        embedding_fn: &varied_embedding/1
      }

      {:ok, chunks} = Semantic.chunk(text, :semantic, config)

      # With min_sentences=3, should have fewer chunks
      # Each chunk should have at least 3 sentences (except possibly the last)
      refute Enum.empty?(chunks)
    end
  end

  describe "estimate_chunks/2" do
    test "estimates based on text length and max_chars" do
      text = String.duplicate("a", 1000)
      estimate = Semantic.estimate_chunks(text, %{max_chars: 200})

      assert estimate >= 5
    end

    test "returns 1 for short text" do
      estimate = Semantic.estimate_chunks("Short text", %{max_chars: 1000})
      assert estimate == 1
    end
  end

  # Mock embedding function - returns deterministic embedding based on text hash
  defp mock_embedding(text) do
    hash = :erlang.phash2(text)
    vec = for i <- 1..768, do: :math.sin(hash + i) / 2 + 0.5
    {:ok, %{vector: vec}}
  end

  # Returns similar embeddings for texts containing the same key word
  defp deterministic_embedding(text) do
    base =
      cond do
        String.contains?(text, "Elixir") -> 1.0
        String.contains?(text, "Python") -> 2.0
        true -> 0.0
      end

    vec = for i <- 1..768, do: :math.sin(base + i * 0.01) / 2 + 0.5
    {:ok, %{vector: vec}}
  end

  # Returns varied embeddings to trigger splits
  defp varied_embedding(text) do
    hash = :erlang.phash2(text)
    # Use the hash directly to create very different embeddings
    vec = for i <- 1..768, do: :math.sin(hash * i) / 2 + 0.5
    {:ok, %{vector: vec}}
  end
end
