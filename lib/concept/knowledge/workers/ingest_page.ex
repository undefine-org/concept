defmodule Concept.Knowledge.Workers.IngestPage do
  @moduledoc """
  Oban worker that ingests a content *source* (a page or a message) + its blocks
  into Arcana for RAG search.

  The job is keyed on a `{source_type, source_id}` pair (PLAN-010 §45): the
  ingest pipeline is no longer page-only. A `page` source lists the page's
  blocks; a `message` source lists that message's blocks (a conversation turn).
  Both flow through the same `BlockChunker`, so conversation content becomes
  searchable knowledge with no separate pipeline.

  Legacy `page_id` job args are still accepted (in-flight jobs / older callers).
  """
  use Oban.Worker, queue: :knowledge_ingest, max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"op" => "upsert"} = args}) do
    {source_type, source_id} = source_ref(args)
    workspace_id = args["workspace_id"]
    ingest(source_type, source_id, workspace_id)
  end

  def perform(%Oban.Job{args: %{"op" => "delete"} = args}) do
    {source_type, source_id} = source_ref(args)
    # Arcana 2.0 doesn't expose delete_by_source_id; deferring to FEAT-035 Reactor.
    Logger.warning("Delete for #{source_type}:#{source_id} not yet implemented; skipping")
    :ok
  end

  def perform(%Oban.Job{args: args}) do
    Logger.error("Invalid IngestPage job args: #{inspect(args)}")
    {:error, :invalid_args}
  end

  # New contract: {source_type, source_id}; legacy contract: page_id.
  defp source_ref(%{"source_type" => t, "source_id" => id}), do: {t, id}
  defp source_ref(%{"page_id" => page_id}), do: {"page", page_id}

  # Dispatch ingest through the Concept.Containable registry: each container
  # type describes itself as a knowledge source via `ingest_descriptor/2`, so
  # this worker needs no per-type clause. Adding a new container = implement the
  # callback + register it; zero edits here.
  defp ingest(source_type, source_id, workspace_id) when is_binary(source_type) do
    case container_module(source_type) do
      nil ->
        Logger.error("Unknown ingest source_type #{inspect(source_type)}; skipping")
        {:error, :unknown_source_type}

      mod ->
        dispatch_ingest(mod, source_type, source_id, workspace_id)
    end
  end

  defp dispatch_ingest(mod, source_type, source_id, workspace_id) do
    case mod.ingest_descriptor(source_id, workspace_id) do
      {:ok, %{source_id: sid, body: body, chunker_opts: opts}} ->
        do_ingest(workspace_id, sid, body, opts)

      :skip ->
        Logger.info("#{source_type}:#{source_id} has nothing to ingest; skipping")
        :ok

      {:error, reason} = error ->
        Logger.error("Failed to ingest #{source_type}:#{source_id}: #{inspect(reason)}")
        error
    end
  end

  # Resolve a source_type string to its Containable module. The discriminator
  # atom is registry-validated, so `to_existing_atom` is safe (the atom exists
  # whenever the module is registered).
  defp container_module(source_type) do
    Concept.Containable.module_for(String.to_existing_atom(source_type))
  rescue
    ArgumentError -> nil
  end

  defp do_ingest(workspace_id, source_id, body, chunker_opts) do
    case Concept.Knowledge.Indexer.ingest_source(workspace_id, source_id, body, chunker_opts) do
      {:ok, _chunk_count} ->
        :ok

      {:error, reason} = err ->
        Logger.error("Arcana ingest failed for #{source_id}: #{inspect(reason)}")
        err
    end
  end
end
