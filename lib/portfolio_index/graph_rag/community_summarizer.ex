defmodule PortfolioIndex.GraphRAG.CommunitySummarizer do
  @moduledoc """
  LLM-based summarization of graph communities.

  Generates concise summaries describing community themes for use in global search.
  Each summary captures:
  - What the community represents
  - Key themes or concepts
  - How members relate to each other

  ## Example

      {:ok, summary} = CommunitySummarizer.summarize(
        community,
        graph_store,
        "my_graph",
        llm,
        []
      )
      # => %{
      #   community_id: "community_0",
      #   summary: "This community focuses on user authentication...",
      #   embedding: [0.1, 0.2, ...]
      # }
  """

  require Logger

  alias PortfolioIndex.RAG.AdapterResolver

  @summary_prompt_template """
  Summarize this community of related entities from a knowledge graph.

  Community members:
  <%= members_text %>

  Relationships between members:
  <%= relationships_text %>

  Provide a concise summary (2-3 sentences) describing:
  1. What this community represents
  2. Key themes or concepts
  3. How members relate to each other

  Summary:
  """

  @type community :: %{
          id: String.t(),
          members: [String.t()],
          summary: String.t() | nil,
          embedding: [float()] | nil
        }

  @doc """
  Summarize a single community.

  ## Parameters

  - `community` - Community map with id and member list
  - `graph_store` - Graph store module
  - `graph_id` - Graph identifier
  - `opts` - Options including:
    - `:llm` - LLM module to use
    - `:llm_opts` - LLM options
    - `:embedder` - Embedder module for summary embedding
    - `:embedder_opts` - Embedder options
    - `:generate_embedding` - Whether to generate embedding (default: true)

  ## Returns

  - `{:ok, community}` - Community with summary and optionally embedding
  - `{:error, reason}` on failure
  """
  @spec summarize(map(), module(), String.t(), keyword()) ::
          {:ok, community()} | {:error, term()}
  def summarize(community, graph_store, graph_id, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)

    with {:ok, members_data} <- get_member_details(community.members, graph_store, graph_id),
         {:ok, relationships} <-
           get_internal_relationships(community.members, graph_store, graph_id),
         {:ok, summary_text} <- generate_summary(members_data, relationships, opts),
         {:ok, embedding} <- maybe_generate_embedding(summary_text, opts) do
      duration = System.monotonic_time(:millisecond) - start_time

      emit_telemetry(:summarize, %{duration_ms: duration}, %{
        community_id: community.id,
        member_count: length(community.members)
      })

      {:ok,
       %{
         id: community.id,
         members: community.members,
         summary: summary_text,
         embedding: embedding
       }}
    end
  end

  @doc """
  Summarize multiple communities in parallel.

  ## Options

  Same as `summarize/4` plus:
  - `:max_concurrency` - Max parallel summarizations (default: 5)
  - `:rate_limit_ms` - Delay between batches (default: 100)

  ## Returns

  - `{:ok, communities}` - List of summarized communities
  - `{:error, reason}` on failure
  """
  @spec summarize_all([map()], module(), String.t(), keyword()) ::
          {:ok, [community()]} | {:error, term()}
  def summarize_all(communities, graph_store, graph_id, opts \\ []) do
    max_concurrency = Keyword.get(opts, :max_concurrency, 5)
    rate_limit_ms = Keyword.get(opts, :rate_limit_ms, 100)

    start_time = System.monotonic_time(:millisecond)

    results =
      communities
      |> Enum.chunk_every(max_concurrency)
      |> Enum.flat_map(fn batch ->
        batch_results =
          batch
          |> Task.async_stream(
            fn community ->
              summarize(community, graph_store, graph_id, opts)
            end,
            timeout: 60_000,
            ordered: true
          )
          |> Enum.map(fn
            {:ok, {:ok, result}} -> {:ok, result}
            {:ok, {:error, reason}} -> {:error, reason}
            {:exit, reason} -> {:error, {:task_exit, reason}}
          end)

        # Rate limiting between batches
        Process.sleep(rate_limit_ms)
        batch_results
      end)

    # Separate successes and failures
    {successes, failures} =
      Enum.split_with(results, fn
        {:ok, _} -> true
        _ -> false
      end)

    if Enum.any?(failures) do
      Logger.warning("Some community summarizations failed: #{length(failures)} failures")
    end

    summarized = Enum.map(successes, fn {:ok, c} -> c end)
    duration = System.monotonic_time(:millisecond) - start_time

    emit_telemetry(
      :summarize_all,
      %{
        duration_ms: duration,
        success_count: length(summarized),
        failure_count: length(failures)
      },
      %{graph_id: graph_id}
    )

    {:ok, summarized}
  end

  @doc """
  Build a community map from detection results.

  Converts the community detector output format to the format expected
  by the summarizer.
  """
  @spec build_communities(%{String.t() => [String.t()]}) :: [map()]
  def build_communities(detection_result) do
    Enum.map(detection_result, fn {community_id, member_ids} ->
      %{id: community_id, members: member_ids}
    end)
  end

  # Private functions

  @spec get_member_details([String.t()], module(), String.t()) ::
          {:ok, [map()]} | {:error, term()}
  defp get_member_details(member_ids, graph_store, graph_id) do
    if Enum.empty?(member_ids) do
      {:ok, []}
    else
      # Query for member details
      query = """
      MATCH (n {_graph_id: $graph_id})
      WHERE n.id IN $member_ids AND NOT n:_Graph
      RETURN n.id as id, n.name as name, n.description as description, labels(n) as labels
      """

      case graph_store.query(graph_id, query, %{graph_id: graph_id, member_ids: member_ids}) do
        {:ok, %{records: records}} ->
          members =
            Enum.map(records, fn record ->
              %{
                id: record["id"] || record[:id],
                name: record["name"] || record[:name] || record["id"] || record[:id],
                description: record["description"] || record[:description],
                labels: record["labels"] || record[:labels] || []
              }
            end)

          {:ok, members}

        {:ok, []} ->
          {:ok, []}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @spec get_internal_relationships([String.t()], module(), String.t()) ::
          {:ok, [map()]} | {:error, term()}
  defp get_internal_relationships(member_ids, graph_store, graph_id) do
    if length(member_ids) < 2 do
      {:ok, []}
    else
      query = """
      MATCH (a {_graph_id: $graph_id})-[r]->(b {_graph_id: $graph_id})
      WHERE a.id IN $member_ids AND b.id IN $member_ids AND NOT a:_Graph AND NOT b:_Graph
      RETURN a.name as source_name, type(r) as rel_type, b.name as target_name, r.description as description
      LIMIT 50
      """

      case graph_store.query(graph_id, query, %{graph_id: graph_id, member_ids: member_ids}) do
        {:ok, %{records: records}} ->
          relationships =
            Enum.map(records, fn record ->
              %{
                source: record["source_name"] || record[:source_name],
                type: record["rel_type"] || record[:rel_type],
                target: record["target_name"] || record[:target_name],
                description: record["description"] || record[:description]
              }
            end)

          {:ok, relationships}

        {:ok, []} ->
          {:ok, []}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @spec generate_summary([map()], [map()], keyword()) :: {:ok, String.t()} | {:error, term()}
  defp generate_summary(members, relationships, opts) do
    {llm, llm_opts} = resolve_llm(opts)

    members_text = format_members(members)
    relationships_text = format_relationships(relationships)

    prompt = build_prompt(members_text, relationships_text)

    messages = [%{role: :user, content: prompt}]

    case llm.complete(messages, llm_opts) do
      {:ok, %{content: summary}} when is_binary(summary) ->
        {:ok, String.trim(summary)}

      {:ok, response} ->
        # Try to extract content from various response formats
        content = extract_content(response)
        {:ok, String.trim(content)}

      {:error, reason} ->
        Logger.warning("Community summary generation failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @spec maybe_generate_embedding(String.t(), keyword()) ::
          {:ok, [float()] | nil} | {:error, term()}
  defp maybe_generate_embedding(text, opts) do
    generate_embedding = Keyword.get(opts, :generate_embedding, true)

    if generate_embedding do
      {embedder, embedder_opts} = resolve_embedder(opts)

      case embedder.embed(text, embedder_opts) do
        {:ok, %{vector: vector}} ->
          {:ok, vector}

        {:ok, vector} when is_list(vector) ->
          {:ok, vector}

        {:error, reason} ->
          Logger.warning("Failed to generate community embedding: #{inspect(reason)}")
          # Don't fail the whole operation
          {:ok, nil}
      end
    else
      {:ok, nil}
    end
  end

  @spec resolve_llm(keyword()) :: {module(), keyword()}
  defp resolve_llm(opts) do
    context = Keyword.get(opts, :context, %{})
    default_llm = PortfolioIndex.Adapters.LLM.Gemini
    AdapterResolver.resolve(context, :llm, default_llm)
  end

  @spec resolve_embedder(keyword()) :: {module(), keyword()}
  defp resolve_embedder(opts) do
    context = Keyword.get(opts, :context, %{})
    default_embedder = PortfolioIndex.Adapters.Embedder.Gemini
    AdapterResolver.resolve(context, :embedder, default_embedder)
  end

  @spec format_members([map()]) :: String.t()
  defp format_members(members) do
    Enum.map_join(members, "\n", fn member ->
      labels = Enum.join(member.labels || [], ", ")
      desc = if member.description, do: ": #{member.description}", else: ""
      "- [#{labels}] #{member.name}#{desc}"
    end)
  end

  @spec format_relationships([map()]) :: String.t()
  defp format_relationships([]), do: "No internal relationships found."

  defp format_relationships(relationships) do
    Enum.map_join(relationships, "\n", fn rel ->
      desc = if rel.description, do: " (#{rel.description})", else: ""
      "- #{rel.source} --[#{rel.type}]--> #{rel.target}#{desc}"
    end)
  end

  @spec build_prompt(String.t(), String.t()) :: String.t()
  defp build_prompt(members_text, relationships_text) do
    @summary_prompt_template
    |> String.replace("<%= members_text %>", members_text)
    |> String.replace("<%= relationships_text %>", relationships_text)
  end

  @spec extract_content(map()) :: String.t()
  defp extract_content(%{content: content}) when is_binary(content), do: content
  defp extract_content(%{"content" => content}) when is_binary(content), do: content
  defp extract_content(_), do: ""

  @spec emit_telemetry(atom(), map(), map()) :: :ok
  defp emit_telemetry(event, measurements, metadata) do
    :telemetry.execute(
      [:portfolio_index, :graph_rag, :community_summarizer, event],
      measurements,
      metadata
    )
  end
end
