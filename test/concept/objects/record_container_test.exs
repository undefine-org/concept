defmodule Concept.Objects.RecordContainerTest do
  @moduledoc """
  D1 — Record's detail body as the third block container. Proves the
  `Containable` primitive generalizes: a Record *owns* a block tree
  (`container_type: :record`) without any schema change, while its `page_id`
  *reference* (the project seam) stays a distinct edge.

    * R1 — :record is a registered container, round-trips through the registry.
    * R2 — blocks created with container_type :record load via the generic
            `list_for_container/2` primitive, and are scoped to that record.
    * R3 — `ingest_descriptor/2` describes a non-empty body, `:skip`s an empty
            one — the single hook that makes a record searchable.
    * R4 — the seam holds: a record's own body blocks are distinct from blocks
            on the page it references via `page_id`.
  """
  use Concept.DataCase, async: false

  alias Concept.Containable
  alias Concept.Objects
  alias Concept.Objects.Record
  alias Concept.Pages

  setup do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "rec#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    {:ok, [ws]} = Concept.Accounts.Workspace.for_user(user.id, actor: user)
    {:ok, type} = Objects.scaffold_object_type("Ticket", actor: user, tenant: ws.id)

    {:ok, rec} =
      Objects.create_record(type.id, %{fields: %{"title" => "Ship D1"}},
        actor: user,
        tenant: ws.id
      )

    %{user: user, ws: ws, type: type, rec: rec}
  end

  describe "R1 — registry membership" do
    test "Record is a registered container and round-trips" do
      assert Record in Containable.registered()
      assert :record in Containable.types()
      assert Containable.module_for(:record) == Record
    end
  end

  describe "R2 — generic block loading" do
    test "blocks created on a record load via list_for_container, scoped tight", ctx do
      {:ok, b} =
        Pages.create_block(:record, ctx.rec.id, :paragraph, ctx.ws.id, nil,
          actor: ctx.user,
          tenant: ctx.ws.id
        )

      assert b.container_type == :record
      assert b.container_id == ctx.rec.id

      {:ok, blocks} =
        Pages.list_for_container(:record, ctx.rec.id, actor: ctx.user, tenant: ctx.ws.id)

      assert Enum.map(blocks, & &1.id) == [b.id]

      # A different record id sees none of this record's blocks.
      {:ok, other} =
        Objects.create_record(ctx.type.id, %{fields: %{"title" => "Other"}},
          actor: ctx.user,
          tenant: ctx.ws.id
        )

      {:ok, none} =
        Pages.list_for_container(:record, other.id, actor: ctx.user, tenant: ctx.ws.id)

      assert none == []
    end
  end

  describe "R3 — ingest_descriptor" do
    test "skips an empty body", ctx do
      assert Record.ingest_descriptor(ctx.rec.id, ctx.ws.id) == :skip
    end

    test "describes a non-empty body with title as document body", ctx do
      {:ok, b} =
        Pages.create_block(:record, ctx.rec.id, :paragraph, ctx.ws.id, nil,
          actor: ctx.user,
          tenant: ctx.ws.id
        )

      {:ok, _} =
        Pages.update_content(b, %{"text" => "searchable detail"},
          actor: ctx.user,
          tenant: ctx.ws.id
        )

      assert {:ok, desc} = Record.ingest_descriptor(ctx.rec.id, ctx.ws.id)
      assert desc.source_id == "record:#{ctx.rec.id}"
      assert desc.body == "Ship D1"
      assert Keyword.fetch!(desc.chunker_opts, :record_id) == ctx.rec.id
      assert [_one] = Keyword.fetch!(desc.chunker_opts, :blocks)
      assert Keyword.fetch!(desc.chunker_opts, :workspace_id) == ctx.ws.id
    end
  end

  describe "R4 — page_id reference vs container ownership are distinct edges" do
    test "a record's body blocks never leak onto its referenced page", ctx do
      {:ok, page} =
        Pages.create_page("Project", ctx.ws.id, nil, actor: ctx.user, tenant: ctx.ws.id)

      {:ok, linked} =
        Record
        |> Ash.Changeset.for_create(
          :create,
          %{object_type_id: ctx.type.id, fields: %{"title" => "Linked"}, page_id: page.id},
          actor: ctx.user,
          tenant: ctx.ws.id
        )
        |> Ash.create()

      # Body block on the RECORD container.
      {:ok, body} =
        Pages.create_block(:record, linked.id, :paragraph, ctx.ws.id, nil,
          actor: ctx.user,
          tenant: ctx.ws.id
        )

      # Block on the referenced PAGE container.
      {:ok, page_block} =
        Pages.create_block(:page, page.id, :paragraph, ctx.ws.id, nil,
          actor: ctx.user,
          tenant: ctx.ws.id
        )

      assert linked.page_id == page.id

      {:ok, record_blocks} =
        Pages.list_for_container(:record, linked.id, actor: ctx.user, tenant: ctx.ws.id)

      {:ok, page_blocks} =
        Pages.list_for_page(page.id, actor: ctx.user, tenant: ctx.ws.id)

      assert Enum.map(record_blocks, & &1.id) == [body.id]
      assert Enum.map(page_blocks, & &1.id) == [page_block.id]
    end
  end
end
