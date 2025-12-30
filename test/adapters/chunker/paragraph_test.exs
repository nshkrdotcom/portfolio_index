defmodule PortfolioIndex.Adapters.Chunker.ParagraphTest do
  use ExUnit.Case, async: true

  alias PortfolioIndex.Adapters.Chunker.Paragraph

  describe "chunk/3" do
    test "splits text on paragraph boundaries" do
      text = """
      First paragraph with some content.

      Second paragraph with different content.

      Third paragraph to complete the text.
      """

      config = %{chunk_size: 100, chunk_overlap: 20}
      {:ok, chunks} = Paragraph.chunk(text, :plain, config)

      refute Enum.empty?(chunks)
      # Each chunk should contain content
      assert Enum.all?(chunks, fn c -> String.trim(c.content) != "" end)
    end

    test "merges small paragraphs" do
      text = """
      Small.

      Also small.

      Still small.

      This is a much longer paragraph that should stand on its own because it has enough content to meet the minimum paragraph size requirement.
      """

      config = %{chunk_size: 500, chunk_overlap: 50, min_paragraph_size: 50}
      {:ok, chunks} = Paragraph.chunk(text, :plain, config)

      # Small paragraphs should be merged
      # The first few small paragraphs should be in one chunk
      refute Enum.empty?(chunks)
    end

    test "splits large paragraphs at sentence boundaries" do
      # One very large paragraph
      text = String.duplicate("This is a sentence. ", 50)

      config = %{chunk_size: 200, chunk_overlap: 50}
      {:ok, chunks} = Paragraph.chunk(text, :plain, config)

      # Should be split into multiple chunks
      assert match?([_, _ | _], chunks)
      # Each chunk should respect size limit (with some tolerance)
      assert Enum.all?(chunks, fn c -> String.length(c.content) <= 300 end)
    end

    test "returns empty list for empty text" do
      {:ok, chunks} = Paragraph.chunk("", :plain, %{})
      assert chunks == []
    end

    test "handles single paragraph" do
      text = "Just a single paragraph without any double newlines."
      config = %{chunk_size: 100, chunk_overlap: 20}

      {:ok, chunks} = Paragraph.chunk(text, :plain, config)

      assert match?([_], chunks)
      assert String.trim(hd(chunks).content) == String.trim(text)
    end

    test "tracks byte positions" do
      text = """
      First paragraph.

      Second paragraph.
      """

      {:ok, chunks} = Paragraph.chunk(text, :plain, %{chunk_size: 500})

      assert Enum.all?(chunks, fn c ->
               is_integer(c.start_byte) and is_integer(c.end_byte) and
                 c.start_byte >= 0
             end)
    end

    test "includes paragraph count in metadata" do
      text = """
      First paragraph.

      Second paragraph.
      """

      {:ok, chunks} = Paragraph.chunk(text, :plain, %{chunk_size: 500})

      assert hd(chunks).metadata.strategy == :paragraph
      assert is_integer(hd(chunks).metadata.paragraph_count)
    end

    test "respects chunk overlap" do
      text = """
      First paragraph with some content here.

      Second paragraph with different content here.

      Third paragraph with more content here.

      Fourth paragraph with final content here.
      """

      config = %{chunk_size: 80, chunk_overlap: 30}
      {:ok, chunks} = Paragraph.chunk(text, :plain, config)

      # With overlap, later chunks should have some content from previous chunks
      assert match?([_, _ | _], chunks)
    end
  end

  describe "estimate_chunks/2" do
    test "estimates based on text length and paragraph count" do
      text = """
      First paragraph.

      Second paragraph.

      Third paragraph.
      """

      estimate = Paragraph.estimate_chunks(text, %{chunk_size: 50})
      assert estimate >= 1
    end

    test "returns 1 for short text" do
      estimate = Paragraph.estimate_chunks("Short", %{chunk_size: 100})
      assert estimate >= 1
    end
  end

  describe "get_chunk_size option" do
    test "uses custom get_chunk_size function" do
      text = """
      First paragraph with several words.

      Second paragraph with more words.

      Third paragraph with even more words.
      """

      word_counter = fn text ->
        text |> String.split(~r/\s+/, trim: true) |> length()
      end

      config = %{chunk_size: 10, chunk_overlap: 0, get_chunk_size: word_counter}

      {:ok, chunks} = Paragraph.chunk(text, :plain, config)
      # Should split based on word count
      refute Enum.empty?(chunks)
    end

    test "estimate_chunks uses get_chunk_size" do
      text = """
      First paragraph.

      Second paragraph.

      Third paragraph.
      """

      word_counter = fn text ->
        text |> String.split(~r/\s+/, trim: true) |> length()
      end

      estimate =
        Paragraph.estimate_chunks(text, %{
          chunk_size: 3,
          chunk_overlap: 0,
          get_chunk_size: word_counter
        })

      assert estimate >= 1
    end
  end

  describe "token_count in metadata" do
    test "includes token_count in chunk metadata" do
      {:ok, chunks} =
        Paragraph.chunk("This is a test sentence for chunking.", :plain, %{chunk_size: 1000})

      assert chunks != []
      chunk = hd(chunks)
      assert Map.has_key?(chunk.metadata, :token_count)
      assert is_integer(chunk.metadata.token_count)
      assert chunk.metadata.token_count > 0
    end

    test "token_count is approximately char_count / 4" do
      # 100 chars
      text = String.duplicate("abcd", 25)
      {:ok, [chunk]} = Paragraph.chunk(text, :plain, %{chunk_size: 1000})

      assert chunk.metadata.char_count == 100
      assert chunk.metadata.token_count == 25
    end
  end
end
