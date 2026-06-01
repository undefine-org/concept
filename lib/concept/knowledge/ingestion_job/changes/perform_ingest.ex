defmodule Concept.Knowledge.IngestionJob.Changes.PerformIngest do
  @moduledoc """
  Change that performs the actual Arcana ingestion during the :run action.

  On success: transitions to :succeeded with chunk_count.
  On failure: classifies error and transitions to :failed.

  Uses SystemActor for all cascade operations.
  """
  use Ash.Resource.Change
  require Logger

  alias Concept.Knowledge.{Config, SystemActor}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_transaction(changeset, &after_transaction/2)
  end

  defp after_transaction(_changeset, {:ok, record}) do
    workspace_id = record.workspace_id
    page_id = record.page_id
    op = record.op

    actor = %SystemActor{}

    result =
      case op do
        :upsert -> perform_upsert(workspace_id, page_id, actor)
        :delete -> perform_delete(workspace_id, page_id, actor)
      end

    case result do
      {:ok, chunk_count} ->
        # Transition to succeeded
        case record
             |> Ash.Changeset.for_update(:succeed, %{chunk_count: chunk_count},
               actor: actor,
               tenant: workspace_id
             )
             |> Ash.update() do
          {:ok, updated} -> {:ok, updated}
          {:error, e} -> {:error, e}
        end

      {:error, error_kind, error_message} ->
        # Transition to failed
        case record
             |> Ash.Changeset.for_update(
               :fail,
               %{error_kind: error_kind, error_message: error_message},
               actor: actor,
               tenant: workspace_id
             )
             |> Ash.update() do
          {:ok, updated} -> {:ok, updated}
          {:error, e} -> {:error, e}
        end
    end
  end

  defp after_transaction(_changeset, {:error, error}) do
    {:error, error}
  end

  defp perform_upsert(workspace_id, page_id, actor) do
    # Load page - catch NotFound and return gracefully
    case Ash.get(Concept.Pages.Page, page_id, actor: actor, tenant: workspace_id) do
      {:ok, page} ->
        perform_upsert_with_page(workspace_id, page_id, page, actor)

      {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{}]}} ->
        Logger.info("Page #{page_id} not found for workspace #{workspace_id}; skipping ingest")
        {:ok, 0}

      {:error, reason} ->
        Logger.error("Error fetching page #{page_id}: #{inspect(reason)}")
        {:error, :not_found, "Page not found"}
    end
  end

  defp perform_upsert_with_page(workspace_id, page_id, page, actor) do
    with {:ok, blocks} <-
           Concept.Pages.Block
           |> Ash.Query.filter(container_type == :page and container_id == ^page_id)
           |> Ash.read(actor: actor, tenant: workspace_id) do
      case Concept.Knowledge.Indexer.ingest_source(
             workspace_id,
             "page:#{page_id}",
             "",
             page: page,
             blocks: blocks,
             workspace_id: workspace_id
           ) do
        {:ok, chunk_count} ->
          {:ok, chunk_count}

        {:error, %{reason: :rate_limited}} ->
          {:error, :rate_limit, "Arcana rate limited"}

        {:error, %{reason: :timeout}} ->
          {:error, :timeout, "Arcana ingestion timeout"}

        {:error, reason} ->
          {:error, :unknown, "Arcana error: #{inspect(reason)}"}
      end
    else
      {:error, reason} ->
        {:error, :unknown, "Failed to load blocks: #{inspect(reason)}"}
    end
  end

  defp perform_delete(workspace_id, page_id, _actor) do
    import Ecto.Query

    collection_name = Config.collection_for(workspace_id)
    source_id = "page:#{page_id}"
    arcana_module = Application.get_env(:concept, :arcana_module, Arcana)

    # Arcana exposes delete/2 by document id but no delete-by-source helper.
    # Resolve the page's documents within this workspace's collection, then
    # delete each. Removing the documents cascades to their chunks, evicting
    # the page from retrieval (BUG-055). A missing collection means nothing
    # was ever ingested — treat as a no-op success.
    docs =
      from(d in Arcana.Document,
        join: c in Arcana.Collection,
        on: d.collection_id == c.id,
        where: c.name == ^collection_name and d.source_id == ^source_id,
        select: d.id
      )
      |> Concept.Repo.all()

    results = Enum.map(docs, fn id -> arcana_module.delete(id, repo: Concept.Repo) end)

    case Enum.find(results, &(&1 != :ok)) do
      nil -> {:ok, length(docs)}
      {:error, reason} -> {:error, :delete_failed, "Arcana delete failed: #{inspect(reason)}"}
      other -> {:error, :delete_failed, "Arcana delete failed: #{inspect(other)}"}
    end
  rescue
    e -> {:error, :unknown, "Delete for page:#{page_id} raised: #{Exception.message(e)}"}
  end
end
