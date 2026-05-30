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

  alias Concept.Knowledge.Config
  alias Concept.Pages

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

  defp ingest("page", page_id, workspace_id) do
    actor = %{system?: true}

    with {:ok, page} <- Pages.get_page(page_id, actor: actor, tenant: workspace_id),
         {:ok, blocks} <- Pages.list_for_page(page_id, actor: actor, tenant: workspace_id) do
      do_ingest(workspace_id, "page:#{page_id}", page.title || "Untitled",
        page: page,
        blocks: blocks,
        workspace_id: workspace_id
      )
    else
      {:error, %Ash.Error.Query.NotFound{}} ->
        Logger.info("Page #{page_id} not found for workspace #{workspace_id}; skipping ingest")
        :ok

      {:error, reason} = error ->
        Logger.error("Failed to ingest page #{page_id}: #{inspect(reason)}")
        error
    end
  end

  defp ingest("message", message_id, workspace_id) do
    actor = %{system?: true}

    case Pages.list_for_message(message_id, actor: actor, tenant: workspace_id) do
      {:ok, []} ->
        # No rich blocks (text-only message): nothing to ingest as blocks.
        :ok

      {:ok, blocks} ->
        # A message has no title; use a stable breadcrumb. The chunker rebuilds
        # chunk text from the blocks, so the document body is just non-blank.
        do_ingest(workspace_id, "message:#{message_id}", "Message",
          blocks: blocks,
          workspace_id: workspace_id,
          message_id: message_id,
          breadcrumbs: "Conversation"
        )

      {:error, reason} = error ->
        Logger.error("Failed to ingest message #{message_id}: #{inspect(reason)}")
        error
    end
  end

  defp do_ingest(workspace_id, source_id, body, chunker_opts) do
    collection = Config.collection_for(workspace_id)
    arcana_module = Application.get_env(:concept, :arcana_module, Arcana)

    case arcana_module.ingest(body,
           repo: Concept.Repo,
           collection: collection,
           source_id: source_id,
           chunker_opts: chunker_opts
         ) do
      {:ok, _result} ->
        :ok

      {:error, reason} = err ->
        Logger.error("Arcana ingest failed for #{source_id}: #{inspect(reason)}")
        err
    end
  end
end
