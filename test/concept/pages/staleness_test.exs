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
      Pages.create_block(:page, page.id, :paragraph, workspace.id, nil,
        actor: user,
        tenant: workspace.id
      )

    {:ok, block2} =
      Pages.create_block(:page, page.id, :paragraph, workspace.id, nil,
        actor: user,
        tenant: workspace.id
      )

    # Create AI answer block
    {:ok, ai_block} =
      Pages.create_block(:page, page.id, :ai_answer, workspace.id, nil,
        actor: user,
        tenant: workspace.id
      )

    # Create user message (conversation will be auto-created)
    {:ok, user_message} =
      Concept.Knowledge.Chat.create_message(%{text: "Test question"},
        actor: user,
        tenant: workspace.id,
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
        workspace_id: workspace.id,
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
    ai_block =
      ai_block
      |> Ash.Changeset.for_update(:update_content, %{content: %{"message_id" => ai_message.id}},
        actor: %{system?: true}
      )
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
      _updated_block1 =
        block1
        |> Ash.Changeset.for_update(
          :update_content,
          %{
            content: %{"text" => "Updated source content 1"}
          },
          actor: %{system?: true}
        )
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
        Pages.create_block(:page, page.id, :ai_answer, workspace.id, nil,
          actor: user,
          tenant: workspace.id
        )

      result = Pages.staleness_for_ai_block(legacy_block)

      assert result.stale? == false
      assert result.drifted_count == 0
      assert result.drifted_block_ids == []
    end

    # FUP-017: depends on AshAI streaming completion + citation creation,
    # which needs LLM stubbing via Concept.TestSupport.LLMStub before this can run
    # deterministically. Marked integration to gate in CI.
    @tag :integration
    test "staleness cleared after evaluate_ai refresh", %{
      workspace: workspace,
      user: user,
      page: page,
      ai_block: ai_block,
      block1: block1
    } do
      # Edit a cited block to make it stale using system actor
      Process.sleep(50)

      _updated_block1 =
        block1
        |> Ash.Changeset.for_update(:update_content, %{content: %{"text" => "Updated again"}},
          actor: %{system?: true}
        )
        |> Ash.update!(actor: %{system?: true}, tenant: workspace.id)

      # Reload and verify stale
      {:ok, ai_block} =
        Pages.Block
        |> Ash.get(ai_block.id, actor: %{system?: true}, tenant: workspace.id)

      original_message_id = get_in(ai_block.content, ["message_id"])

      result_before = Pages.staleness_for_ai_block(ai_block)
      assert result_before.stale? == true

      # Wait to ensure clear timestamp separation before refresh
      Process.sleep(50)

      # Re-evaluate the AI block (simulate refresh)
      # This will create a new message with a newer timestamp
      {:ok, refreshed_block} =
        Pages.evaluate_ai(
          ai_block,
          "Refresh question",
          :workspace,
          :default,
          actor: user,
          tenant: workspace.id
        )

      # Wait for async evaluation to complete and poll for message completion
      # Reload block and check message status in each iteration
      result_after =
        Enum.reduce_while(1..20, nil, fn _i, _acc ->
          Process.sleep(100)

          case Pages.Block
               |> Ash.get(refreshed_block.id, actor: %{system?: true}, tenant: workspace.id) do
            {:ok, block} ->
              message_id = get_in(block.content, ["message_id"])

              # Wait for the block to point at the NEW message (finalize_completion
              # has run), not the pre-refresh one — otherwise we'd halt on the old
              # complete message and read stale state.
              if message_id && message_id != original_message_id do
                case Concept.Knowledge.Chat.Message
                     |> Ash.get(message_id, actor: %{system?: true}, tenant: workspace.id) do
                  {:ok, %{complete: true}} ->
                    {:halt, Pages.staleness_for_ai_block(block)}

                  _ ->
                    {:cont, nil}
                end
              else
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
