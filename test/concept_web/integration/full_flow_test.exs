defmodule ConceptWeb.Integration.FullFlowTest do
  use ConceptWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  describe "happy path" do
    test "unauth visit /w redirects to /sign-in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/w")
    end

    test "home page renders Concept landing", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ "Concept"
      assert html =~ "ora-hello"
    end

    test "register → onboarding creates workspace + membership", %{conn: _conn} do
      email = "flow#{System.unique_integer([:positive])}@example.com"

      {:ok, user} =
        Concept.Accounts.User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: email,
          password: "passw0rd!",
          password_confirmation: "passw0rd!"
        })
        |> Ash.create(authorize?: false)

      {:ok, [ws]} = Concept.Accounts.Workspace.for_user(user.id, actor: user)
      assert ws.owner_id == user.id

      {:ok, page} = Concept.Pages.create_page("Roadmap", ws.id, nil, actor: user, tenant: ws.id)
      assert page.title == "Roadmap"

      {:ok, b1} =
        Concept.Pages.create_block(page.id, :paragraph, ws.id, nil, actor: user, tenant: ws.id)

      {:ok, b2} =
        Concept.Pages.create_block(page.id, :heading_1, ws.id, nil, actor: user, tenant: ws.id)

      {:ok, blocks} = Concept.Pages.list_for_page(page.id, actor: user, tenant: ws.id)
      assert length(blocks) == 2
      assert b1.position < b2.position
    end

    test "FractionalIndex.between produces strictly intermediate values" do
      a = Concept.Pages.FractionalIndex.initial()
      b = Concept.Pages.FractionalIndex.after_(a)
      mid = Concept.Pages.FractionalIndex.between(a, b)
      assert a < mid and mid < b
    end

    test "block_types registry has all 19 modules" do
      assert length(Concept.Pages.BlockTypes.all()) == 19
      slash = Concept.Pages.BlockTypes.slash_menu_items()
      assert Enum.any?(slash, &(&1.type == :paragraph))
      assert Enum.all?(slash, &(&1.group != :hidden))
    end

    test "Lexical.to_html escapes XSS and renders marks" do
      content = %{
        "root" => %{
          "type" => "root",
          "children" => [
            %{
              "type" => "paragraph",
              "children" => [
                %{"type" => "text", "text" => "hi", "format" => 1},
                %{"type" => "text", "text" => "<script>", "format" => 0}
              ]
            }
          ]
        }
      }

      html = Concept.Lexical.to_html(content)
      assert html =~ "<strong>hi</strong>"
      assert html =~ "&lt;script&gt;"
      refute html =~ "<script>"
    end
  end
end
