defmodule PortfolioIndex.Adapters.CollectionSelector.RuleBased do
  @moduledoc """
  Rule-based collection selector using keyword matching.
  Useful when LLM routing is not needed or for deterministic behavior.

  ## Configuration

      rules = [
        %{
          collection: "api_docs",
          keywords: ["api", "endpoint", "request", "response"],
          boost: 2.0
        },
        %{
          collection: "tutorials",
          keywords: ["how to", "guide", "tutorial", "example"],
          boost: 1.5
        }
      ]

      RuleBased.select(query, collections, rules: rules)

  ## Usage

      collections = [
        %{name: "api_docs", description: "API reference"},
        %{name: "tutorials", description: "Getting started guides"}
      ]

      opts = [
        rules: rules,
        max_collections: 2
      ]

      {:ok, result} = RuleBased.select("How do I use the API?", collections, opts)
      result.selected
      # => ["api_docs", "tutorials"]

  ## Scoring

  Each collection is scored by:
  1. Counting keyword matches in the query
  2. Multiplying by the boost factor
  3. Collections with score > 0 are selected
  4. Results are ordered by score (highest first)
  """

  @behaviour PortfolioCore.Ports.CollectionSelector

  @impl true
  @spec select(String.t(), [map()], keyword()) ::
          {:ok, PortfolioCore.Ports.CollectionSelector.selection_result()} | {:error, term()}
  def select(query, available_collections, opts \\ [])

  def select(_query, [], _opts) do
    {:ok, %{selected: [], reasoning: nil, confidence: nil}}
  end

  def select(query, available_collections, opts) do
    rules = Keyword.get(opts, :rules, [])
    max_collections = Keyword.get(opts, :max_collections, 3)

    collection_names = Enum.map(available_collections, & &1.name)

    if Enum.empty?(rules) do
      # No rules defined, return all collections as fallback
      {:ok, %{selected: collection_names, reasoning: "No routing rules defined", confidence: nil}}
    else
      scores = score_query(query, rules)

      # Filter to collections that exist and have positive scores
      valid_scores =
        scores
        |> Enum.filter(fn {name, score} -> name in collection_names and score > 0 end)
        |> Enum.sort_by(fn {_, score} -> score end, :desc)
        |> Enum.take(max_collections)

      selected =
        if Enum.empty?(valid_scores) do
          # No matches, fallback to all collections
          collection_names
        else
          Enum.map(valid_scores, fn {name, _} -> name end)
        end

      reasoning = build_reasoning(valid_scores)

      {:ok, %{selected: selected, reasoning: reasoning, confidence: nil}}
    end
  end

  @doc """
  Score a query against rules.

  Returns a list of `{collection_name, score}` tuples where score
  is `match_count * boost`.

  ## Examples

      rules = [
        %{collection: "docs", keywords: ["api", "guide"], boost: 1.5}
      ]

      score_query("api guide example", rules)
      # => [{"docs", 3.0}]  # 2 matches * 1.5 boost
  """
  @spec score_query(String.t(), [map()]) :: [{String.t(), float()}]
  def score_query(query, rules) do
    query_lower = String.downcase(query)

    Enum.map(rules, fn rule ->
      collection = rule.collection
      keywords = rule[:keywords] || []
      boost = rule[:boost] || 1.0

      match_count =
        Enum.count(keywords, fn keyword ->
          String.contains?(query_lower, String.downcase(keyword))
        end)

      score = match_count * boost
      {collection, score}
    end)
  end

  # Private functions

  @spec build_reasoning([{String.t(), float()}]) :: String.t() | nil
  defp build_reasoning([]), do: nil

  defp build_reasoning(scores) do
    matched =
      scores
      |> Enum.map(fn {name, score} -> "#{name} (score: #{Float.round(score, 2)})" end)
      |> Enum.join(", ")

    "Selected based on keyword matches: #{matched}"
  end
end
