defmodule PortfolioIndex.Maintenance do
  @moduledoc """
  Production maintenance utilities for document and embedding management.
  Provides re-embedding, diagnostics, and batch operations.

  These functions are designed to be callable from production environments
  where mix tasks are not available (e.g., releases).

  ## Usage in Production

      # Remote IEx
      iex> PortfolioIndex.Maintenance.reembed(MyApp.Repo)

      # Release command
      bin/my_app eval "PortfolioIndex.Maintenance.reembed(MyApp.Repo)"

  ## Progress Tracking

  All long-running operations support an `:on_progress` callback:

      PortfolioIndex.Maintenance.reembed(repo,
        on_progress: fn event ->
          IO.puts("Progress: \#{event.current}/\#{event.total}")
        end
      )

  See `PortfolioIndex.Maintenance.Progress` for built-in progress reporters.
  """

  import Ecto.Query

  alias PortfolioIndex.Maintenance.Progress
  alias PortfolioIndex.Schemas.{Chunk, Collection, Document}
  alias PortfolioIndex.Schemas.Queries

  @type reembed_result :: %{
          total: non_neg_integer(),
          processed: non_neg_integer(),
          failed: non_neg_integer(),
          errors: [%{chunk_id: String.t(), error: term()}]
        }

  @type diagnostics_result :: %{
          collections: non_neg_integer(),
          documents: non_neg_integer(),
          chunks: non_neg_integer(),
          chunks_without_embedding: non_neg_integer(),
          failed_documents: non_neg_integer(),
          storage_bytes: non_neg_integer() | nil
        }

  @doc """
  Re-embed all chunks or a filtered subset.

  ## Options

  - `:collection` - Only re-embed chunks in this collection (by name)
  - `:document_id` - Only re-embed chunks for this document
  - `:batch_size` - Number of chunks per batch (default 100)
  - `:embedder` - Embedder module to use (default from config)
  - `:on_progress` - Callback function for progress updates

  ## Examples

      # Re-embed all chunks
      Maintenance.reembed(Repo)

      # Re-embed with progress callback
      Maintenance.reembed(Repo,
        batch_size: 50,
        on_progress: Progress.cli_reporter()
      )

      # Re-embed specific collection
      Maintenance.reembed(Repo, collection: "docs")
  """
  @spec reembed(Ecto.Repo.t(), keyword()) :: {:ok, reembed_result()} | {:error, term()}
  def reembed(repo, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, 100)
    progress_fn = Keyword.get(opts, :on_progress)
    embedder = Keyword.get(opts, :embedder, default_embedder())
    collection_name = Keyword.get(opts, :collection)
    document_id = Keyword.get(opts, :document_id)

    # Build the query based on filters
    query = build_chunk_query(repo, collection_name, document_id)

    # Count total chunks to process
    total = repo.aggregate(query, :count, :id)

    if total == 0 do
      {:ok, %{total: 0, processed: 0, failed: 0, errors: []}}
    else
      do_reembed(repo, query, embedder, batch_size, progress_fn, total)
    end
  end

  @doc """
  Get system diagnostics including counts and storage usage.

  Returns comprehensive statistics about the current state of the system.

  ## Examples

      {:ok, diagnostics} = Maintenance.diagnostics(Repo)
      # => %{
      #   collections: 5,
      #   documents: 100,
      #   chunks: 500,
      #   chunks_without_embedding: 10,
      #   failed_documents: 3,
      #   storage_bytes: nil
      # }
  """
  @spec diagnostics(Ecto.Repo.t()) :: {:ok, diagnostics_result()}
  def diagnostics(repo) do
    collections_count = repo.aggregate(Collection, :count, :id)
    documents_count = repo.aggregate(Document, :count, :id)
    chunks_count = repo.aggregate(Chunk, :count, :id)

    chunks_without_embedding = Queries.count_chunks_without_embedding(repo)

    failed_documents_count =
      Document
      |> where([d], d.status == :failed)
      |> repo.aggregate(:count, :id)

    {:ok,
     %{
       collections: collections_count,
       documents: documents_count,
       chunks: chunks_count,
       chunks_without_embedding: chunks_without_embedding,
       failed_documents: failed_documents_count,
       storage_bytes: nil
     }}
  end

  @doc """
  Retry failed document processing.

  Resets failed documents to pending status so they can be reprocessed.

  ## Options

  - `:limit` - Max documents to retry (default all)
  - `:on_progress` - Callback for progress updates

  ## Examples

      {:ok, result} = Maintenance.retry_failed(Repo)
      # => %{total: 5, processed: 5, failed: 0}

      {:ok, result} = Maintenance.retry_failed(Repo, limit: 10)
  """
  @spec retry_failed(Ecto.Repo.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def retry_failed(repo, opts \\ []) do
    limit = Keyword.get(opts, :limit)
    progress_fn = Keyword.get(opts, :on_progress)

    failed_docs = Queries.get_failed_documents(repo, limit: limit || 10_000)
    total = length(failed_docs)

    if total == 0 do
      {:ok, %{total: 0, processed: 0, failed: 0}}
    else
      processed =
        failed_docs
        |> Enum.with_index(1)
        |> Enum.reduce(0, fn {doc, index}, acc ->
          Progress.report(progress_fn, :retry_failed, index, total)

          case reset_document(repo, doc) do
            {:ok, _} -> acc + 1
            {:error, _} -> acc
          end
        end)

      {:ok, %{total: total, processed: processed, failed: total - processed}}
    end
  end

  @doc """
  Clean up soft-deleted documents and their chunks.

  Permanently removes documents with `:deleted` status and all associated chunks.

  ## Options

  - `:before` - Only cleanup documents deleted before this datetime

  ## Examples

      {:ok, count} = Maintenance.cleanup_deleted(Repo)
      # => {:ok, 10}
  """
  @spec cleanup_deleted(Ecto.Repo.t(), keyword()) :: {:ok, non_neg_integer()}
  def cleanup_deleted(repo, opts \\ []) do
    before_time = Keyword.get(opts, :before)

    query =
      Document
      |> where([d], d.status == :deleted)

    query =
      if before_time do
        where(query, [d], d.updated_at < ^before_time)
      else
        query
      end

    deleted_docs = repo.all(query)
    count = length(deleted_docs)

    # Delete chunks first (foreign key constraint)
    Enum.each(deleted_docs, fn doc ->
      Chunk
      |> where([c], c.document_id == ^doc.id)
      |> repo.delete_all()

      repo.delete(doc)
    end)

    {:ok, count}
  end

  @doc """
  Verify embedding consistency (detect dimension mismatches).

  Checks all chunks to ensure embeddings have consistent dimensions.

  ## Examples

      {:ok, result} = Maintenance.verify_embeddings(Repo)
      # => %{
      #   total_chunks: 500,
      #   consistent: true,
      #   dimensions: %{384 => 500}
      # }
  """
  @spec verify_embeddings(Ecto.Repo.t()) :: {:ok, map()} | {:error, term()}
  def verify_embeddings(repo) do
    # Get chunks with embeddings
    chunks =
      Chunk
      |> where([c], not is_nil(c.embedding))
      |> select([c], %{id: c.id, embedding: c.embedding})
      |> repo.all()

    total = length(chunks)

    if total == 0 do
      {:ok, %{total_chunks: 0, consistent: true, dimensions: %{}}}
    else
      # Count dimensions
      dimension_counts =
        Enum.reduce(chunks, %{}, fn chunk, acc ->
          dims = embedding_dimensions(chunk.embedding)
          Map.update(acc, dims, 1, &(&1 + 1))
        end)

      consistent = map_size(dimension_counts) <= 1

      {:ok,
       %{
         total_chunks: total,
         consistent: consistent,
         dimensions: dimension_counts
       }}
    end
  end

  # Private functions

  defp build_chunk_query(repo, collection_name, document_id) do
    query = from(c in Chunk)

    query =
      cond do
        document_id ->
          where(query, [c], c.document_id == ^document_id)

        collection_name ->
          collection = Queries.get_collection_by_name(repo, collection_name)

          if collection do
            query
            |> join(:inner, [c], d in Document, on: c.document_id == d.id)
            |> where([c, d], d.collection_id == ^collection.id)
          else
            # No matching collection, return empty result
            where(query, [c], false)
          end

        true ->
          query
      end

    query
  end

  defp do_reembed(repo, query, embedder, batch_size, progress_fn, total) do
    chunks =
      query
      |> order_by([c], c.id)
      |> repo.all()

    {processed, failed, errors} =
      chunks
      |> Enum.chunk_every(batch_size)
      |> Enum.with_index(1)
      |> Enum.reduce({0, 0, []}, fn {batch, batch_index}, {proc_acc, fail_acc, err_acc} ->
        current = min(batch_index * batch_size, total)
        Progress.report(progress_fn, :reembed, current, total)

        batch_results =
          Enum.map(batch, fn chunk ->
            reembed_chunk(repo, embedder, chunk)
          end)

        batch_processed = Enum.count(batch_results, &match?({:ok, _}, &1))
        batch_failed = Enum.count(batch_results, &match?({:error, _, _}, &1))

        batch_errors =
          batch_results
          |> Enum.filter(&match?({:error, _, _}, &1))
          |> Enum.map(fn {:error, chunk_id, error} -> %{chunk_id: chunk_id, error: error} end)

        {proc_acc + batch_processed, fail_acc + batch_failed, err_acc ++ batch_errors}
      end)

    {:ok, %{total: total, processed: processed, failed: failed, errors: errors}}
  end

  defp reembed_chunk(repo, embedder, chunk) do
    case embedder.embed(chunk.content, []) do
      {:ok, %{vector: vector}} ->
        changeset = Chunk.embedding_changeset(chunk, vector)

        case repo.update(changeset) do
          {:ok, _updated} -> {:ok, chunk.id}
          {:error, reason} -> {:error, chunk.id, reason}
        end

      {:error, reason} ->
        {:error, chunk.id, reason}
    end
  end

  defp reset_document(repo, document) do
    document
    |> Document.status_changeset(:pending)
    |> repo.update()
  end

  defp default_embedder do
    Application.get_env(:portfolio_index, :embedder, PortfolioIndex.Adapters.Embedder.Gemini)
  end

  defp embedding_dimensions(embedding) when is_list(embedding), do: length(embedding)

  defp embedding_dimensions(%Pgvector{} = pgvector) do
    pgvector
    |> Pgvector.to_list()
    |> length()
  end

  defp embedding_dimensions(_), do: 0
end
