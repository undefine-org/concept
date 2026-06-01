defmodule Concept.Pages.BlockContainerPropertyTest do
  @moduledoc """
  Property: every persisted Block satisfies the container invariant

      ∀ block:  container_id ≠ nil  ∧  container_type ∈ Concept.Containable.types()

  This is the schema-level truth the Container cutover establishes. We fuzz
  block creation across both registered container types (page, message) and a
  range of block types, asserting the invariant holds on every persisted row —
  and that an *unregistered* container type is always rejected, never stored.

  Uses StreamData via a single shared workspace (created once) so the property
  runs many generated cases without per-case onboarding cost; each created
  block is asserted then archived-irrelevant (we only read attributes).
  """
  use Concept.DataCase, async: false
  use ExUnitProperties

  alias Concept.{Containable, Pages}
  alias Concept.Knowledge.Chat

  setup do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "block-prop-#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    {:ok, [ws | _]} = Concept.Accounts.Workspace.for_user(user.id, actor: user)
    {:ok, page} = Pages.create_page("Prop", ws.id, nil, actor: user, tenant: ws.id)
    {:ok, _conv} = Chat.create_conversation(%{workspace_id: ws.id}, actor: user, tenant: ws.id)

    {:ok, msg} =
      Chat.create_message(%{text: "m", addresses_host: false}, actor: user, tenant: ws.id)

    %{user: user, ws: ws, page: page, msg: msg}
  end

  # Block types safe to create with empty content/props in any container.
  @block_types [:paragraph, :heading_1, :heading_2, :quote, :bulleted_list_item, :to_do]

  property "every created block satisfies the container invariant", %{
    user: u,
    ws: ws,
    page: page,
    msg: msg
  } do
    container_gen =
      StreamData.member_of([{:page, page.id}, {:message, msg.id}])

    type_gen = StreamData.member_of(@block_types)

    check all(
            {ctype, cid} <- container_gen,
            btype <- type_gen,
            max_runs: 40
          ) do
      {:ok, block} =
        Pages.create_block(ctype, cid, btype, ws.id, nil, actor: u, tenant: ws.id)

      # The invariant, on the persisted row.
      assert block.container_id == cid
      assert block.container_type == ctype
      assert block.container_type in Containable.types()
      refute is_nil(block.container_id)
    end
  end

  property "an unregistered container type is never persisted", %{user: u, ws: ws} do
    # Atoms that are NOT registered container types must be rejected at write.
    # (`:record` joined the registry in D1 — it is a real container now.)
    bogus_gen = StreamData.member_of([:workspace, :conversation, :user, :object_type])

    check all(bogus <- bogus_gen, max_runs: 10) do
      result =
        Pages.create_block(bogus, Ash.UUID.generate(), :paragraph, ws.id, nil,
          actor: u,
          tenant: ws.id
        )

      assert match?({:error, _}, result),
             "container_type #{inspect(bogus)} must be rejected, got #{inspect(result)}"
    end
  end
end
