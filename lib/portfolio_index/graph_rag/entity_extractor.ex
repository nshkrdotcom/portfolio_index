defmodule PortfolioIndex.GraphRAG.EntityExtractor do
  @moduledoc """
  LLM-based entity and relationship extraction from text.

  Extracts entities and relationships for knowledge graph construction.
  Supports batch extraction with rate limiting and entity resolution
  to deduplicate and merge similar entities.

  ## Example

      {:ok, result} = EntityExtractor.extract(text, llm, [])
      # => %{
      #   entities: [
      #     %{name: "User", type: "Class", description: "..."},
      #     %{name: "authenticate", type: "Function", description: "..."}
      #   ],
      #   relationships: [
      #     %{source: "User", target: "authenticate", type: "CALLS", description: "..."}
      #   ]
      # }
  """

  require Logger

  alias PortfolioIndex.RAG.AdapterResolver

  @extraction_prompt """
  Extract entities and relationships from this text.

  Text:
  <%= text %>

  Instructions:
  1. Identify key entities (functions, modules, classes, concepts, people, organizations)
  2. Identify relationships between entities
  3. Return valid JSON in this exact format:

  {
    "entities": [
      {"name": "EntityName", "type": "EntityType", "description": "Brief description"}
    ],
    "relationships": [
      {"source": "SourceEntity", "target": "TargetEntity", "type": "RELATIONSHIP_TYPE", "description": "Brief description"}
    ]
  }

  Entity types: Module, Class, Function, Variable, Concept, Person, Organization, Other
  Relationship types: CALLS, USES, EXTENDS, IMPLEMENTS, CONTAINS, DEPENDS_ON, RELATED_TO, CREATED_BY

  JSON:
  """

  @type entity :: %{
          name: String.t(),
          type: String.t(),
          description: String.t() | nil
        }

  @type relationship :: %{
          source: String.t(),
          target: String.t(),
          type: String.t(),
          description: String.t() | nil
        }

  @type extraction_result :: %{
          entities: [entity()],
          relationships: [relationship()]
        }

  @doc """
  Extract entities and relationships from a single text.

  ## Options

  - `:llm` - LLM module to use
  - `:llm_opts` - LLM options
  - `:context` - Context map for adapter resolution

  ## Returns

  - `{:ok, %{entities: [...], relationships: [...]}}` on success
  - `{:error, reason}` on failure
  """
  @spec extract(String.t(), keyword()) :: {:ok, extraction_result()} | {:error, term()}
  def extract(text, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)
    {llm, llm_opts} = resolve_llm(opts)

    prompt = build_extraction_prompt(text)
    messages = [%{role: :user, content: prompt}]

    case llm.complete(messages, llm_opts) do
      {:ok, %{content: content}} ->
        case parse_extraction_result(content) do
          {:ok, result} ->
            duration = System.monotonic_time(:millisecond) - start_time

            emit_telemetry(
              :extract,
              %{
                duration_ms: duration,
                entity_count: length(result.entities),
                relationship_count: length(result.relationships)
              },
              %{}
            )

            {:ok, result}

          {:error, reason} ->
            {:error, {:parse_error, reason}}
        end

      {:ok, response} ->
        # Try to extract content from various response formats
        content = extract_content(response)

        case parse_extraction_result(content) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:error, {:parse_error, reason}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Extract entities and relationships from multiple texts in parallel.

  ## Options

  Same as `extract/2` plus:
  - `:max_concurrency` - Max parallel extractions (default: 5)
  - `:rate_limit_ms` - Delay between batches (default: 100)

  ## Returns

  - `{:ok, [extraction_result]}` - List of extraction results
  - `{:error, reason}` on failure
  """
  @spec extract_batch([String.t()], keyword()) :: {:ok, [extraction_result()]} | {:error, term()}
  def extract_batch(texts, opts \\ []) do
    max_concurrency = Keyword.get(opts, :max_concurrency, 5)
    rate_limit_ms = Keyword.get(opts, :rate_limit_ms, 100)

    start_time = System.monotonic_time(:millisecond)

    results =
      texts
      |> Enum.chunk_every(max_concurrency)
      |> Enum.flat_map(fn batch ->
        batch_results =
          batch
          |> Task.async_stream(
            fn text -> extract(text, opts) end,
            timeout: 60_000,
            ordered: true
          )
          |> Enum.map(fn
            {:ok, {:ok, result}} -> {:ok, result}
            {:ok, {:error, reason}} -> {:error, reason}
            {:exit, reason} -> {:error, {:task_exit, reason}}
          end)

        Process.sleep(rate_limit_ms)
        batch_results
      end)

    {successes, failures} =
      Enum.split_with(results, fn
        {:ok, _} -> true
        _ -> false
      end)

    if Enum.any?(failures) do
      Logger.warning("Some entity extractions failed: #{length(failures)} failures")
    end

    extracted = Enum.map(successes, fn {:ok, r} -> r end)
    duration = System.monotonic_time(:millisecond) - start_time

    emit_telemetry(
      :extract_batch,
      %{
        duration_ms: duration,
        success_count: length(extracted),
        failure_count: length(failures)
      },
      %{}
    )

    {:ok, extracted}
  end

  @doc """
  Resolve entities by deduplicating and merging similar entities.

  Uses name similarity to identify potential duplicates and merges
  their properties.

  ## Options

  - `:similarity_threshold` - Name similarity threshold for merging (default: 0.85)
  - `:case_sensitive` - Whether to use case-sensitive matching (default: false)

  ## Returns

  - `{:ok, resolved_entities}` - Deduplicated entity list
  """
  @spec resolve_entities([entity()], keyword()) :: {:ok, [entity()]}
  def resolve_entities(entities, opts \\ []) do
    threshold = Keyword.get(opts, :similarity_threshold, 0.85)
    case_sensitive = Keyword.get(opts, :case_sensitive, false)

    resolved =
      entities
      |> Enum.reduce([], fn entity, acc ->
        case find_similar(entity, acc, threshold, case_sensitive) do
          nil ->
            [entity | acc]

          existing ->
            merged = merge_entities(existing, entity)
            replace_entity(acc, existing, merged)
        end
      end)
      |> Enum.reverse()

    {:ok, resolved}
  end

  @doc """
  Merge multiple extraction results into one.

  Combines entities and relationships from multiple extractions,
  optionally resolving duplicates.

  ## Options

  - `:resolve` - Whether to resolve entity duplicates (default: true)
  - `:similarity_threshold` - Threshold for entity resolution (default: 0.85)
  """
  @spec merge_results([extraction_result()], keyword()) :: {:ok, extraction_result()}
  def merge_results(results, opts \\ []) do
    resolve = Keyword.get(opts, :resolve, true)

    all_entities = Enum.flat_map(results, & &1.entities)
    all_relationships = Enum.flat_map(results, & &1.relationships)

    entities =
      if resolve do
        {:ok, resolved} = resolve_entities(all_entities, opts)
        resolved
      else
        all_entities
      end

    relationships = deduplicate_relationships(all_relationships)

    {:ok, %{entities: entities, relationships: relationships}}
  end

  # Private functions

  @spec resolve_llm(keyword()) :: {module(), keyword()}
  defp resolve_llm(opts) do
    context = Keyword.get(opts, :context, %{})
    default_llm = PortfolioIndex.Adapters.LLM.Gemini
    AdapterResolver.resolve(context, :llm, default_llm)
  end

  @spec build_extraction_prompt(String.t()) :: String.t()
  defp build_extraction_prompt(text) do
    String.replace(@extraction_prompt, "<%= text %>", text)
  end

  @spec parse_extraction_result(String.t()) :: {:ok, extraction_result()} | {:error, term()}
  defp parse_extraction_result(content) do
    # Try to find JSON in the response
    case extract_json(content) do
      {:ok, json_str} ->
        case Jason.decode(json_str) do
          {:ok, %{"entities" => entities, "relationships" => relationships}} ->
            {:ok,
             %{
               entities: normalize_entities(entities),
               relationships: normalize_relationships(relationships)
             }}

          {:ok, %{}} ->
            {:ok, %{entities: [], relationships: []}}

          {:error, reason} ->
            {:error, {:json_decode, reason}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec extract_json(String.t()) :: {:ok, String.t()} | {:error, term()}
  defp extract_json(content) do
    # Try to find JSON object in the content
    case Regex.run(~r/\{[\s\S]*\}/, content) do
      [json] -> {:ok, json}
      nil -> {:error, :no_json_found}
    end
  end

  @spec normalize_entities([map()]) :: [entity()]
  defp normalize_entities(entities) when is_list(entities) do
    Enum.map(entities, fn entity ->
      %{
        name: entity["name"] || "",
        type: entity["type"] || "Other",
        description: entity["description"]
      }
    end)
    |> Enum.reject(fn e -> e.name == "" end)
  end

  defp normalize_entities(_), do: []

  @spec normalize_relationships([map()]) :: [relationship()]
  defp normalize_relationships(relationships) when is_list(relationships) do
    Enum.map(relationships, fn rel ->
      %{
        source: rel["source"] || "",
        target: rel["target"] || "",
        type: rel["type"] || "RELATED_TO",
        description: rel["description"]
      }
    end)
    |> Enum.reject(fn r -> r.source == "" or r.target == "" end)
  end

  defp normalize_relationships(_), do: []

  @spec find_similar(entity(), [entity()], float(), boolean()) :: entity() | nil
  defp find_similar(entity, entities, threshold, case_sensitive) do
    Enum.find(entities, fn existing ->
      similarity = name_similarity(entity.name, existing.name, case_sensitive)
      similarity >= threshold
    end)
  end

  @spec name_similarity(String.t(), String.t(), boolean()) :: float()
  defp name_similarity(name1, name2, case_sensitive) do
    n1 = if case_sensitive, do: name1, else: String.downcase(name1)
    n2 = if case_sensitive, do: name2, else: String.downcase(name2)

    if n1 == n2 do
      1.0
    else
      # Simple Jaccard similarity on characters
      chars1 = String.graphemes(n1) |> MapSet.new()
      chars2 = String.graphemes(n2) |> MapSet.new()

      intersection = MapSet.intersection(chars1, chars2) |> MapSet.size()
      union = MapSet.union(chars1, chars2) |> MapSet.size()

      if union == 0, do: 0.0, else: intersection / union
    end
  end

  @spec merge_entities(entity(), entity()) :: entity()
  defp merge_entities(existing, new) do
    %{
      name: existing.name,
      type: existing.type,
      description: merge_descriptions(existing.description, new.description)
    }
  end

  @spec merge_descriptions(String.t() | nil, String.t() | nil) :: String.t() | nil
  defp merge_descriptions(nil, new), do: new
  defp merge_descriptions(existing, nil), do: existing

  defp merge_descriptions(existing, new) do
    if String.length(new) > String.length(existing), do: new, else: existing
  end

  @spec replace_entity([entity()], entity(), entity()) :: [entity()]
  defp replace_entity(entities, old, new) do
    Enum.map(entities, fn e ->
      if e.name == old.name, do: new, else: e
    end)
  end

  @spec deduplicate_relationships([relationship()]) :: [relationship()]
  defp deduplicate_relationships(relationships) do
    relationships
    |> Enum.uniq_by(fn r ->
      {String.downcase(r.source), String.downcase(r.target), String.downcase(r.type)}
    end)
  end

  @spec extract_content(map()) :: String.t()
  defp extract_content(%{content: content}) when is_binary(content), do: content
  defp extract_content(%{"content" => content}) when is_binary(content), do: content
  defp extract_content(_), do: ""

  @spec emit_telemetry(atom(), map(), map()) :: :ok
  defp emit_telemetry(event, measurements, metadata) do
    :telemetry.execute(
      [:portfolio_index, :graph_rag, :entity_extractor, event],
      measurements,
      metadata
    )
  end
end
