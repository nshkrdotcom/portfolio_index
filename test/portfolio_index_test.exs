defmodule PortfolioIndexTest do
  use PortfolioIndex.SupertesterCase, async: false

  describe "version/0" do
    test "returns version string" do
      version = PortfolioIndex.version()
      assert is_binary(version)
    end
  end

  describe "adapter/1" do
    test "returns a module for vector store" do
      adapter = PortfolioIndex.adapter(:vector_store)
      assert is_atom(adapter)
    end

    test "returns a module for graph store" do
      adapter = PortfolioIndex.adapter(:graph_store)
      assert is_atom(adapter)
    end

    test "returns a module for embedder" do
      adapter = PortfolioIndex.adapter(:embedder)
      assert is_atom(adapter)
    end

    test "returns a module for llm" do
      adapter = PortfolioIndex.adapter(:llm)
      assert is_atom(adapter)
    end

    test "returns a module for chunker" do
      adapter = PortfolioIndex.adapter(:chunker)
      assert is_atom(adapter)
    end

    test "returns a module for document store" do
      adapter = PortfolioIndex.adapter(:document_store)
      assert is_atom(adapter)
    end
  end
end
