defmodule Concept.Knowledge.Workers.IngestPage do
  @moduledoc """
  Oban worker that ingests a page + blocks into Arcana for RAG search.
  Thin wrapper around Arcana.ingest/2; will be replaced by Reactor in FEAT-035.
  """
  use Oban.Worker, queue: :knowledge_ingest, max_attempts: 3

  require Logger

  alias Concept.Knowledge.Config
  alias Concept.Pages

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"workspace_id" => workspace_id, "page_id" => page_id, "op" => "upsert"}
      }) do
    # System actor for cross-tenant reads
    actor = %{system?: true}

    with {:ok, page} <- Pages.get_page(page_id, actor: actor, tenant: workspace_id),
         {:ok, blocks} <-
           Pages.list_for_page(page_id, actor: actor, tenant: workspace_id) do
      collection = Config.collection_for(workspace_id)
      arcana_module = Application.get_env(:concept, :arcana_module, Arcana)

      # `text` carries the page title as a non-empty document body. The custom
      # `Concept.Knowledge.BlockChunker` ignores it and rebuilds chunks from
      # `chunker_opts`; Arcana.Document still requires non-blank content.
      case arcana_module.ingest(page.title || "Untitled",
             repo: Concept.Repo,
             collection: collection,
             source_id: "page:#{page_id}",
             chunker_opts: [page: page, blocks: blocks, workspace_id: workspace_id]
           ) do
        {:ok, _result} ->
          :ok

        {:error, reason} = err ->
          Logger.error("Arcana ingest failed for page #{page_id}: #{inspect(reason)}")
          err
      end
    else
      {:error, %Ash.Error.Query.NotFound{}} ->
        Logger.info("Page #{page_id} not found for workspace #{workspace_id}; skipping ingest")
        :ok

      {:error, reason} = error ->
        Logger.error("Failed to ingest page #{page_id}: #{inspect(reason)}")
        error
    end
  end

  def perform(%Oban.Job{
        args: %{"workspace_id" => _workspace_id, "page_id" => page_id, "op" => "delete"}
      }) do
    # Arcana 2.0 doesn't expose delete_by_source_id; deferring to FEAT-035 Reactor implementation
    Logger.warning("Delete for page:#{page_id} not yet implemented; skipping")
    :ok
  end

  def perform(%Oban.Job{args: args}) do
    Logger.error("Invalid IngestPage job args: #{inspect(args)}")
    {:error, :invalid_args}
  end
end
