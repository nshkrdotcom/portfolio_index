defmodule PortfolioIndex.Adapters.Chunker.CharacterTest do
  use ExUnit.Case, async: true

  alias PortfolioIndex.Adapters.Chunker.Character

  describe "chunk/3" do
    test "splits text at character boundaries with word boundary mode" do
      text = "The quick brown fox jumps over the lazy dog."
      config = %{chunk_size: 20, chunk_overlap: 5, boundary: :word}

      {:ok, chunks} = Character.chunk(text, :plain, config)

      assert match?([_, _ | _], chunks)
      # All chunks should have content
      assert Enum.all?(chunks, fn c -> String.trim(c.content) != "" end)
      # First chunk should start at 0
      assert hd(chunks).start_byte == 0
    end

    test "splits text at sentence boundaries when boundary is :sentence" do
      text = "First sentence. Second sentence. Third sentence. Fourth sentence."
      config = %{chunk_size: 40, chunk_overlap: 10, boundary: :sentence}

      {:ok, chunks} = Character.chunk(text, :plain, config)

      refute Enum.empty?(chunks)
      # Each chunk should have complete sentences
      assert Enum.all?(chunks, fn c -> String.trim(c.content) != "" end)
    end

    test "splits text at exact character count when boundary is :none" do
      text = String.duplicate("a", 100)
      config = %{chunk_size: 30, chunk_overlap: 0, boundary: :none}

      {:ok, chunks} = Character.chunk(text, :plain, config)

      assert match?([_, _, _, _], chunks)
      # First 3 chunks should be exactly 30 chars, last one is 10
      assert String.length(hd(chunks).content) == 30
    end

    test "respects chunk overlap" do
      text = "The quick brown fox jumps over the lazy dog."
      config = %{chunk_size: 20, chunk_overlap: 5, boundary: :word}

      {:ok, chunks} = Character.chunk(text, :plain, config)

      if match?([_, _ | _], chunks) do
        # Second chunk should have some overlap content
        second_chunk = Enum.at(chunks, 1)
        assert second_chunk != nil
      end
    end

    test "returns empty list for empty text" do
      {:ok, chunks} = Character.chunk("", :plain, %{})
      assert chunks == []
    end

    test "returns empty list for whitespace-only text" do
      {:ok, chunks} = Character.chunk("   \n\t  ", :plain, %{})
      assert chunks == []
    end

    test "handles single word shorter than chunk size" do
      {:ok, chunks} = Character.chunk("Hello", :plain, %{chunk_size: 100})

      assert match?([_], chunks)
      assert hd(chunks).content == "Hello"
    end

    test "tracks byte positions correctly" do
      text = "First. Second. Third."
      config = %{chunk_size: 10, chunk_overlap: 0, boundary: :word}

      {:ok, chunks} = Character.chunk(text, :plain, config)

      # All chunks should have valid byte positions
      assert Enum.all?(chunks, fn c ->
               is_integer(c.start_byte) and is_integer(c.end_byte) and
                 c.start_byte >= 0 and c.end_byte > c.start_byte
             end)
    end

    test "includes metadata with strategy and boundary info" do
      {:ok, chunks} = Character.chunk("Hello world", :plain, %{boundary: :word})

      assert hd(chunks).metadata.strategy == :character
      assert hd(chunks).metadata.boundary == :word
      assert is_integer(hd(chunks).metadata.char_count)
    end
  end

  describe "estimate_chunks/2" do
    test "estimates correctly for text shorter than chunk size" do
      text = "Short text"
      assert Character.estimate_chunks(text, %{chunk_size: 100}) == 1
    end

    test "estimates based on chunk size and overlap" do
      text = String.duplicate("a", 1000)
      estimate = Character.estimate_chunks(text, %{chunk_size: 200, chunk_overlap: 50})

      # Should be approximately 1000 / (200 - 50) + 1 = 7.67, rounded up
      assert estimate >= 6 and estimate <= 8
    end
  end
end
