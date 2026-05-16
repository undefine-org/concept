defmodule Concept.Accounts.Scope do
  @moduledoc """
  Authenticated request/LV scope: user + optional workspace + role.

  Constructed by `live_user_auth` on_mount hooks and threaded into every
  `<Layouts.app>` invocation. Future Ash policies and live_components can
  rely on `@current_scope` existing for authenticated routes.
  """

  alias Concept.Accounts

  defstruct [:user, :workspace, :role, system?: false]

  @type t :: %__MODULE__{
          user: Concept.Accounts.User.t(),
          workspace: Concept.Accounts.Workspace.t() | nil,
          role: :owner | :admin | :member | nil,
          system?: boolean()
        }

  @doc """
  Build a scope for `user` within `workspace_id`.

  ## Examples

      Scope.for_user(nil, _)           # => nil
      Scope.for_user(user, nil)         # => %Scope{user: user, workspace: nil, role: nil}
      Scope.for_user(user, workspace_id) # => resolves membership role

  When the user has no membership in the given workspace the scope still
  carries the user (workspace and role remain nil).
  """
  def for_user(user, workspace_id \\ nil)

  def for_user(nil, _), do: nil

  def for_user(user, nil), do: %__MODULE__{user: user}

  def for_user(user, workspace_id) do
    case Accounts.get_membership(user.id, workspace_id, actor: user) do
      {:ok, %{workspace: ws, role: role}} ->
        %__MODULE__{user: user, workspace: ws, role: role}

      _ ->
        %__MODULE__{user: user}
    end
  end
end
