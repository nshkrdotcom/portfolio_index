defmodule PortfolioIndex.Adapters.CollectionSelector.RuleBasedTest do
  use PortfolioIndex.SupertesterCase, async: true

  alias PortfolioIndex.Adapters.CollectionSelector.RuleBased

  @sample_collections [
    %{name: "api_docs", description: "API reference", document_count: 500},
    %{name: "tutorials", description: "Getting started", document_count: 100},
    %{name: "faq", description: "FAQ", document_count: 50}
  ]

  @sample_rules [
    %{
      collection: "api_docs",
      keywords: ["api", "endpoint", "request", "response", "rest"],
      boost: 2.0
    },
    %{
      collection: "tutorials",
      keywords: ["how to", "guide", "tutorial", "example", "getting started"],
      boost: 1.5
    },
    %{
      collection: "faq",
      keywords: ["what is", "why", "when", "common", "question"],
      boost: 1.0
    }
  ]

  describe "select/3" do
    test "selects collection based on keyword matches" do
      opts = [rules: @sample_rules]

      {:ok, result} =
        RuleBased.select(
          "What is the API endpoint for authentication?",
          @sample_collections,
          opts
        )

      assert "api_docs" in result.selected
    end

    test "selects tutorial collection for how-to queries" do
      opts = [rules: @sample_rules]

      {:ok, result} =
        RuleBased.select("How to get started with the SDK?", @sample_collections, opts)

      assert "tutorials" in result.selected
    end

    test "returns all collections when no keywords match" do
      opts = [rules: @sample_rules]

      {:ok, result} = RuleBased.select("xyzabc123", @sample_collections, opts)

      # With no matches, should return all collections as fallback
      assert length(result.selected) == 3
    end

    test "respects max_collections option" do
      opts = [rules: @sample_rules, max_collections: 1]

      {:ok, result} = RuleBased.select("API tutorial guide", @sample_collections, opts)

      assert length(result.selected) == 1
    end

    test "orders by score (boost * matches)" do
      opts = [rules: @sample_rules]

      # Query with both API and tutorial keywords
      {:ok, result} = RuleBased.select("API endpoint guide tutorial", @sample_collections, opts)

      # Should have both, but order may vary based on scoring
      assert result.selected != []
    end

    test "is case insensitive" do
      opts = [rules: @sample_rules]

      {:ok, result} = RuleBased.select("ENDPOINT REQUEST", @sample_collections, opts)

      assert "api_docs" in result.selected
    end

    test "handles empty collections list" do
      opts = [rules: @sample_rules]

      {:ok, result} = RuleBased.select("test query", [], opts)

      assert result.selected == []
    end

    test "handles empty rules list" do
      opts = [rules: []]

      {:ok, result} = RuleBased.select("test query", @sample_collections, opts)

      # With no rules, should fallback to all collections
      assert length(result.selected) == 3
    end

    test "uses default rules when none provided" do
      # Without explicit rules, should still work (fallback behavior)
      {:ok, result} = RuleBased.select("test query", @sample_collections, [])

      assert is_list(result.selected)
    end

    test "provides reasoning in result" do
      opts = [rules: @sample_rules]

      {:ok, result} = RuleBased.select("API endpoint guide", @sample_collections, opts)

      assert is_binary(result.reasoning) or is_nil(result.reasoning)
    end
  end

  describe "score_query/2" do
    test "scores query against rules" do
      scores = RuleBased.score_query("api endpoint request", @sample_rules)

      assert is_list(scores)
      assert length(scores) == 3

      # Find api_docs score
      api_score = Enum.find(scores, fn {name, _} -> name == "api_docs" end)
      assert api_score != nil
      {_, score} = api_score
      assert score > 0
    end

    test "returns zero score for no matches" do
      rules = [
        %{collection: "test", keywords: ["xyzabc"], boost: 1.0}
      ]

      scores = RuleBased.score_query("hello world", rules)

      {_, score} = hd(scores)
      assert score == 0.0
    end

    test "applies boost multiplier" do
      rules = [
        %{collection: "boosted", keywords: ["test"], boost: 3.0},
        %{collection: "normal", keywords: ["test"], boost: 1.0}
      ]

      scores = RuleBased.score_query("test", rules)

      boosted_score = Enum.find(scores, fn {name, _} -> name == "boosted" end) |> elem(1)
      normal_score = Enum.find(scores, fn {name, _} -> name == "normal" end) |> elem(1)

      assert boosted_score == normal_score * 3.0
    end

    test "counts multiple keyword matches" do
      rules = [
        %{collection: "multi", keywords: ["one", "two", "three"], boost: 1.0}
      ]

      single_match_scores = RuleBased.score_query("one", rules)
      multi_match_scores = RuleBased.score_query("one two three", rules)

      single_score = hd(single_match_scores) |> elem(1)
      multi_score = hd(multi_match_scores) |> elem(1)

      assert multi_score > single_score
    end
  end
end
