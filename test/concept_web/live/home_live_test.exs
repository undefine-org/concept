defmodule ConceptWeb.HomeLiveTest do
  use ConceptWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  import Ecto.Query
  alias Concept.{Accounts, Repo}

  defp authed_conn_no_ws(conn, prefix) do
    email = "#{prefix}#{System.unique_integer([:positive])}@example.com"
    password = "passw0rd!"

    {:ok, user} =
      Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: email,
        password: password,
        password_confirmation: password
      })
      |> Ash.create(authorize?: false)

    Repo.update_all(
      from(u in Accounts.User, where: u.id == ^user.id),
      set: [confirmed_at: DateTime.utc_now()]
    )

    {:ok, signed_in} =
      Accounts.User
      |> Ash.Query.for_read(:sign_in_with_password, %{email: email, password: password})
      |> Ash.read_one(authorize?: false)

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session("user_token", signed_in.__metadata__.token)

    # Destroy auto-created workspace so HomeLive stays mounted.
    {:ok, [ws]} = Accounts.Workspace.for_user(user.id, actor: user)
    Ash.destroy!(ws, authorize?: false)

    {conn, user}
  end

  describe "open_command_palette hook (BUG-025)" do
    test "signed-out user → no redirect", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html =
        view
        |> element("#home-root")
        |> render_hook("open_command_palette", %{})

      # Still on the home page.
      assert html =~ "Concept"
    end

    test "signed-in user → redirect to /w", %{conn: conn} do
      {conn, _user} = authed_conn_no_ws(conn, "homecmdk")

      {:ok, view, _html} = live(conn, ~p"/")

      assert {:error, {:live_redirect, %{kind: :push, to: "/w"}}} =
               view
               |> element("#home-root")
               |> render_hook("open_command_palette", %{})
    end
  end

  describe "close_command_palette hook (BUG-025)" do
    test "signed-out user → no-op", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html =
        view
        |> element("#home-root")
        |> render_hook("close_command_palette", %{})

      assert html =~ "Concept"
    end
  end
end
