defmodule ConceptWeb.AuthFlowTest do
  @moduledoc """
  Post-authentication landing flow (BUG-020).

  After a fresh registration, a returning sign-in, or any other path
  that leaves the user authenticated on a root-level route, the user
  should land directly on their primary workspace (`/w/:slug`) rather
  than the public marketing page.

  The redirect is driven by two complementary hooks:

    * `ConceptWeb.LiveUserAuth.:after_sign_in` on the auth routes,
    * `ConceptWeb.HomeLive.mount/3` for direct visits to `/`.
  """
  use ConceptWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Ecto.Query

  alias Concept.Accounts
  alias Concept.Repo

  defp authed_conn(conn, prefix) do
    email = "#{prefix}#{System.unique_integer([:positive])}@example.com"
    password = "passw0rd!"

    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: email,
        password: password,
        password_confirmation: password
      })
      |> Ash.create(authorize?: false)

    # Simulate the user clicking the confirmation link.
    Repo.update_all(
      from(u in Concept.Accounts.User, where: u.id == ^user.id),
      set: [confirmed_at: DateTime.utc_now()]
    )

    {:ok, signed_in} =
      Concept.Accounts.User
      |> Ash.Query.for_read(:sign_in_with_password, %{email: email, password: password})
      |> Ash.read_one(authorize?: false)

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session("user_token", signed_in.__metadata__.token)

    {:ok, [ws]} = Accounts.Workspace.for_user(user.id, actor: user)
    {conn, user, ws}
  end

  describe "post-auth landing" do
    test "fresh registration → confirmed user → push_navigate to /w/<slug>", %{conn: conn} do
      {conn, _user, ws} = authed_conn(conn, "register")

      assert {:error, {:live_redirect, %{to: target}}} = live(conn, ~p"/")
      assert target == "/w/#{ws.slug}"
    end

    test "returning user hitting /sign-in is bounced to /w/<slug>", %{conn: conn} do
      {conn, _user, ws} = authed_conn(conn, "returning")

      assert {:error, {:live_redirect, %{to: target}}} = live(conn, ~p"/sign-in")
      assert target == "/w/#{ws.slug}"
    end

    test "signed-in user hitting / push_navigates to /w/<slug>", %{conn: conn} do
      {conn, _user, ws} = authed_conn(conn, "homehit")

      assert {:error, {:live_redirect, %{to: target}}} = live(conn, ~p"/")
      assert target == "/w/#{ws.slug}"
    end
  end
end
