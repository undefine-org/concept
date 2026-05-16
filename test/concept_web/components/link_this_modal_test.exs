defmodule ConceptWeb.Components.LinkThisModalTest do
  use ConceptWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Concept.Pages
  alias Concept.Knowledge
  alias ConceptWeb.Components.LinkThisModal

  require Ash.Query

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

    # Create test pages and blocks
    {:ok, page1} =
      Pages.create_page("Test Page 1", workspace.id, nil, actor: user, tenant: workspace.id)

    {:ok, page2} =
      Pages.create_page("Test Page 2", workspace.id, nil, actor: user, tenant: workspace.id)

    {:ok, block1} =
      Pages.create_block(page1.id, :paragraph, workspace.id, nil,
        actor: user,
        tenant: workspace.id
      )

    {:ok, block2} =
      Pages.create_block(page2.id, :paragraph, workspace.id, nil,
        actor: user,
        tenant: workspace.id
      )

    %{
      user: user,
      workspace: workspace,
      page1: page1,
      page2: page2,
      block1: block1,
      block2: block2
    }
  end

  describe "link_this_modal/1" do
    test "renders 4 kind options when shown", %{
      block1: block1,
      block2: block2
    } do
      html =
        render_component(&LinkThisModal.link_this_modal/1,
          show: true,
          source_block_id: block1.id,
          target_block_id: block2.id,
          error: nil
        )

      assert html =~ "Link this block"
      assert html =~ "Relationship type"
      assert html =~ ~s(<option value="relates_to">Relates to</option>)
      assert html =~ ~s(<option value="cites">Cites</option>)
      assert html =~ ~s(<option value="contradicts">Contradicts</option>)
      assert html =~ ~s(<option value="see_also">See also</option>)
    end

    test "does not render when show is false" do
      html =
        render_component(&LinkThisModal.link_this_modal/1,
          show: false,
          source_block_id: Ash.UUID.generate(),
          target_block_id: Ash.UUID.generate(),
          error: nil
        )

      refute html =~ "Link this block"
    end

    test "displays error message when present", %{
      block1: block1,
      block2: block2
    } do
      html =
        render_component(&LinkThisModal.link_this_modal/1,
          show: true,
          source_block_id: block1.id,
          target_block_id: block2.id,
          error: "This is a test error"
        )

      assert html =~ "This is a test error"
    end

    test "disables submit button when source and target are the same", %{
      block1: block1
    } do
      html =
        render_component(&LinkThisModal.link_this_modal/1,
          show: true,
          source_block_id: block1.id,
          target_block_id: block1.id,
          error: nil
        )

      assert html =~ "disabled"
      assert html =~ "Create Link"
    end
  end

  describe "Link creation" do
    test "creates link successfully", %{
      user: user,
      workspace: workspace,
      block1: block1,
      block2: block2
    } do
      link_attrs = %{
        source_block_id: block1.id,
        target_block_id: block2.id,
        kind: :relates_to,
        note: "Test note",
        workspace_id: workspace.id
      }

      {:ok, link} =
        Knowledge.Link
        |> Ash.Changeset.for_create(:create, link_attrs, actor: user, tenant: workspace.id)
        |> Ash.create()

      assert link.source_block_id == block1.id
      assert link.target_block_id == block2.id
      assert link.kind == :relates_to
      assert link.note == "Test note"
    end

    test "rejects duplicate link", %{
      user: user,
      workspace: workspace,
      block1: block1,
      block2: block2
    } do
      link_attrs = %{
        source_block_id: block1.id,
        target_block_id: block2.id,
        kind: :relates_to,
        workspace_id: workspace.id
      }

      # Create first link
      {:ok, _link} =
        Knowledge.Link
        |> Ash.Changeset.for_create(:create, link_attrs, actor: user, tenant: workspace.id)
        |> Ash.create()

      # Try to create duplicate
      result =
        Knowledge.Link
        |> Ash.Changeset.for_create(:create, link_attrs, actor: user, tenant: workspace.id)
        |> Ash.create()

      assert {:error, %Ash.Error.Invalid{}} = result
    end

    test "rejects self-link", %{
      user: user,
      workspace: workspace,
      block1: block1
    } do
      link_attrs = %{
        source_block_id: block1.id,
        target_block_id: block1.id,
        kind: :relates_to,
        workspace_id: workspace.id
      }

      result =
        Knowledge.Link
        |> Ash.Changeset.for_create(:create, link_attrs, actor: user, tenant: workspace.id)
        |> Ash.create()

      assert {:error, %Ash.Error.Invalid{errors: errors}} = result
      assert Enum.any?(errors, fn error -> error.message =~ "cannot link a block to itself" end)
    end
  end
end
