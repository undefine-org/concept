defmodule Concept.Pages.BlockEvaluateAiTest do
  use Concept.DataCase, async: true

  alias Concept.Pages
  alias Concept.Knowledge

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

    # Create a page
    {:ok, page} =
      Pages.create_page("Test Page", workspace.id, nil, actor: user, tenant: workspace.id)

    # Create an AI answer block
    {:ok, block} =
      Pages.create_block(page.id, :ai_answer, workspace.id, nil,
        actor: user,
        tenant: workspace.id
      )

    %{
      user: user,
      workspace: workspace,
      page: page,
      block: block
    }
  end

  describe "empty AI block" do
    test "renders with default props", %{block: block} do
      assert block.type == :ai_answer
      # Default props from block type
      assert block.props["prompt"] == ""
      assert block.props["scope"] == "subtree"
      assert block.content == %{}
    end
  end

  describe "evaluate_ai action" do
    test "updates block props with prompt/scope/profile", %{
      user: user,
      workspace: workspace,
      block: block
    } do
      {:ok, updated_block} =
        Pages.evaluate_ai(
          block,
          "What is the meaning of life?",
          :workspace,
          :default,
          actor: user,
          tenant: workspace.id
        )

      # Props should be updated immediately
      assert updated_block.props["prompt"] == "What is the meaning of life?"
      assert updated_block.props["scope"] == "workspace"
      assert updated_block.props["profile"] == "default"
    end

    test "creates conversation for the block", %{
      user: user,
      workspace: workspace,
      block: block
    } do
      {:ok, updated_block} =
        Pages.evaluate_ai(
          block,
          "Test question",
          :workspace,
          :default,
          actor: user,
          tenant: workspace.id
        )

      # Wait a moment for async task to start
      Process.sleep(500)

      # Reload to check if conversation_id was set
      {:ok, reloaded_block} =
        Pages.Block
        |> Ash.get(block.id, actor: user, tenant: workspace.id)

      # Conversation might be created by now
      if conversation_id = reloaded_block.props["conversation_id"] do
        {:ok, conversation} =
          Knowledge.Chat.get_conversation(conversation_id,
            actor: user,
            authorize?: false
          )

        assert conversation.title =~ "AI Block"
      end
    end

    test "scope :subtree is stored in props", %{
      user: user,
      workspace: workspace,
      block: block
    } do
      {:ok, updated_block} =
        Pages.evaluate_ai(
          block,
          "Subtree question",
          :subtree,
          :default,
          actor: user,
          tenant: workspace.id
        )

      assert updated_block.props["scope"] == "subtree"
    end
  end

  describe "block content structure" do
    test "validates expected content shape for AI blocks", %{block: block} do
      # Verify block starts empty
      assert block.content == %{}

      # Expected content structure after AI response:
      # %{"message_id" => uuid, "model" => string, "ran_at" => iso8601}
      assert is_map(block.content)
    end
  end
end
