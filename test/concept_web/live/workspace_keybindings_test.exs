defmodule ConceptWeb.WorkspaceKeybindingsTest do
  @moduledoc """
  FUP-034: GlobalKeys hook is the *single* keyboard authority on the workspace.

  The legacy `phx-window-keydown="global_key"` mechanism was dead code — the
  hook's document listener calls `stopPropagation`, so k/j never reached the
  window listener. These tests pin the consolidated contract:

    - `#workspace-root` carries NO `phx-window-keydown` (one mechanism only)
    - chat toggles via the real `toggle_chat` runtime event (hook target)
    - palette opens via the real `open_command_palette` event (hook target)
    - Escape closes palette-then-chat via the `escape` event (hook target)
  """
  use ConceptWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Concept.Accounts
  alias Concept.Repo
  import Ecto.Query

  setup %{conn: conn} do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "keys#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    Repo.update_all(
      from(u in Concept.Accounts.User, where: u.id == ^user.id),
      set: [confirmed_at: DateTime.utc_now()]
    )

    {:ok, signed_in} =
      Concept.Accounts.User
      |> Ash.Query.for_read(:sign_in_with_password, %{email: user.email, password: "passw0rd!"})
      |> Ash.read_one(authorize?: false)

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session("user_token", signed_in.__metadata__.token)

    {:ok, [ws]} = Accounts.Workspace.for_user(user.id, actor: user)

    {:ok, conn: conn, user: user, ws: ws}
  end

  describe "single keyboard mechanism (FUP-034)" do
    test "#workspace-root keeps GlobalKeys hook as sole owner — no phx-window-keydown",
         %{conn: conn, ws: ws} do
      {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}")

      # The hook is the sole keyboard owner: present on #workspace-root, which
      # itself carries no phx-window-keydown (the dead/duplicate mechanism).
      assert has_element?(view, "#workspace-root[phx-hook*='GlobalKeys']"),
             "GlobalKeys hook must remain on #workspace-root"

      refute has_element?(view, "#workspace-root[phx-window-keydown]"),
             "phx-window-keydown is dead/duplicate; the hook owns Cmd-K/Cmd-J/Escape"
    end
  end

  describe "chat toggle (Cmd-J → toggle_chat)" do
    test "toggle_chat opens then closes the chat panel", %{conn: conn, ws: ws} do
      {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}")
      refute render(view) =~ "ora-chat-panel--open"

      view |> element("#workspace-root") |> render_hook("toggle_chat", %{})
      assert render(view) =~ "ora-chat-panel--open"

      view |> element("#workspace-root") |> render_hook("toggle_chat", %{})
      refute render(view) =~ "ora-chat-panel--open"
    end
  end

  describe "chat state mirrored to hook (Escape gating)" do
    # The GlobalKeys hook gates Escape on `_chatOpen`, synced via push_event.
    # Without this push, Escape-to-close-chat silently breaks in the browser.
    test "toggle_chat pushes chat_state so the hook can gate Escape",
         %{conn: conn, ws: ws} do
      {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}")

      view |> element("#workspace-root") |> render_hook("toggle_chat", %{})
      assert_push_event(view, "chat_state", %{open: true})

      view |> element("#workspace-root") |> render_hook("toggle_chat", %{})
      assert_push_event(view, "chat_state", %{open: false})
    end
  end

  describe "command palette (Cmd-K → open_command_palette)" do
    test "open_command_palette shows the palette", %{conn: conn, ws: ws} do
      {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}")
      # #command-palette is always mounted; the search input renders only when open.
      refute palette_open?(view)

      view |> element("#workspace-root") |> render_hook("open_command_palette", %{})
      assert palette_open?(view)
    end
  end

  describe "escape (Escape → escape) closes palette-then-chat" do
    test "escape closes the palette when open, leaving chat untouched", %{conn: conn, ws: ws} do
      {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}")

      view |> element("#workspace-root") |> render_hook("toggle_chat", %{})
      view |> element("#workspace-root") |> render_hook("open_command_palette", %{})
      assert palette_open?(view)
      assert render(view) =~ "ora-chat-panel--open"

      view |> element("#workspace-root") |> render_hook("escape", %{})
      refute palette_open?(view)
      assert render(view) =~ "ora-chat-panel--open"
    end

    test "escape closes the chat panel when palette is closed", %{conn: conn, ws: ws} do
      {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}")

      view |> element("#workspace-root") |> render_hook("toggle_chat", %{})
      assert render(view) =~ "ora-chat-panel--open"

      view |> element("#workspace-root") |> render_hook("escape", %{})
      refute render(view) =~ "ora-chat-panel--open"
    end
  end

  # The palette is "open" when its search input is present inside #command-palette.
  defp palette_open?(view) do
    has_element?(view, "#command-palette input[placeholder='Search pages or run a command...']")
  end
end
