defmodule Concept.Pages.PageTitleTest do
  @moduledoc """
  BUG-023: titles entered with surrounding (or pure) whitespace must be
  trimmed server-side so the empty-title placeholder renders correctly.
  """
  use Concept.DataCase, async: true

  alias Concept.Pages

  setup do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "title_test_#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    {:ok, [workspace]} = Concept.Accounts.Workspace.for_user(user.id, actor: user)

    {:ok, page} =
      Pages.create_page("Initial", workspace.id, nil, actor: user, tenant: workspace.id)

    %{user: user, workspace: workspace, page: page}
  end

  describe "rename_page trims whitespace" do
    test "whitespace-only title collapses to empty string", %{
      user: user,
      workspace: ws,
      page: page
    } do
      {:ok, renamed} =
        Pages.rename_page(page, "  ", actor: user, tenant: ws.id)

      assert renamed.title == ""
    end

    test "surrounding whitespace is stripped, inner spaces preserved", %{
      user: user,
      workspace: ws,
      page: page
    } do
      {:ok, renamed} =
        Pages.rename_page(page, "  hello world  ", actor: user, tenant: ws.id)

      assert renamed.title == "hello world"
    end
  end
end
