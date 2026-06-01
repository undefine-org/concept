defmodule ConceptWeb.Blocks.AiAnswerTest do
  @moduledoc """
  Contract test for the AI Answer interactive block.

  Proves the full client→server roundtrip wired by
  `Concept.Pages.BlockType.Interactive`:

  1. A `phx-hook="OraBlock"` wrapper exists on the rendered block.
  2. The wrapper's `data-events` is derived from the module's `ash_actions`.
  3. Pushing an `evaluate` event with `{prompt, scope, profile}` invokes
     `Concept.Pages.evaluate_ai/4`, which synchronously updates
     `block.props["prompt" | "scope" | "profile"]` before spawning the async
     evaluation Task.

  This is the test that would have caught the original bug (no LV handler
  for the `evaluate_ai` event); it covers the wiring contract, not the
  downstream AI pipeline.
  """
  use ConceptWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Concept.Accounts
  alias Concept.Pages
  alias Concept.Repo
  import Ecto.Query

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "ai-contract-#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    Repo.update_all(
      from(u in Accounts.User, where: u.id == ^user.id),
      set: [confirmed_at: DateTime.utc_now()]
    )

    {:ok, signed_in} =
      Accounts.User
      |> Ash.Query.for_read(:sign_in_with_password, %{email: user.email, password: "passw0rd!"})
      |> Ash.read_one(authorize?: false)

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session("user_token", signed_in.__metadata__.token)

    {:ok, [ws]} = Accounts.Workspace.for_user(user.id, actor: user)
    {:ok, page} = Pages.create_page("AI Wiring Page", ws.id, nil, actor: user, tenant: ws.id)

    {:ok, block} =
      Pages.create_block(:page, page.id, :ai_answer, ws.id, nil, actor: user, tenant: ws.id)

    {:ok, conn: conn, user: user, ws: ws, page: page, block: block}
  end

  defp page_editor_view(view, page_id) do
    # The AI Answer LiveComponent lives inside `PageEditorLive`, which is
    # mounted via `live_render` from `WorkspaceLive`. Events targeted at the
    # LC must be pushed to the nested LV, not the root.
    find_live_child(view, "page-editor-#{page_id}")
  end

  test "wrapper exposes phx-hook + data-events derived from ash_actions",
       %{conn: conn, ws: ws, page: page, block: block} do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")
    inner = page_editor_view(view, page.id)

    assert has_element?(inner, "div#ai-#{block.id}[phx-hook=\"OraBlock\"]")
    assert has_element?(inner, "div#ai-#{block.id}[data-block-id=\"#{block.id}\"]")
    assert has_element?(inner, "div#ai-#{block.id}[data-events=\"evaluate refresh retry\"]")
  end

  test "evaluate event invokes Concept.Pages.evaluate_ai and persists prompt/scope/profile",
       %{conn: conn, user: user, ws: ws, page: page, block: block} do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")
    inner = page_editor_view(view, page.id)

    # `render_hook/3` routes the event through the LiveComponent owning the
    # matched element — here the AiAnswer LC, because its `render/1` wraps
    # the inner Lit element in a <div phx-hook="OraBlock" phx-target={@myself}>.
    inner
    |> element("div#ai-#{block.id}")
    |> render_hook("evaluate", %{
      "block_id" => block.id,
      "prompt" => "Roundtrip OK?",
      "scope" => "workspace",
      "profile" => "default"
    })

    reloaded = Ash.get!(Pages.Block, block.id, actor: user, tenant: ws.id)

    assert reloaded.props["prompt"] == "Roundtrip OK?"
    assert reloaded.props["scope"] == "workspace"
    assert reloaded.props["profile"] == "default"
  end
end
