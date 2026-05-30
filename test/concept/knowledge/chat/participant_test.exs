defmodule Concept.Knowledge.Chat.ParticipantTest do
  @moduledoc """
  Wave 1 (FEAT-076): Participants are identities (Membership × Conversation);
  the host is a voice, not a participant. Addressed-response replaces the
  every-message-summons-AI reflex.
  """
  use Concept.DataCase, async: true
  require Ash.Query
  require Ash.Query

  alias Concept.Knowledge.Chat

  setup do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "participant-#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    {:ok, [workspace | _]} = Concept.Accounts.Workspace.for_user(user.id, actor: user)

    {:ok, membership} =
      Concept.Accounts.Membership
      |> Ash.Query.filter(workspace_id == ^workspace.id and user_id == ^user.id)
      |> Ash.read_one(authorize?: false)

    {:ok, conversation} =
      Chat.create_conversation(%{workspace_id: workspace.id}, actor: user, tenant: workspace.id)

    %{user: user, workspace: workspace, membership: membership, conversation: conversation}
  end

  describe "Participant = Membership × Conversation (identity)" do
    test "join adds a member; kind is derived from membership role", ctx do
      %{user: u, workspace: ws, membership: m, conversation: conv} = ctx

      {:ok, p} =
        Chat.join_conversation(
          %{workspace_id: ws.id, conversation_id: conv.id, membership_id: m.id},
          actor: u,
          tenant: ws.id
        )

      {:ok, loaded} = Ash.load(p, [:kind], actor: u, tenant: ws.id)
      # role :member → identity kind :user
      assert loaded.kind == :user
    end

    test "join is idempotent per (conversation, membership)", ctx do
      %{user: u, workspace: ws, membership: m, conversation: conv} = ctx

      join = fn ->
        Chat.join_conversation!(
          %{workspace_id: ws.id, conversation_id: conv.id, membership_id: m.id},
          actor: u,
          tenant: ws.id
        )
      end

      p1 = join.()
      p2 = join.()
      assert p1.id == p2.id

      {:ok, participants} = Chat.participants_for_conversation(conv.id, actor: u, tenant: ws.id)
      assert length(participants) == 1
    end

    test "mark_read advances the unread cursor (the inbox primitive)", ctx do
      %{user: u, workspace: ws, membership: m, conversation: conv} = ctx

      p =
        Chat.join_conversation!(
          %{workspace_id: ws.id, conversation_id: conv.id, membership_id: m.id},
          actor: u,
          tenant: ws.id
        )

      msg_id = Ash.UUIDv7.generate()

      {:ok, updated} =
        Chat.mark_participant_read(p, %{last_read_message_id: msg_id}, actor: u, tenant: ws.id)

      assert updated.last_read_message_id == msg_id
    end
  end

  describe "sender auto-join (inbox precondition)" do
    test "sending a message joins the sender as a participant", ctx do
      %{user: u, workspace: ws} = ctx

      {:ok, msg} =
        Chat.create_message(%{text: "hello", addresses_host: false}, actor: u, tenant: ws.id)

      {:ok, participants} =
        Chat.participants_for_conversation(msg.conversation_id, actor: u, tenant: ws.id)

      assert length(participants) == 1
      {:ok, [p]} = {:ok, participants}
      {:ok, loaded} = Ash.load(p, [:membership], actor: u, tenant: ws.id)
      assert loaded.membership.user_id == u.id
    end

    test "sending twice keeps a single participant (idempotent)", ctx do
      %{user: u, workspace: ws} = ctx

      {:ok, m1} =
        Chat.create_message(%{text: "one", addresses_host: false}, actor: u, tenant: ws.id)

      {:ok, _m2} =
        Chat.create_message(%{text: "two", conversation_id: m1.conversation_id, addresses_host: false},
          actor: u,
          tenant: ws.id
        )

      {:ok, participants} =
        Chat.participants_for_conversation(m1.conversation_id, actor: u, tenant: ws.id)

      assert length(participants) == 1
    end
  end

  describe "addressed response (the reflex is dead)" do
    test "a message addressing the host owes a response", ctx do
      %{user: u, workspace: ws, conversation: conv} = ctx

      {:ok, msg} =
        Chat.create_message(%{text: "hey @page", addresses_host: true},
          actor: u,
          tenant: ws.id
        )
        |> then(fn {:ok, m} ->
          Ash.load(m, [:needs_host_response], actor: u, tenant: ws.id)
        end)

      assert msg.needs_host_response == true
      # silence unused
      _ = conv
    end

    test "a human-to-human message (addresses_host: false) owes NO response", ctx do
      %{user: u, workspace: ws} = ctx

      {:ok, msg} =
        Chat.create_message(%{text: "just chatting with Leo", addresses_host: false},
          actor: u,
          tenant: ws.id
        )

      {:ok, loaded} = Ash.load(msg, [:needs_host_response], actor: u, tenant: ws.id)
      assert loaded.needs_host_response == false
    end
  end
end
