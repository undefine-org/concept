defmodule ConceptWeb.ChatResumeTest do
  @moduledoc """
  B1/B2 (FUP-UX): the chat panel must resume the host's existing conversation
  on open and stay open through send — not reset to a blank seed state and not
  eject the user. These were the two Tier-0 "feels broken" blockers.
  """
  use ConceptWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Concept.Accounts
  alias Concept.Knowledge.Chat
  alias Concept.Repo
  import Ecto.Query

  setup %{conn: conn} do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "resume#{System.unique_integer([:positive])}@example.com",
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

  test "panel resumes the workspace host's existing conversation on open", ctx do
    # Seed a prior workspace-host conversation with a human message.
    {:ok, msg} =
      Chat.create_message(%{text: "prior question about the cutover", addresses_host: false},
        actor: ctx.user,
        tenant: ctx.ws.id
      )

    assert msg.conversation_id

    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}")

    # Open the chat panel.
    view |> element("#workspace-root") |> render_hook("toggle_chat", %{})
    :timer.sleep(80)

    html = render(view)
    # The prior message is shown — NOT the blank "Try asking" seed state.
    assert html =~ "prior question about the cutover",
           "expected the panel to resume the existing conversation on open"
  end

  test "first-run (no prior conversation) shows the seed prompts", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}")

    view |> element("#workspace-root") |> render_hook("toggle_chat", %{})
    :timer.sleep(80)

    html = render(view)
    # No conversation yet → the designed empty/seed state, not a crash.
    assert html =~ "Summarize this workspace" or html =~ "TRY ASKING" or
             html =~ "Try asking"
  end

  test "clicking a seed prompt sends immediately (one-click)", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}")
    view |> element("#workspace-root") |> render_hook("toggle_chat", %{})
    :timer.sleep(80)

    # Click a seed prompt button — it must SEND, not just fill the composer.
    view
    |> element("button[phx-value-prompt='Summarize this workspace']")
    |> render_click()

    :timer.sleep(120)
    html = render(view)
    # The prompt now appears as a sent message (a conversation exists / responding).
    assert html =~ "Summarize this workspace"
    # And it left the blank seed-only state: a responding cue or the message stream.
    assert html =~ "is thinking" or html =~ "ora-chat-message"
  end

  test "panel stays open across a re-render after opening", ctx do
    {:ok, _msg} =
      Chat.create_message(%{text: "keepopen probe", addresses_host: false},
        actor: ctx.user,
        tenant: ctx.ws.id
      )

    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}")
    view |> element("#workspace-root") |> render_hook("toggle_chat", %{})
    :timer.sleep(80)
    assert render(view) =~ "ora-chat-panel--open"

    # A subsequent unrelated re-render must not collapse the panel (B2).
    _ = render(view)
    assert render(view) =~ "ora-chat-panel--open"
  end
end
