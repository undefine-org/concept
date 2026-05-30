defmodule Concept.Knowledge.Chat.ScenarioTest do
  @moduledoc """
  PLAN-010 end-to-end proof: the real use cases of the conversation substrate,
  exercised as one narrative. Each step maps to a user-facing capability and a
  design section in docs/messaging_design.md.

  This is the "show me it works" test: it drives the SAME domain code-interface
  functions the LiveView and the MCP tools call — so a green run proves both the
  human projection and the agent projection of every feature.
  """
  use Concept.DataCase, async: true
  require Ash.Query

  alias Concept.Knowledge.Chat
  alias Concept.Pages

  defp register(prefix) do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "#{prefix}-#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    {:ok, [ws | _]} = Concept.Accounts.Workspace.for_user(user.id, actor: user)
    {user, ws}
  end

  test "the full Concept conversation story" do
    # ── Cast ──────────────────────────────────────────────────────────────
    {maya, ws} = register("maya")

    # A page exists — it will be the HOST of a conversation (the keystone:
    # you talk to a thing, and the thing is grounded in itself).
    {:ok, roadmap} =
      Pages.create_page("Q3 Roadmap", ws.id, nil, actor: maya, tenant: ws.id)

    # ── USE CASE 1: Talk TO a page (host addressing) ───────────────────────
    # Maya opens the Q3 Roadmap and asks a question about it. No conversation
    # exists yet → one is find-or-created, hosted by the page. (design §10-11)
    {:ok, m1} =
      Chat.create_message(
        %{text: "Should offline mode ship in Q3?", host_type: :page, host_id: roadmap.id},
        actor: maya,
        tenant: ws.id
      )

    {:ok, [convo]} = Chat.conversations_for_host(:page, roadmap.id, actor: maya, tenant: ws.id)
    assert convo.host_type == :page
    assert convo.host_id == roadmap.id

    # USE CASE 1b: sending auto-joins Maya as a Participant (identity), which is
    # the unread cursor that powers her inbox. (design §39)
    {:ok, participants} = Chat.participants_for_conversation(convo.id, actor: maya, tenant: ws.id)
    assert length(participants) == 1

    # ── USE CASE 2: A message carries real Blocks, not just text ───────────
    # Maya attaches a code block to her message — talk has the editor's full
    # expressiveness (the content membrane). (design §27)
    {:ok, code_block} =
      Pages.Block
      |> Ash.Changeset.for_create(
        :create_block,
        %{
          message_id: m1.id,
          type: :code,
          content: %{"text" => "config :offline, enabled: true"},
          workspace_id: ws.id
        },
        actor: maya,
        tenant: ws.id
      )
      |> Ash.create()

    assert code_block.message_id == m1.id
    assert is_nil(code_block.page_id)
    # …and a block lives under exactly one container (page XOR message).
    {:ok, msg_blocks} = Pages.list_for_message(m1.id, actor: maya, tenant: ws.id)
    assert Enum.map(msg_blocks, & &1.id) == [code_block.id]

    # ── USE CASE 3: Spawn a focused thread from a message ──────────────────
    # The "competitor comparison" tangent becomes a child conversation,
    # inheriting the page host + lineage. (design §13)
    {:ok, reply} =
      Chat.create_message(
        %{text: "How do competitors handle offline?", reply_to_message_id: m1.id},
        actor: maya,
        tenant: ws.id
      )

    {:ok, thread} = Chat.get_conversation(reply.conversation_id, actor: maya, tenant: ws.id)
    assert thread.parent_conversation_id == convo.id
    assert thread.seed_message_id == m1.id
    assert thread.host_type == :page and thread.host_id == roadmap.id

    # ── USE CASE 4: Conversation activity reaches Maya's inbox ─────────────
    # The inbox is a projection over participation — every conversation she's in.
    # (design §A)
    {:ok, inbox} = Chat.inbox(actor: maya, tenant: ws.id)
    inbox_ids = Enum.map(inbox, & &1.id)
    assert convo.id in inbox_ids
    assert thread.id in inbox_ids

    # ── USE CASE 5: Agent-turn budget bounds runaway automation ────────────
    # Each automatic host/agent turn consumes budget; exhausting it stops the
    # respond trigger until a human re-engages. (design §B)
    {:ok, fresh} = Chat.get_conversation(convo.id, actor: maya, tenant: ws.id)
    assert fresh.agent_turn_budget == 5

    # A host-addressed message is created FIRST (while budget is healthy), then
    # the conversation's budget is drained to 0. We re-load THIS message's
    # `needs_host_response` afterwards — no new human post intervenes, so no
    # replenish fires. This isolates the budget gate: an exhausted conversation
    # owes no automatic response. (A human re-engaging WOULD replenish and lift
    # the cap by design §B — humans always get answered; the gate bounds only
    # unattended agent loops, which is exactly what this asserts.)
    {:ok, gated} =
      Chat.create_message(
        %{
          text: "@page anything else?",
          host_type: :page,
          host_id: roadmap.id,
          addresses_host: true
        },
        actor: maya,
        tenant: ws.id
      )

    # While budget > 0, the response IS owed.
    {:ok, owed} = Ash.load(gated, [:needs_host_response], actor: maya, tenant: ws.id)
    assert owed.needs_host_response

    drained =
      Enum.reduce(1..5, fresh, fn _i, c ->
        {:ok, c} = Chat.decrement_budget(c, actor: maya, tenant: ws.id)
        c
      end)

    assert drained.agent_turn_budget == 0

    # Now the budget is spent and no human re-engaged → the same message owes
    # NO automatic response. The agent loop halts. (design §B). Re-fetch the
    # message fresh so the `conversation.agent_turn_budget` calc sees the
    # drained DB value rather than a preloaded relationship.
    {:ok, budget_check} = Chat.get_conversation(convo.id, actor: maya, tenant: ws.id)
    assert budget_check.agent_turn_budget == 0

    {:ok, halted} =
      Chat.get_message(gated.id, actor: maya, tenant: ws.id)
      |> then(fn {:ok, msg} ->
        Ash.load(msg, [:needs_host_response], actor: maya, tenant: ws.id)
      end)

    refute halted.needs_host_response

    # ── USE CASE 6: Human↔human messages do NOT summon the AI ──────────────
    # The old reflex is dead: a plain message (addresses_host: false) owes no
    # response. (design §4)
    {:ok, chitchat} =
      Chat.create_message(
        %{text: "nice, thanks!", host_type: :workspace, addresses_host: false},
        actor: maya,
        tenant: ws.id
      )

    {:ok, chitchat} = Ash.load(chitchat, [:needs_host_response], actor: maya, tenant: ws.id)
    refute chitchat.needs_host_response

    # ── USE CASE 7: Crystallize the decision into the page ─────────────────
    # The conversation's blocks are cloned onto the host page with provenance;
    # talk becomes durable document. (design §20, §46)
    {:ok, _cloned_ids} =
      Chat.crystallize_conversation(convo.id, roadmap.id, ws.id, actor: maya, tenant: ws.id)

    {:ok, page_blocks} = Pages.list_for_page(roadmap.id, actor: maya, tenant: ws.id)
    assert Enum.any?(page_blocks, &(&1.content["text"] == "config :offline, enabled: true"))

    {:ok, crystallized} = Chat.get_conversation(convo.id, actor: maya, tenant: ws.id)
    assert crystallized.crystallized_page_id == roadmap.id

    # Provenance link source(message-block) → clone(page-block) exists.
    {:ok, links} =
      Concept.Knowledge.Link
      |> Ash.Query.filter(source_block_id == ^code_block.id and kind == :crystallized_from)
      |> Ash.read(actor: maya, tenant: ws.id)

    assert length(links) == 1

    # The source message block is UNTOUCHED — copy, not move (scrollback intact).
    {:ok, still_there} = Ash.get(Pages.Block, code_block.id, actor: maya, tenant: ws.id)
    assert still_there.message_id == m1.id
  end

  test "tenancy: an outsider cannot read another workspace's conversation" do
    {owner, ws} = register("owner")
    {outsider, _other_ws} = register("outsider")

    {:ok, m} =
      Chat.create_message(%{text: "secret", addresses_host: false}, actor: owner, tenant: ws.id)

    assert {:error, _} = Chat.get_conversation(m.conversation_id, actor: outsider, tenant: ws.id)
  end
end
