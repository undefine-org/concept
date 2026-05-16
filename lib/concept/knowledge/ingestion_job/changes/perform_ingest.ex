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
           |> Ash.Query.filter(page_id == ^page_id)
           |> Ash.read(actor: actor, tenant: workspace_id) do
      collection = Config.collection_for(workspace_id)
      arcana_module = Application.get_env(:concept, :arcana_module, Arcana)

      case arcana_module.ingest("",
             repo: Concept.Repo,
             collection: collection,
             source_id: "page:#{page_id}",
             chunker_opts: [page: page, blocks: blocks, workspace_id: workspace_id]
           ) do
        {:ok, result} ->
          chunk_count = Map.get(result, :chunks, 0)
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

  defp perform_delete(_workspace_id, page_id, _actor) do
    # Arcana 2.0 doesn't expose delete_by_source_id; deferring to FEAT-035 Reactor
    Logger.warning("Delete for page:#{page_id} not yet implemented; skipping")
    {:ok, 0}
  end
end
