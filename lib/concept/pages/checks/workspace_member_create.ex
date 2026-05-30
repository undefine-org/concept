defmodule Concept.Pages.Checks.WorkspaceMemberCreate do
  @moduledoc """
  Create-action variant of `Concept.Pages.Checks.WorkspaceMember`.

  `Ash.Policy.FilterCheck` cannot authorize create actions that reference
  relationships (there is no row yet to filter against). This check reads
  the to-be-set `workspace_id` from the changeset and verifies the actor is
  a member.

  Only used on :create policies; read/update/destroy go through the
  `FilterCheck` variant so the membership predicate fuses into the main SQL.
  """
  use Ash.Policy.SimpleCheck
  require Ash.Query

  @impl true
  def describe(_), do: "actor is a member of the workspace being written to"

  @impl true
  def match?(nil, _, _), do: false

  def match?(actor, %{subject: %Ash.Changeset{} = changeset}, _opts) do
    workspace_id =
      Ash.Changeset.get_attribute(changeset, :workspace_id) ||
        Ash.Changeset.get_argument(changeset, :workspace_id)

    member?(actor, workspace_id)
  end

  # Generic actions (e.g. Conversation.:crystallize) carry an ActionInput whose
  # workspace tenant is passed as an argument.
  def match?(actor, %{subject: %Ash.ActionInput{} = input}, _opts) do
    member?(actor, Ash.ActionInput.get_argument(input, :workspace_id))
  end

  def match?(_actor, _context, _opts), do: false

  defp member?(_actor, nil), do: false

  defp member?(actor, workspace_id) do
    Concept.Accounts.Membership
    |> Ash.Query.filter(workspace_id == ^workspace_id and user_id == ^actor.id)
    |> Ash.read_first!(authorize?: false)
    |> is_map()
  end
end
