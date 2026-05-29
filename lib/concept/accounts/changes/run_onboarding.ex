defmodule Concept.Accounts.Changes.RunOnboarding do
  @moduledoc "After-action change that runs the Onboarding Reactor for a newly created user."
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _ctx) do
    Ash.Changeset.after_action(changeset, fn _cs, user ->
      case Reactor.run(Concept.Accounts.Reactors.Onboarding, %{user: user}, %{}, async?: false) do
        {:ok, workspace} ->
          # Seed the built-in Task object type for the new workspace. Done here
          # (after the reactor commits) so seed writes land in their own
          # transactions; the seeder is idempotent.
          _ = Concept.Objects.Seeder.seed_task_type(workspace.id)
          {:ok, user}

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end
end
