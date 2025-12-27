defmodule PortfolioIndex.Adapters.Chunker.RecursiveTest do
  use ExUnit.Case, async: true

  alias PortfolioIndex.Adapters.Chunker.Recursive
  alias PortfolioIndex.Fixtures

  describe "chunk/3" do
    test "chunks plain text" do
      text = String.duplicate("Hello world. ", 100)
      config = %{chunk_size: 100, chunk_overlap: 20}

      assert {:ok, chunks} = Recursive.chunk(text, :plain, config)
      assert length(chunks) > 1

      Enum.each(chunks, fn chunk ->
        assert is_binary(chunk.content)
        assert is_integer(chunk.index)
        assert is_integer(chunk.start_offset)
        assert is_integer(chunk.end_offset)
        assert is_map(chunk.metadata)
      end)
    end

    test "chunks markdown with header awareness" do
      text = """
      # Main Title

      Introduction paragraph here.

      ## Section One

      Content for section one.

      ## Section Two

      Content for section two.
      """

      config = %{chunk_size: 50, chunk_overlap: 10}

      assert {:ok, chunks} = Recursive.chunk(text, :markdown, config)
      assert chunks != []

      # Check that chunks have markdown format in metadata
      Enum.each(chunks, fn chunk ->
        assert chunk.metadata.format == :markdown
      end)
    end

    test "chunks code with function awareness" do
      text = Fixtures.sample_code()
      config = %{chunk_size: 100, chunk_overlap: 20}

      assert {:ok, chunks} = Recursive.chunk(text, :code, config)
      assert chunks != []
    end

    test "returns single chunk for small text" do
      text = "Small text"
      config = %{chunk_size: 1000, chunk_overlap: 100}

      assert {:ok, chunks} = Recursive.chunk(text, :plain, config)
      assert length(chunks) == 1
      assert hd(chunks).content == text
    end

    test "handles empty text" do
      config = %{chunk_size: 100, chunk_overlap: 20}

      assert {:ok, chunks} = Recursive.chunk("", :plain, config)
      assert chunks == [] or (length(chunks) == 1 and hd(chunks).content == "")
    end
  end

  describe "estimate_chunks/2" do
    test "estimates chunk count for text" do
      text = String.duplicate("a", 1000)
      config = %{chunk_size: 100, chunk_overlap: 20}

      estimate = Recursive.estimate_chunks(text, config)
      assert estimate > 1
      assert is_integer(estimate)
    end

    test "returns 1 for small text" do
      text = "Small text"
      config = %{chunk_size: 1000, chunk_overlap: 100}

      assert Recursive.estimate_chunks(text, config) == 1
    end
  end
end
