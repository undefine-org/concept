defmodule ConceptWeb.Components.IndexingPillTest do
  use ConceptWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Concept.Accounts
  alias Concept.Pages
  alias Concept.Knowledge.IngestionJob
  alias Concept.Repo
  import Ecto.Query

  setup %{conn: conn} do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "pill#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    # Confirm user directly
    Repo.update_all(
      from(u in Concept.Accounts.User, where: u.id == ^user.id),
      set: [confirmed_at: DateTime.utc_now()]
    )

    # Sign in to get token
    {:ok, signed_in} =
      Concept.Accounts.User
      |> Ash.Query.for_read(:sign_in_with_password, %{email: user.email, password: "passw0rd!"})
      |> Ash.read_one(authorize?: false)

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session("user_token", signed_in.__metadata__.token)

    {:ok, [ws]} = Accounts.Workspace.for_user(user.id, actor: user)
    {:ok, page} = Pages.create_page("Test Page", ws.id, nil, actor: user, tenant: ws.id)

    {:ok, conn: conn, user: user, ws: ws, page: page}
  end

  test "renders idle state by default", %{conn: conn, ws: ws} do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}")

    assert view |> element(".ora-pill") |> render() =~ "Idle"
  end

  test "PubSub ingest_started event → indexing state with count 1", %{conn: conn, ws: ws} do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}")

    # Send PubSub event
    Phoenix.PubSub.broadcast!(
      Concept.PubSub,
      "workspace:#{ws.id}:ingest",
      %Phoenix.Socket.Broadcast{
        event: "ingest_started",
        payload: %{data: %{id: Ash.UUIDv7.generate()}}
      }
    )

    # Give LiveView time to process
    :timer.sleep(50)

    assert view |> element(".ora-pill-indexing") |> render() =~ "Indexing"
    assert view |> element(".ora-pill-indexing") |> render() =~ "1"
  end

  test "ingest_succeeded decrements count and shows last success time", %{conn: conn, ws: ws} do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}")

    # Start one job
    Phoenix.PubSub.broadcast!(
      Concept.PubSub,
      "workspace:#{ws.id}:ingest",
      %Phoenix.Socket.Broadcast{
        event: "ingest_started",
        payload: %{data: %{id: Ash.UUIDv7.generate()}}
      }
    )

    :timer.sleep(50)
    assert view |> element(".ora-pill-indexing") |> has_element?()

    # Complete the job
    Phoenix.PubSub.broadcast!(
      Concept.PubSub,
      "workspace:#{ws.id}:ingest",
      %Phoenix.Socket.Broadcast{
        event: "ingest_succeeded",
        payload: %{data: %{id: Ash.UUIDv7.generate()}}
      }
    )

    :timer.sleep(50)

    # Should be back to idle with "Indexed ... ago"
    assert view |> element(".ora-pill-idle") |> render() =~ "Indexed"
    assert view |> element(".ora-pill-idle") |> render() =~ "ago"
  end

  test "click shows details popover with IngestionJob rows", %{conn: conn, ws: ws, page: page} do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}")

    # Create a test ingestion job (requires system actor)
    {:ok, _job} =
      IngestionJob
      |> Ash.Changeset.for_create(:enqueue, %{
        page_id: page.id,
        workspace_id: ws.id,
        op: :upsert
      })
      |> Ash.create(tenant: ws.id, authorize?: false)

    # Click the pill
    view |> element(".ora-pill") |> render_click()

    :timer.sleep(50)

    # Should show popover with jobs
    html = render(view)
    assert html =~ "Indexing Jobs"
    assert html =~ "Queued"
  end
end
