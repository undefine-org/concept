defmodule Concept.AshOban.WorkspaceTenants do
  @moduledoc """
  `AshOban.ListTenants` implementation for workspace-scoped triggers.

  Any tenant-aware resource that declares `multitenancy global? false` must
  wire its trigger to a tenant lister, otherwise the cron-scheduled scheduler
  invokes `Ash.read!/2` without a tenant and `Ash.Actions.Read` rejects the
  query (see BUG-043).

  Returns every workspace id; the per-tenant read still filters down to
  rows in scope for the trigger.

  ## Usage

      oban do
        triggers do
          trigger :process do
            ...
            list_tenants Concept.AshOban.WorkspaceTenants
            actor_persister Concept.AshOban.SystemActorPersister
          end
        end
      end
  """

  @behaviour AshOban.ListTenants

  alias Concept.Accounts.Workspace

  @impl true
  def list_tenants(_opts) do
    Workspace
    |> Ash.read!(authorize?: false)
    |> Enum.map(& &1.id)
  end
end
