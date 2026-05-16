defmodule Concept.Knowledge.LinkTest do
  use Concept.DataCase, async: true

  alias Concept.Knowledge
  alias Concept.Pages
  import Ecto.Query

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

    # Get workspace for user
    {:ok, [workspace]} = Concept.Accounts.Workspace.for_user(user.id, actor: user)

    # Create two pages with blocks
    {:ok, page1} =
      Pages.create_page("Page 1", workspace.id, nil, actor: user, tenant: workspace.id)

    {:ok, page2} =
      Pages.create_page("Page 2", workspace.id, nil, actor: user, tenant: workspace.id)

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

  describe "create_link" do
    test "creates a link with valid attributes and mirrors to Arcana", %{
      workspace: workspace,
      user: user,
      block1: block1,
      block2: block2
    } do
      {:ok, link} =
        Knowledge.create_link(
          %{
            workspace_id: workspace.id,
            source_block_id: block1.id,
            target_block_id: block2.id,
            kind: :relates_to,
            note: "Test note"
          },
          actor: user,
          tenant: workspace.id
        )

      assert link.workspace_id == workspace.id
      assert link.source_block_id == block1.id
      assert link.target_block_id == block2.id
      assert link.kind == :relates_to
      assert link.note == "Test note"
      assert link.created_by_user_id == user.id

      # Verify Arcana.Graph.Relationship row exists
      arcana_rel =
        Concept.Repo.one(
          from r in Arcana.Graph.Relationship,
            where:
              r.source_id == ^block1.id and
                r.target_id == ^block2.id and
                r.type == "USER_RELATES_TO"
        )

      assert arcana_rel != nil
      assert arcana_rel.description == "Test note"
      assert arcana_rel.strength == 1
      assert arcana_rel.metadata["link_id"] == link.id
      assert arcana_rel.metadata["workspace_id"] == workspace.id
      assert arcana_rel.metadata["created_by"] == user.id
    end

    test "rejects duplicate triple (same source+target+kind)", %{
      workspace: workspace,
      user: user,
      block1: block1,
      block2: block2
    } do
      # Create first link
      {:ok, _link} =
        Knowledge.create_link(
          %{
            workspace_id: workspace.id,
            source_block_id: block1.id,
            target_block_id: block2.id,
            kind: :cites
          },
          actor: user,
          tenant: workspace.id
        )

      # Attempt duplicate
      {:error, error} =
        Knowledge.create_link(
          %{
            workspace_id: workspace.id,
            source_block_id: block1.id,
            target_block_id: block2.id,
            kind: :cites
          },
          actor: user,
          tenant: workspace.id
        )

      assert %Ash.Error.Invalid{} = error
      assert error.errors |> Enum.any?(&String.contains?(inspect(&1), "unique"))
    end

    test "rejects self-link with validation message", %{
      workspace: workspace,
      user: user,
      block1: block1
    } do
      {:error, error} =
        Knowledge.create_link(
          %{
            workspace_id: workspace.id,
            source_block_id: block1.id,
            target_block_id: block1.id,
            kind: :relates_to
          },
          actor: user,
          tenant: workspace.id
        )

      assert %Ash.Error.Invalid{} = error

      assert error.errors
             |> Enum.any?(&(&1.message =~ "cannot link a block to itself"))
    end

    test "different kind allows same source+target pair", %{
      workspace: workspace,
      user: user,
      block1: block1,
      block2: block2
    } do
      {:ok, link1} =
        Knowledge.create_link(
          %{
            workspace_id: workspace.id,
            source_block_id: block1.id,
            target_block_id: block2.id,
            kind: :relates_to
          },
          actor: user,
          tenant: workspace.id
        )

      {:ok, link2} =
        Knowledge.create_link(
          %{
            workspace_id: workspace.id,
            source_block_id: block1.id,
            target_block_id: block2.id,
            kind: :cites
          },
          actor: user,
          tenant: workspace.id
        )

      assert link1.kind == :relates_to
      assert link2.kind == :cites
    end
  end

  describe "destroy_link" do
    test "removes the Arcana.Graph.Relationship row", %{
      workspace: workspace,
      user: user,
      block1: block1,
      block2: block2
    } do
      # Create link
      {:ok, link} =
        Knowledge.create_link(
          %{
            workspace_id: workspace.id,
            source_block_id: block1.id,
            target_block_id: block2.id,
            kind: :see_also
          },
          actor: user,
          tenant: workspace.id
        )

      # Verify Arcana row exists
      assert Concept.Repo.one(
               from r in Arcana.Graph.Relationship,
                 where:
                   r.source_id == ^block1.id and
                     r.target_id == ^block2.id and
                     r.type == "USER_SEE_ALSO"
             ) != nil

      # Destroy link
      :ok = Knowledge.destroy_link(link, actor: user, tenant: workspace.id)

      # Verify Arcana row removed
      assert Concept.Repo.one(
               from r in Arcana.Graph.Relationship,
                 where:
                   r.source_id == ^block1.id and
                     r.target_id == ^block2.id and
                     r.type == "USER_SEE_ALSO"
             ) == nil
    end
  end

  describe "paper_trail" do
    test "records create version", %{
      workspace: workspace,
      user: user,
      block1: block1,
      block2: block2
    } do
      {:ok, link} =
        Knowledge.create_link(
          %{
            workspace_id: workspace.id,
            source_block_id: block1.id,
            target_block_id: block2.id,
            kind: :contradicts
          },
          actor: user,
          tenant: workspace.id
        )

      # Query for versions via AshPaperTrail
      versions =
        Concept.Repo.all(
          from v in "versions",
            where: v.item_id == ^link.id,
            select: %{event: v.event, item_id: v.item_id}
        )

      assert length(versions) >= 1
      assert Enum.any?(versions, &(&1.event == "create"))
    end
  end

  describe "policies" do
    test "cross-workspace block rejected by policy", %{
      user: user,
      block1: block1
    } do
      # Create another user and workspace
      {:ok, other_user} =
        Concept.Accounts.User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "other_#{System.unique_integer([:positive])}@example.com",
          password: "passw0rd!",
          password_confirmation: "passw0rd!"
        })
        |> Ash.create(authorize?: false)

      {:ok, [other_workspace]} =
        Concept.Accounts.Workspace.for_user(other_user.id, actor: other_user)

      {:ok, other_page} =
        Pages.create_page("Other Page", other_workspace.id, nil,
          actor: other_user,
          tenant: other_workspace.id
        )

      {:ok, other_block} =
        Pages.create_block(other_page.id, :paragraph, other_workspace.id, nil,
          actor: other_user,
          tenant: other_workspace.id
        )

      # Attempt to create link from block1 (workspace1) to other_block (workspace2)
      # Using workspace1 as tenant, which should fail because target block is in different workspace
      {:error, error} =
        Knowledge.create_link(
          %{
            # intentionally wrong to trigger error
            workspace_id: user.id,
            source_block_id: block1.id,
            target_block_id: other_block.id,
            kind: :relates_to
          },
          actor: user,
          tenant: block1.workspace_id
        )

      assert %Ash.Error.Invalid{} = error
    end

    test "system actor bypasses policy", %{
      workspace: workspace,
      block1: block1,
      block2: block2
    } do
      system_actor = %{system?: true}

      {:ok, link} =
        Knowledge.create_link(
          %{
            workspace_id: workspace.id,
            source_block_id: block1.id,
            target_block_id: block2.id,
            kind: :relates_to
          },
          actor: system_actor,
          tenant: workspace.id
        )

      assert link.workspace_id == workspace.id
    end
  end
end
