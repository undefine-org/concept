defmodule ConceptWeb.Components.CitationCardTest do
  use Concept.DataCase, async: true

  import Phoenix.LiveViewTest

  alias Concept.Pages
  alias ConceptWeb.Components.CitationCard

  setup do
    # Create test user
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "test_#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    # Get user's workspace
    {:ok, [workspace]} = Concept.Accounts.Workspace.for_user(user.id, actor: user)

    # Create a test page
    {:ok, page} =
      Pages.create_page("Test Page", workspace.id, nil, actor: user, tenant: workspace.id)

    # Create a test block with content
    {:ok, block} =
      Pages.create_block(
        :page,
        page.id,
        :paragraph,
        workspace.id,
        nil,
        actor: user,
        tenant: workspace.id
      )

    # Acquire lock before updating content
    {:ok, block} =
      Pages.acquire_lock(block, %{user_id: user.id}, actor: user, tenant: workspace.id)

    {:ok, block} =
      Pages.update_content(
        block,
        %{
          "root" => %{
            "type" => "root",
            "children" => [%{"type" => "text", "text" => "Test block content"}]
          }
        },
        actor: user,
        tenant: workspace.id
      )

    # Release lock after update
    {:ok, block} = Pages.release_lock(block, actor: user, tenant: workspace.id)

    %{user: user, workspace: workspace, page: page, block: block}
  end

  describe "citation_card/1" do
    test "renders title-hit shape when breadcrumbs is nil", %{
      workspace: workspace,
      page: page,
      block: block
    } do
      citation = %{
        id: Ash.UUID.generate(),
        workspace_id: workspace.id,
        message_id: Ash.UUID.generate(),
        block_id: block.id,
        page_id: page.id,
        rank: 1,
        score: 0.95,
        snippet: nil,
        breadcrumbs: nil
      }

      html =
        render_component(&CitationCard.citation_card/1,
          citation: citation,
          workspace_slug: workspace.slug
        )

      assert html =~ "hero-document-text"
      refute html =~ "hero-sparkles"
    end

    test "renders semantic-hit shape when breadcrumbs and snippet present", %{
      workspace: workspace,
      page: page,
      block: block
    } do
      citation = %{
        id: Ash.UUID.generate(),
        workspace_id: workspace.id,
        message_id: Ash.UUID.generate(),
        block_id: block.id,
        page_id: page.id,
        rank: 1,
        score: 0.85,
        snippet: "This is a test snippet with some content",
        breadcrumbs: "Workspace > Test Page > Paragraph"
      }

      html =
        render_component(&CitationCard.citation_card/1,
          citation: citation,
          workspace_slug: workspace.slug
        )

      assert html =~ "hero-sparkles"
      refute html =~ "hero-document-text"
      assert html =~ "Workspace › Test Page › Paragraph"
      assert html =~ "This is a test snippet with some content"
    end

    test "link href matches expected deep-link pattern", %{
      workspace: workspace,
      page: page,
      block: block
    } do
      citation = %{
        id: Ash.UUID.generate(),
        workspace_id: workspace.id,
        message_id: Ash.UUID.generate(),
        block_id: block.id,
        page_id: page.id,
        rank: 1,
        score: 0.75,
        snippet: nil,
        breadcrumbs: nil
      }

      html =
        render_component(&CitationCard.citation_card/1,
          citation: citation,
          workspace_slug: workspace.slug
        )

      expected_href = "/w/#{workspace.slug}/p/#{page.id}#block-#{block.id}"
      assert html =~ expected_href
    end

    test "score sparkline aria-valuenow matches round(score*100)", %{
      workspace: workspace,
      page: page,
      block: block
    } do
      citation = %{
        id: Ash.UUID.generate(),
        workspace_id: workspace.id,
        message_id: Ash.UUID.generate(),
        block_id: block.id,
        page_id: page.id,
        rank: 1,
        score: 0.876,
        snippet: nil,
        breadcrumbs: nil
      }

      html =
        render_component(&CitationCard.citation_card/1,
          citation: citation,
          workspace_slug: workspace.slug
        )

      # 0.876 * 100 = 87.6 -> round(87.6) = 88
      assert html =~ ~r/aria-valuenow="88"/
    end

    test "score sparkline handles nil score", %{workspace: workspace, page: page, block: block} do
      citation = %{
        id: Ash.UUID.generate(),
        workspace_id: workspace.id,
        message_id: Ash.UUID.generate(),
        block_id: block.id,
        page_id: page.id,
        rank: 1,
        score: nil,
        snippet: nil,
        breadcrumbs: nil
      }

      html =
        render_component(&CitationCard.citation_card/1,
          citation: citation,
          workspace_slug: workspace.slug
        )

      assert html =~ ~r/aria-valuenow="0"/
      assert html =~ ~r/width: 0%/
    end
  end

  describe "load_block_preview/2" do
    test "returns HTML containing block content text", %{
      user: user,
      workspace: workspace,
      block: block
    } do
      # Mock socket with required assigns
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          workspace: workspace,
          current_user: user
        }
      }

      {:ok, html} = CitationCard.load_block_preview(block.id, socket)

      assert is_binary(html)
      assert html =~ "Test block content"
    end

    test "returns error for non-existent block", %{user: user, workspace: workspace} do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          workspace: workspace,
          current_user: user
        }
      }

      non_existent_id = Ash.UUID.generate()
      result = CitationCard.load_block_preview(non_existent_id, socket)

      assert {:error, _} = result
    end
  end
end
