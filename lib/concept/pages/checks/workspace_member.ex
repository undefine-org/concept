defmodule Concept.Pages.Checks.WorkspaceMember do
  @moduledoc "Authorizes when actor is a member of the page's tenant workspace."
  use Ash.Policy.SimpleCheck
  require Ash.Query

  @impl true
  def describe(_), do: "actor is a member of the workspace"

  @impl true
  def match?(nil, _, _), do: false

  def match?(actor, %{subject: subject} = _ctx, _opts) do
    workspace_id =
      cond do
        Map.has_key?(subject, :tenant) and not is_nil(subject.tenant) ->
          tenant_id(subject.tenant)

        Map.has_key?(subject, :data) and is_map(subject.data) ->
          Map.get(subject.data, :workspace_id)

        true ->
          nil
      end

    case workspace_id do
      nil ->
        false

      ws_id ->
        actor_id = actor.id

        Concept.Accounts.Membership
        |> Ash.Query.filter(workspace_id == ^ws_id and user_id == ^actor_id)
        |> Ash.read_first!(authorize?: false)
        |> is_map()
    end
  end

  defp tenant_id(t) when is_binary(t), do: t
  defp tenant_id(%{id: id}), do: id
  defp tenant_id(_), do: nil
end
