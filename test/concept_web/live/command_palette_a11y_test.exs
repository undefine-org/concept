defmodule ConceptWeb.CommandPaletteA11yTest do
  @moduledoc """
  BUG-065: the command palette is a modal searchable list with full keyboard
  navigation but no ARIA semantics. Screen-reader users cannot perceive the
  dialog, the combobox/listbox roles, which option is active, or how many
  results exist.

  These tests pin the ARIA combobox+listbox contract, palette-scoped.
  """
  use ConceptWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Concept.{Accounts, Pages, Repo}
  import Ecto.Query

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "pala11y#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    Repo.update_all(from(u in Accounts.User, where: u.id == ^user.id),
      set: [confirmed_at: DateTime.utc_now()]
    )

    {:ok, si} =
      Accounts.User
      |> Ash.Query.for_read(:sign_in_with_password, %{email: user.email, password: "passw0rd!"})
      |> Ash.read_one(authorize?: false)

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session("user_token", si.__metadata__.token)

    {:ok, [ws]} = Accounts.Workspace.for_user(user.id, actor: user)
    {:ok, page} = Pages.create_page("Roadmap", ws.id, nil, actor: user, tenant: ws.id)
    {:ok, conn: conn, user: user, ws: ws, page: page}
  end

  defp open(view) do
    view |> element("#workspace-root") |> render_hook("open_command_palette", %{})
    render_async(view)
  end

  defp search(view, q) do
    view |> element(~s{#command-palette input[type="text"]}) |> render_keyup(%{key: "", value: q})
    render_async(view)
  end

  describe "ARIA combobox/listbox semantics (BUG-065)" do
    test "dialog exposes role=dialog + aria-modal + label", %{conn: conn, ws: ws} do
      {:ok, view, _} = live(conn, ~p"/w/#{ws.slug}")
      open(view)

      assert has_element?(view, ~s{#command-palette [role="dialog"][aria-modal="true"]}),
             "palette overlay must be a labelled modal dialog"

      assert has_element?(view, ~s{#command-palette [role="dialog"][aria-label]})
    end

    test "input is a combobox controlling the listbox", %{conn: conn, ws: ws} do
      {:ok, view, _} = live(conn, ~p"/w/#{ws.slug}")
      open(view)

      assert has_element?(
               view,
               ~s{#command-palette input[role="combobox"][aria-controls="palette-listbox"][aria-expanded="true"]}
             ),
             "search input must be an expanded combobox controlling the listbox"

      assert has_element?(view, ~s{#command-palette input[role="combobox"][aria-label]})
    end

    test "results container is a listbox with option rows", %{conn: conn, ws: ws} do
      {:ok, view, _} = live(conn, ~p"/w/#{ws.slug}")
      open(view)

      assert has_element?(view, ~s{#command-palette #palette-listbox[role="listbox"]})
      # Empty-query state shows actions as options.
      assert has_element?(view, ~s{#command-palette #palette-listbox [role="option"]})
    end

    test "selected option carries aria-selected and is the combobox active descendant",
         %{conn: conn, ws: ws, page: page} do
      {:ok, view, _} = live(conn, ~p"/w/#{ws.slug}")
      open(view)
      _ = search(view, "oad")

      # The page's title row is an option.
      assert has_element?(
               view,
               ~s{#command-palette [role="option"][data-page-id="#{page.id}"]}
             )

      # selected_index starts at 0 → first option is selected.
      assert has_element?(view, ~s{#command-palette #palette-item-0[aria-selected="true"]})

      # The combobox points at the active option via aria-activedescendant.
      assert has_element?(
               view,
               ~s{#command-palette input[role="combobox"][aria-activedescendant="palette-item-0"]}
             )
    end

    test "aria-selected moves with ArrowDown", %{conn: conn, ws: ws} do
      {:ok, view, _} = live(conn, ~p"/w/#{ws.slug}")
      open(view)
      _ = search(view, "oad")

      assert has_element?(view, ~s{#command-palette #palette-item-0[aria-selected="true"]})

      view
      |> element(~s{#command-palette [phx-window-keydown="palette_key"]})
      |> render_keydown(%{key: "ArrowDown"})

      assert has_element?(view, ~s{#command-palette #palette-item-1[aria-selected="true"]})
      assert has_element?(view, ~s{#command-palette #palette-item-0[aria-selected="false"]})

      assert has_element?(
               view,
               ~s{#command-palette input[role="combobox"][aria-activedescendant="palette-item-1"]}
             )
    end
  end
end
