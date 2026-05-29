defmodule Concept.Pages.Changes.AssertWorkspaceMatchesTenant do
  @moduledoc """
  Guards the `workspace_id` create argument against the resolved tenant.

  Workspace-tenanted resources derive `workspace_id` from the tenant
  (`handle_attribute_multitenancy` force-changes the attribute to the tenant
  before authorization and insert). The `workspace_id` argument is therefore
  redundant — and, left unchecked, *silently ignored*: a caller could pass any
  value (even a non-existent workspace) and the write would still land in the
  tenant's workspace.

  For MCP parity (finding M3) the argument must be **honest**: when a tenant is
  present, `workspace_id` must equal it, otherwise the action fails fast with a
  clear message instead of pretending to honor the argument.

  Tenant is always present for these resources on create (`global? false`), so
  the `nil` tenant branch is defensive only.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _ctx) do
    arg = Ash.Changeset.get_argument(changeset, :workspace_id)
    tenant = tenant_id(changeset)

    cond do
      is_nil(tenant) -> changeset
      is_nil(arg) -> changeset
      arg == tenant -> changeset
      true -> mismatch_error(changeset)
    end
  end

  defp mismatch_error(changeset) do
    Ash.Changeset.add_error(changeset,
      field: :workspace_id,
      message: "workspace_id must match the request tenant",
      code: :workspace_tenant_mismatch
    )
  end

  defp tenant_id(%{to_tenant: tenant}) when not is_nil(tenant), do: tenant
  defp tenant_id(%{tenant: tenant}), do: tenant
end
