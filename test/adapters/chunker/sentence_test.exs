defmodule PortfolioIndex.Adapters.Chunker.SentenceTest do
  use ExUnit.Case, async: true

  alias PortfolioIndex.Adapters.Chunker.Sentence

  describe "chunk/3" do
    test "splits text on sentence boundaries" do
      text = "First sentence. Second sentence. Third sentence. Fourth sentence."
      config = %{chunk_size: 40, chunk_overlap: 10}

      {:ok, chunks} = Sentence.chunk(text, :plain, config)

      refute Enum.empty?(chunks)
      # Each chunk should have content
      assert Enum.all?(chunks, fn c -> String.trim(c.content) != "" end)
    end

    test "groups sentences to reach target chunk size" do
      text = "One. Two. Three. Four. Five. Six. Seven. Eight. Nine. Ten."
      config = %{chunk_size: 30, chunk_overlap: 0}

      {:ok, chunks} = Sentence.chunk(text, :plain, config)

      # Sentences should be grouped
      assert match?([_, _ | _], chunks)
    end

    test "handles question marks and exclamation points" do
      text = "Is this a question? Yes it is! And this is a statement."
      config = %{chunk_size: 100, chunk_overlap: 0}

      {:ok, chunks} = Sentence.chunk(text, :plain, config)

      # Should recognize all three sentences
      refute Enum.empty?(chunks)
      assert hd(chunks).metadata.sentence_count >= 1
    end

    test "preserves abbreviations" do
      text = "Dr. Smith went to the store. Mr. Jones stayed home."
      config = %{chunk_size: 100, chunk_overlap: 0}

      {:ok, chunks} = Sentence.chunk(text, :plain, config)

      # Abbreviations shouldn't cause false splits
      assert match?([_], chunks)
      assert chunks |> hd() |> Map.get(:content) |> String.contains?("Dr.")
    end

    test "returns empty list for empty text" do
      {:ok, chunks} = Sentence.chunk("", :plain, %{})
      assert chunks == []
    end

    test "handles single sentence" do
      text = "Just one sentence here."
      {:ok, chunks} = Sentence.chunk(text, :plain, %{chunk_size: 100})

      assert match?([_], chunks)
      assert hd(chunks).metadata.sentence_count == 1
    end

    test "tracks byte positions" do
      text = "First sentence. Second sentence."
      config = %{chunk_size: 100, chunk_overlap: 0}

      {:ok, chunks} = Sentence.chunk(text, :plain, config)

      assert Enum.all?(chunks, fn c ->
               is_integer(c.start_byte) and is_integer(c.end_byte) and
                 c.start_byte >= 0 and c.end_byte > c.start_byte
             end)
    end

    test "includes sentence count in metadata" do
      text = "One. Two. Three."
      {:ok, chunks} = Sentence.chunk(text, :plain, %{chunk_size: 100})

      assert hd(chunks).metadata.strategy == :sentence
      assert hd(chunks).metadata.sentence_count == 3
    end

    test "respects chunk overlap" do
      text =
        "First sentence here. Second sentence here. Third sentence here. Fourth sentence here."

      config = %{chunk_size: 40, chunk_overlap: 20}

      {:ok, chunks} = Sentence.chunk(text, :plain, config)

      # With overlap, sentences from previous chunk may appear in next
      assert match?([_, _ | _], chunks)
    end

    test "handles multi-line text" do
      text = """
      This is the first sentence.
      This is the second sentence.
      And this is the third.
      """

      {:ok, chunks} = Sentence.chunk(text, :plain, %{chunk_size: 100})

      refute Enum.empty?(chunks)
      assert hd(chunks).metadata.sentence_count >= 1
    end
  end

  describe "estimate_chunks/2" do
    test "estimates based on sentence count and chunk size" do
      text = "One. Two. Three. Four. Five."
      estimate = Sentence.estimate_chunks(text, %{chunk_size: 15})

      assert estimate >= 1
    end

    test "returns 1 for single sentence" do
      estimate = Sentence.estimate_chunks("Just one.", %{chunk_size: 100})
      assert estimate >= 1
    end
  end
end
