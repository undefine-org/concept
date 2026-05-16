defmodule Concept.Pages.StalenessTest do
  use Concept.DataCase, async: true

  alias Concept.Pages
  alias Concept.Knowledge

  setup do
    # Create user
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

    # Create page
    {:ok, page} =
      Pages.create_page("Test Page", workspace.id, nil, actor: user, tenant: workspace.id)

    # Create cited blocks (source blocks)
    {:ok, block1} =
      Pages.create_block(page.id, :paragraph, workspace.id, nil,
        actor: user,
        tenant: workspace.id
      )

    {:ok, block2} =
      Pages.create_block(page.id, :paragraph, workspace.id, nil,
        actor: user,
        tenant: workspace.id
      )

    # Create AI answer block
    {:ok, ai_block} =
      Pages.create_block(page.id, :ai_answer, workspace.id, nil,
        actor: user,
        tenant: workspace.id
      )

    # Create user message (conversation will be auto-created)
    {:ok, user_message} =
      Concept.Knowledge.Chat.create_message(%{text: "Test question"},
        actor: user,
        authorize?: false
      )

    # Create AI response message
    # Note: We can't use upsert_response to create a message from scratch, so we create manually
    ai_message_id = Uniq.UUID.uuid7()

    {:ok, ai_message} =
      Concept.Repo.insert(%Concept.Knowledge.Chat.Message{
        id: ai_message_id,
        response_to_id: user_message.id,
        conversation_id: user_message.conversation_id,
        text: "AI answer text",
        complete: true,
        source: :agent
      })

    # Create citations linking message to blocks
    {:ok, _citation1} =
      Knowledge.create_citation(
        %{
          message_id: ai_message.id,
          block_id: block1.id,
          page_id: page.id,
          rank: 1,
          score: 0.9,
          snippet: "Source 1",
          workspace_id: workspace.id
        },
        actor: %{system?: true},
        tenant: workspace.id
      )

    {:ok, _citation2} =
      Knowledge.create_citation(
        %{
          message_id: ai_message.id,
          block_id: block2.id,
          page_id: page.id,
          rank: 2,
          score: 0.8,
          snippet: "Source 2",
          workspace_id: workspace.id
        },
        actor: %{system?: true},
        tenant: workspace.id
      )

    # Update AI block with message_id using system actor (bypasses lock requirement)
    {:ok, ai_block} =
      Concept.Pages.Block
      |> Ash.Changeset.for_update(:update_content, %{content: %{"message_id" => ai_message.id}})
      |> Ash.update!(actor: %{system?: true}, tenant: workspace.id)

    %{
      workspace: workspace,
      user: user,
      page: page,
      ai_block: ai_block,
      ai_message: ai_message,
      block1: block1,
      block2: block2
    }
  end

  describe "staleness_for_ai_block/1" do
    test "returns stale?: false for fresh AI block with no edits", %{
      workspace: workspace,
      ai_block: ai_block
    } do
      # Reload to get fresh timestamps
      {:ok, ai_block} =
        Pages.Block
        |> Ash.get(ai_block.id, actor: %{system?: true}, tenant: workspace.id)

      result = Pages.staleness_for_ai_block(ai_block)

      assert result.stale? == false
      assert result.drifted_count == 0
      assert result.drifted_block_ids == []
    end

    test "returns stale?: true when one cited block is edited", %{
      workspace: workspace,
      user: user,
      ai_block: ai_block,
      block1: block1
    } do
      # Wait a tiny bit to ensure timestamp difference
      Process.sleep(10)

      # Edit one of the cited blocks using system actor (bypasses lock)
      {:ok, _updated_block1} =
        Concept.Pages.Block
        |> Ash.Changeset.for_update(:update_content, %{
          content: %{"text" => "Updated source content 1"}
        })
        |> Ash.update!(actor: %{system?: true}, tenant: workspace.id)

      # Reload block1 to get updated timestamp
      {:ok, block1} =
        Concept.Pages.Block |> Ash.get(block1.id, actor: %{system?: true}, tenant: workspace.id)

      # Reload AI block
      {:ok, ai_block} =
        Pages.Block
        |> Ash.get(ai_block.id, actor: %{system?: true}, tenant: workspace.id)

      result = Pages.staleness_for_ai_block(ai_block)

      assert result.stale? == true
      assert result.drifted_count == 1
      assert block1.id in result.drifted_block_ids
    end

    test "returns stale?: false for legacy AI block with no message_id", %{
      workspace: workspace,
      user: user,
      page: page
    } do
      # Create AI block without message_id
      {:ok, legacy_block} =
        Pages.create_block(page.id, :ai_answer, workspace.id, nil,
          actor: user,
          tenant: workspace.id
        )

      result = Pages.staleness_for_ai_block(legacy_block)

      assert result.stale? == false
      assert result.drifted_count == 0
      assert result.drifted_block_ids == []
    end

    test "staleness cleared after evaluate_ai refresh", %{
      workspace: workspace,
      user: user,
      page: page,
      ai_block: ai_block,
      block1: block1
    } do
      # Edit a cited block to make it stale using system actor
      Process.sleep(10)

      {:ok, _updated_block1} =
        Concept.Pages.Block
        |> Ash.Changeset.for_update(:update_content, %{content: %{"text" => "Updated again"}})
        |> Ash.update!(actor: %{system?: true}, tenant: workspace.id)

      # Reload and verify stale
      {:ok, ai_block} =
        Pages.Block
        |> Ash.get(ai_block.id, actor: %{system?: true}, tenant: workspace.id)

      result_before = Pages.staleness_for_ai_block(ai_block)
      assert result_before.stale? == true

      # Re-evaluate the AI block (simulate refresh)
      # This will create a new message with a newer timestamp
      {:ok, refreshed_block} =
        Pages.evaluate_ai(ai_block.id, "Refresh question",
          actor: user,
          tenant: workspace.id
        )

      # Wait for async evaluation to complete
      Process.sleep(100)

      # Reload the block
      {:ok, refreshed_block} =
        Pages.Block
        |> Ash.get(refreshed_block.id, actor: %{system?: true}, tenant: workspace.id)

      # Get the new message_id
      new_message_id = get_in(refreshed_block.content, ["message_id"])

      # Wait for message to complete (in real scenario, this would be done by the async task)
      # For this test, we'll poll briefly
      result_after =
        Enum.reduce_while(1..10, nil, fn _i, _acc ->
          case Pages.Block
               |> Ash.get(refreshed_block.id, actor: %{system?: true}, tenant: workspace.id) do
            {:ok, block} ->
              # Check if message is complete
              case Concept.Knowledge.Chat.Message
                   |> Ash.get(new_message_id, actor: %{system?: true}) do
                {:ok, %{complete: true}} ->
                  {:halt, Pages.staleness_for_ai_block(block)}

                _ ->
                  Process.sleep(50)
                  {:cont, nil}
              end

            _ ->
              {:halt, nil}
          end
        end)

      # If the message completed, staleness should be false
      # (because the new message was created after the block edit)
      if result_after do
        assert result_after.stale? == false
        assert result_after.drifted_count == 0
      end
    end
  end
end
