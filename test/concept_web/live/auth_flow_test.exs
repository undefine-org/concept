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

  # Variant of authed_conn/2 that strips the auto-created workspace +
  # membership left behind by the RunOnboarding after-action change.
  # Lets us simulate the "no primary workspace" recovery path that the
  # post-auth redirects need to handle gracefully (BUG-037 scenario 1).
  defp authed_conn_no_ws(conn, prefix) do
    {conn, user, ws} = authed_conn(conn, prefix)
    Ash.destroy!(ws, authorize?: false)
    {conn, user}
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

    # BUG-037 scenario 1: signed-in user with NO workspace.
    #
    # We bypass Onboarding by destroying the auto-created workspace, then
    # walk the post-auth surfaces a real user would hit:
    #
    #   /        — HomeLive must NOT redirect to /w/<slug> (none exists)
    #             and is free to stay on the public landing.
    #   /sign-in — :after_sign_in hook must NOT redirect (no primary).
    #   /w       — WorkspaceLive :index has no slug to forward to;
    #             it must surface the failure (flash + bounce back to /)
    #             instead of crashing or looping. Final landing is /, not
    #             /w/<slug>.
    #
    # If the recovery contract regresses (e.g. HomeLive raises on nil
    # workspace, or :after_sign_in tries to navigate to /w/), this test
    # is what catches it.
    test "user with NO workspace lands on / (not /w/<slug>) on every post-auth surface",
         %{conn: conn} do
      {conn, user} = authed_conn_no_ws(conn, "nows")

      # Sanity: the user really has zero workspaces.
      assert {:ok, []} = Accounts.Workspace.for_user(user.id, actor: user)

      # HomeLive must stay on / for a signed-in user with no workspace.
      assert {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ "Enter your workspace"

      # :after_sign_in must NOT force-redirect a no-workspace user.
      assert {:ok, _view, _html} = live(conn, ~p"/sign-in")

      # /w (index) has nothing to forward to → bounce back to / with a
      # flash, *not* a crash and *not* a slug-less /w/.
      assert {:error, {:live_redirect, %{to: "/", flash: flash}}} = live(conn, ~p"/w")
      assert flash["error"] == "No workspace found"

      # And the bounce truly did not silently create a workspace.
      assert {:ok, []} = Accounts.Workspace.for_user(user.id, actor: user)
    end
  end
end
