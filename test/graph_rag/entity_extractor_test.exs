# Mock LLM that returns valid extraction JSON
defmodule PortfolioIndex.Test.MockLLM do
  def complete(_messages, _opts) do
    {:ok,
     %{
       content: """
       {
         "entities": [
           {"name": "User", "type": "Class", "description": "A user entity"},
           {"name": "authenticate", "type": "Function", "description": "Auth function"}
         ],
         "relationships": [
           {"source": "User", "target": "authenticate", "type": "CALLS", "description": "User calls auth"}
         ]
       }
       """
     }}
  end
end

# Mock LLM that returns empty result
defmodule PortfolioIndex.Test.EmptyLLM do
  def complete(_messages, _opts) do
    {:ok,
     %{
       content: """
       {
         "entities": [],
         "relationships": []
       }
       """
     }}
  end
end

defmodule PortfolioIndex.GraphRAG.EntityExtractorTest do
  use PortfolioIndex.SupertesterCase, async: true

  alias PortfolioIndex.GraphRAG.EntityExtractor
  alias PortfolioIndex.Test.EmptyLLM
  alias PortfolioIndex.Test.MockLLM

  describe "extract/2" do
    test "extracts entities and relationships from text" do
      text = "The User class calls the authenticate function."
      opts = [context: %{adapters: %{llm: MockLLM}}]

      {:ok, result} = EntityExtractor.extract(text, opts)

      assert is_list(result.entities)
      assert is_list(result.relationships)
    end

    test "handles empty extraction result" do
      opts = [context: %{adapters: %{llm: EmptyLLM}}]

      {:ok, result} = EntityExtractor.extract("random text", opts)

      assert result.entities == []
      assert result.relationships == []
    end
  end

  describe "resolve_entities/2" do
    test "merges duplicate entities by name" do
      entities = [
        %{name: "User", type: "Class", description: "First description"},
        %{name: "user", type: "Class", description: "Second longer description here"},
        %{name: "Admin", type: "Class", description: nil}
      ]

      {:ok, resolved} = EntityExtractor.resolve_entities(entities, [])

      assert length(resolved) == 2
      user = Enum.find(resolved, &(&1.name == "User"))
      assert user.description == "Second longer description here"
    end

    test "respects similarity threshold" do
      entities = [
        %{name: "authenticate", type: "Function", description: nil},
        %{name: "authentication", type: "Function", description: nil}
      ]

      {:ok, resolved_high} = EntityExtractor.resolve_entities(entities, similarity_threshold: 0.9)
      {:ok, resolved_low} = EntityExtractor.resolve_entities(entities, similarity_threshold: 0.5)

      # High threshold: should not merge
      assert length(resolved_high) == 2
      # Low threshold: should merge (similar names)
      assert length(resolved_low) == 1
    end

    test "handles case sensitivity option" do
      entities = [
        %{name: "User", type: "Class", description: nil},
        %{name: "USER", type: "Class", description: nil}
      ]

      {:ok, case_insensitive} = EntityExtractor.resolve_entities(entities, case_sensitive: false)
      {:ok, case_sensitive} = EntityExtractor.resolve_entities(entities, case_sensitive: true)

      assert length(case_insensitive) == 1
      assert length(case_sensitive) == 2
    end
  end

  describe "merge_results/2" do
    test "combines entities and relationships from multiple results" do
      results = [
        %{
          entities: [%{name: "A", type: "Class", description: nil}],
          relationships: [%{source: "A", target: "B", type: "CALLS", description: nil}]
        },
        %{
          entities: [%{name: "B", type: "Function", description: nil}],
          relationships: [%{source: "B", target: "C", type: "USES", description: nil}]
        }
      ]

      {:ok, merged} = EntityExtractor.merge_results(results, [])

      assert length(merged.entities) == 2
      assert length(merged.relationships) == 2
    end

    test "deduplicates relationships" do
      results = [
        %{
          entities: [],
          relationships: [%{source: "A", target: "B", type: "CALLS", description: nil}]
        },
        %{
          entities: [],
          relationships: [%{source: "a", target: "b", type: "calls", description: nil}]
        }
      ]

      {:ok, merged} = EntityExtractor.merge_results(results, resolve: false)

      # Should deduplicate case-insensitively
      assert length(merged.relationships) == 1
    end

    test "optionally skips entity resolution" do
      results = [
        %{
          entities: [%{name: "User", type: "Class", description: nil}],
          relationships: []
        },
        %{
          entities: [%{name: "user", type: "Class", description: nil}],
          relationships: []
        }
      ]

      {:ok, no_resolve} = EntityExtractor.merge_results(results, resolve: false)
      {:ok, with_resolve} = EntityExtractor.merge_results(results, resolve: true)

      assert length(no_resolve.entities) == 2
      assert length(with_resolve.entities) == 1
    end
  end
end
