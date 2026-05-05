defmodule Concept.Knowledge.Checks.WorkspaceArgumentMember do
  @moduledoc """
  Authorizes if the actor is a member of the workspace identified by
  the `:workspace_id` argument on the action input.
  """
  use Ash.Policy.SimpleCheck
  require Ash.Query

  @impl true
  def describe(_opts) do
    "actor is a member of the workspace passed as the :workspace_id argument"
  end

  @impl true
  def match?(_actor, _context, _opts) do
    false
  end

  @impl true
  def check(actor, _resource, opts, _context) do
    workspace_id = Ash.ActionInput.get_argument(opts[:action_input], :workspace_id)

    if is_nil(workspace_id) or is_nil(actor) do
      {:error, Ash.Error.Forbidden.exception([])}
    else
      actor_id = actor.id

      membership =
        Concept.Accounts.Membership
        |> Ash.Query.filter(workspace_id == ^workspace_id and user_id == ^actor_id)
        |> Ash.read_one!(actor: actor)

      if membership do
        :ok
      else
        {:error, Ash.Error.Forbidden.exception([])}
      end
    end
  end
end
