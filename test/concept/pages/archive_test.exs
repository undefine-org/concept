defmodule Concept.Pages.ArchiveTest do
  @moduledoc """
  BUG-066: the :archive action must archive the target page itself (not only
  its descendants). AshArchival base_filter hides rows WITH archived_at set, so
  an archived page must drop out of default reads.
  """
  use Concept.DataCase, async: true
  import Ecto.Query

  alias Concept.Accounts
  alias Concept.Pages
  alias Concept.Repo

  setup do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "arch#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    {:ok, [ws]} = Accounts.Workspace.for_user(user.id, actor: user)
    {:ok, parent} = Pages.create_page("Parent", ws.id, nil, actor: user, tenant: ws.id)
    {:ok, child} = Pages.create_page("Child", ws.id, parent.id, actor: user, tenant: ws.id)

    {:ok, user: user, ws: ws, parent: parent, child: child}
  end

  defp raw_archived_at(id) do
    Repo.one(from p in "pages", where: p.id == type(^id, :binary_id), select: p.archived_at)
  end

  test "archiving a page archives the page itself", %{user: user, ws: ws, parent: parent} do
    assert {:ok, _} = Pages.archive(parent, actor: user, tenant: ws.id)

    # The page's own archived_at is set...
    assert raw_archived_at(parent.id) != nil

    # ...so it drops out of default reads (base_filter? true).
    assert {:error, _} = Pages.get_page(parent.id, actor: user, tenant: ws.id)
  end

  test "archiving cascades to descendants with the same timestamp",
       %{user: user, ws: ws, parent: parent, child: child} do
    assert {:ok, _} = Pages.archive(parent, actor: user, tenant: ws.id)

    parent_at = raw_archived_at(parent.id)
    child_at = raw_archived_at(child.id)

    assert parent_at != nil
    assert child_at != nil
    assert parent_at == child_at
  end
end
