# Mock LLM for collection selector testing
defmodule PortfolioIndex.Test.CollectionSelectorMockLLM do
  def complete(_messages, _opts) do
    {:ok,
     %{
       content: """
       {"collections": ["api_docs", "tutorials"], "reasoning": "Query is about API usage and getting started"}
       """
     }}
  end
end

defmodule PortfolioIndex.Test.CollectionSelectorFailingLLM do
  def complete(_messages, _opts) do
    {:error, :api_timeout}
  end
end

defmodule PortfolioIndex.Test.CollectionSelectorInvalidJsonLLM do
  def complete(_messages, _opts) do
    {:ok, %{content: "Just pick api_docs, it seems relevant"}}
  end
end

defmodule PortfolioIndex.Test.CollectionSelectorSingleCollectionLLM do
  def complete(_messages, _opts) do
    {:ok,
     %{
       content: """
       {"collections": ["faq"], "reasoning": "This is a frequently asked question"}
       """
     }}
  end
end

defmodule PortfolioIndex.Adapters.CollectionSelector.LLMTest do
  use ExUnit.Case, async: true

  alias PortfolioIndex.Adapters.CollectionSelector.LLM
  alias PortfolioIndex.Test.CollectionSelectorFailingLLM
  alias PortfolioIndex.Test.CollectionSelectorInvalidJsonLLM
  alias PortfolioIndex.Test.CollectionSelectorMockLLM
  alias PortfolioIndex.Test.CollectionSelectorSingleCollectionLLM

  @sample_collections [
    %{name: "api_docs", description: "REST API reference documentation", document_count: 500},
    %{
      name: "tutorials",
      description: "Getting started guides and tutorials",
      document_count: 100
    },
    %{name: "faq", description: "Frequently asked questions", document_count: 50}
  ]

  describe "select/3" do
    test "selects collections based on LLM response" do
      opts = [context: %{adapters: %{llm: CollectionSelectorMockLLM}}]

      {:ok, result} = LLM.select("How do I authenticate with the API?", @sample_collections, opts)

      assert is_list(result.selected)
      assert "api_docs" in result.selected
      assert "tutorials" in result.selected
      assert result.reasoning == "Query is about API usage and getting started"
    end

    test "returns single collection when LLM selects one" do
      opts = [context: %{adapters: %{llm: CollectionSelectorSingleCollectionLLM}}]

      {:ok, result} = LLM.select("What are your support hours?", @sample_collections, opts)

      assert result.selected == ["faq"]
      assert result.reasoning == "This is a frequently asked question"
    end

    test "returns error on LLM failure" do
      opts = [context: %{adapters: %{llm: CollectionSelectorFailingLLM}}]

      assert {:error, :api_timeout} =
               LLM.select("Test query", @sample_collections, opts)
    end

    test "falls back to all collections on invalid JSON" do
      opts = [context: %{adapters: %{llm: CollectionSelectorInvalidJsonLLM}}]

      {:ok, result} = LLM.select("Test query", @sample_collections, opts)

      # Should fall back to all collection names
      assert length(result.selected) == 3
      assert "api_docs" in result.selected
      assert "tutorials" in result.selected
      assert "faq" in result.selected
      assert result.reasoning == nil
    end

    test "handles empty collections list" do
      opts = [context: %{adapters: %{llm: CollectionSelectorMockLLM}}]

      {:ok, result} = LLM.select("Test query", [], opts)

      assert result.selected == []
    end

    test "respects max_collections option" do
      opts = [
        context: %{adapters: %{llm: CollectionSelectorMockLLM}},
        max_collections: 1
      ]

      {:ok, result} = LLM.select("Test query", @sample_collections, opts)

      # LLM returned 2 collections, but we limit to 1
      assert length(result.selected) <= 1
    end

    test "handles collections with nil descriptions" do
      collections = [
        %{name: "docs", description: nil, document_count: 10},
        %{name: "api", description: "", document_count: nil}
      ]

      opts = [context: %{adapters: %{llm: CollectionSelectorMockLLM}}]

      # Should not crash with nil descriptions
      assert {:ok, _result} = LLM.select("Test query", collections, opts)
    end
  end

  describe "format_collections/1" do
    test "formats collections with descriptions" do
      formatted = LLM.format_collections(@sample_collections)

      assert formatted =~ "api_docs: REST API reference documentation"
      assert formatted =~ "tutorials: Getting started guides and tutorials"
      assert formatted =~ "faq: Frequently asked questions"
    end

    test "formats collections without descriptions" do
      collections = [
        %{name: "docs", description: nil, document_count: 10}
      ]

      formatted = LLM.format_collections(collections)

      assert formatted =~ "docs"
      refute formatted =~ ":"
    end

    test "includes document count when available" do
      formatted = LLM.format_collections(@sample_collections)

      assert formatted =~ "500 docs" or formatted =~ "500"
    end
  end
end
