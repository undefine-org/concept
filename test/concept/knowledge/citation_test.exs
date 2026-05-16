defmodule Concept.Knowledge.CitationTest do
  use Concept.DataCase, async: true

  alias Concept.Knowledge
  alias Concept.Pages

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

    # Create a page and block
    {:ok, page} =
      Pages.create_page("Test Page", workspace.id, nil, actor: user, tenant: workspace.id)

    {:ok, block} =
      Pages.create_block(page.id, :paragraph, workspace.id, nil,
        actor: user,
        tenant: workspace.id
      )

    # Create a message (conversation will be auto-created)
    {:ok, message} =
      Concept.Knowledge.Chat.create_message(%{text: "Test message"},
        actor: user,
        authorize?: false
      )

    # System actor for creating citations
    system_actor = %{system?: true}

    %{
      user: user,
      workspace: workspace,
      page: page,
      block: block,
      message: message,
      system_actor: system_actor
    }
  end

  describe "create_citation" do
    test "creates a citation with valid attributes", %{
      workspace: workspace,
      message: message,
      block: block,
      page: page,
      system_actor: system_actor
    } do
      {:ok, citation} =
        Knowledge.create_citation(
          %{
            workspace_id: workspace.id,
            message_id: message.id,
            block_id: block.id,
            page_id: page.id,
            rank: 1,
            score: 0.95,
            snippet: "Test snippet",
            breadcrumbs: "Test Page"
          },
          actor: system_actor,
          tenant: workspace.id
        )

      assert citation.workspace_id == workspace.id
      assert citation.message_id == message.id
      assert citation.block_id == block.id
      assert citation.page_id == page.id
      assert citation.rank == 1
      assert citation.score == 0.95
      assert citation.snippet == "Test snippet"
      assert citation.breadcrumbs == "Test Page"
    end

    test "raises error when message_id is missing", %{
      workspace: workspace,
      block: block,
      page: page,
      system_actor: system_actor
    } do
      assert {:error, %Ash.Error.Invalid{}} =
               Knowledge.create_citation(
                 %{
                   workspace_id: workspace.id,
                   block_id: block.id,
                   page_id: page.id,
                   rank: 1
                 },
                 actor: system_actor,
                 tenant: workspace.id
               )
    end

    test "rejects score outside [0.0, 1.0] range", %{
      workspace: workspace,
      message: message,
      block: block,
      page: page,
      system_actor: system_actor
    } do
      # Test score > 1.0
      assert {:error, %Ash.Error.Invalid{}} =
               Knowledge.create_citation(
                 %{
                   workspace_id: workspace.id,
                   message_id: message.id,
                   block_id: block.id,
                   page_id: page.id,
                   rank: 1,
                   score: 1.5
                 },
                 actor: system_actor,
                 tenant: workspace.id
               )

      # Test score < 0.0
      assert {:error, %Ash.Error.Invalid{}} =
               Knowledge.create_citation(
                 %{
                   workspace_id: workspace.id,
                   message_id: message.id,
                   block_id: block.id,
                   page_id: page.id,
                   rank: 1,
                   score: -0.1
                 },
                 actor: system_actor,
                 tenant: workspace.id
               )
    end
  end

  describe "citations_for_message" do
    test "returns citations sorted by rank ascending", %{
      workspace: workspace,
      message: message,
      block: block,
      page: page,
      system_actor: system_actor
    } do
      # Create three citations with ranks [3, 1, 2]
      {:ok, _citation3} =
        Knowledge.create_citation(
          %{
            workspace_id: workspace.id,
            message_id: message.id,
            block_id: block.id,
            page_id: page.id,
            rank: 3
          },
          actor: system_actor,
          tenant: workspace.id
        )

      {:ok, _citation1} =
        Knowledge.create_citation(
          %{
            workspace_id: workspace.id,
            message_id: message.id,
            block_id: block.id,
            page_id: page.id,
            rank: 1
          },
          actor: system_actor,
          tenant: workspace.id
        )

      {:ok, _citation2} =
        Knowledge.create_citation(
          %{
            workspace_id: workspace.id,
            message_id: message.id,
            block_id: block.id,
            page_id: page.id,
            rank: 2
          },
          actor: system_actor,
          tenant: workspace.id
        )

      # Query citations for message
      {:ok, citations} =
        Knowledge.citations_for_message(message.id,
          actor: system_actor,
          tenant: workspace.id
        )

      # Verify order: [1, 2, 3]
      ranks = Enum.map(citations, & &1.rank)
      assert ranks == [1, 2, 3]
    end
  end

  describe "policy checks" do
    test "non-member cannot read citations", %{
      workspace: workspace,
      message: message,
      block: block,
      page: page,
      system_actor: system_actor
    } do
      # Create a citation
      {:ok, _citation} =
        Knowledge.create_citation(
          %{
            workspace_id: workspace.id,
            message_id: message.id,
            block_id: block.id,
            page_id: page.id,
            rank: 1
          },
          actor: system_actor,
          tenant: workspace.id
        )

      # Create another user who is not a member
      {:ok, other_user} =
        Concept.Accounts.User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "other_#{System.unique_integer([:positive])}@example.com",
          password: "passw0rd!",
          password_confirmation: "passw0rd!"
        })
        |> Ash.create(authorize?: false)

      # Attempt to read citations as non-member
      # The policy check succeeds but multitenancy filtering returns empty results
      assert {:ok, []} =
               Knowledge.citations_for_message(message.id,
                 actor: other_user,
                 tenant: workspace.id
               )
    end
  end
end
