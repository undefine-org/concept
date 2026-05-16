defmodule Concept.Knowledge.Workers.RebuildCommunities do
  @moduledoc """
  Cron worker that rebuilds Leiden communities + LLM summaries for every workspace.
  Runs on the :knowledge_maintenance queue.
  """
  use Oban.Worker, queue: :knowledge_maintenance, max_attempts: 3

  require Logger

  alias Concept.Accounts.Workspace
  alias Concept.Knowledge.{Community, SystemActor}

  @impl Oban.Worker
  def perform(_job) do
    actor = %SystemActor{}
    workspaces = Ash.read!(Workspace, actor: actor)

    Enum.each(workspaces, fn ws ->
      case Community.rebuild_communities(ws.id) do
        {:ok, result} ->
          Logger.info("Communities rebuilt for workspace #{ws.id}",
            communities_detected: result.communities_detected,
            summaries_written: result.summaries_written
          )

        {:error, reason} ->
          Logger.error("Failed to rebuild communities for workspace #{ws.id}: #{inspect(reason)}")
      end
    end)

    :ok
  end
end
