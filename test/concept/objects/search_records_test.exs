defmodule Concept.Objects.SearchRecordsTest do
  @moduledoc """
  Thread ② — the non-redundancy seam: `Objects.search_records/1` finds records
  by title so a human can *pick* the canonical record to reference from a doc
  (record_ref block) or a relation field. Workspace-scoped; optionally narrowed
  to one object type; case-insensitive title contains; capped by limit.
  """
  use Concept.DataCase, async: true

  alias Concept.Objects

  setup do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "search_#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    {:ok, [ws]} = Concept.Accounts.Workspace.for_user(user.id, actor: user)
    {:ok, type_a} = Objects.scaffold_object_type("Alpha", actor: user, tenant: ws.id)
    {:ok, type_b} = Objects.scaffold_object_type("Beta", actor: user, tenant: ws.id)

    rec = fn type, title ->
      {:ok, r} =
        Objects.create_record(type.id, %{fields: %{"title" => title}},
          actor: user,
          tenant: ws.id
        )

      r
    end

    %{user: user, ws: ws.id, type_a: type_a, type_b: type_b, rec: rec}
  end

  test "finds records by case-insensitive title fragment across all types", ctx do
    a = ctx.rec.(ctx.type_a, "Design the landing page")
    b = ctx.rec.(ctx.type_b, "Landing zone cleanup")
    _c = ctx.rec.(ctx.type_a, "Unrelated work")

    {:ok, results} = Objects.search_records(query: "landing", actor: ctx.user, tenant: ctx.ws)
    ids = Enum.map(results, & &1.id)

    assert a.id in ids
    assert b.id in ids
    assert length(results) == 2
  end

  test "narrows to a single object type when object_type_id is given", ctx do
    a = ctx.rec.(ctx.type_a, "Shared name")
    _b = ctx.rec.(ctx.type_b, "Shared name")

    {:ok, results} =
      Objects.search_records(
        query: "shared",
        object_type_id: ctx.type_a.id,
        actor: ctx.user,
        tenant: ctx.ws
      )

    assert Enum.map(results, & &1.id) == [a.id]
  end

  test "blank query returns recent records (capped by limit)", ctx do
    for i <- 1..5, do: ctx.rec.(ctx.type_a, "Rec #{i}")

    {:ok, results} = Objects.search_records(query: "", limit: 3, actor: ctx.user, tenant: ctx.ws)
    assert length(results) == 3
  end

  test "excludes a given record id (so a record can't reference itself)", ctx do
    a = ctx.rec.(ctx.type_a, "Self ref candidate")
    b = ctx.rec.(ctx.type_a, "Self ref candidate two")

    {:ok, results} =
      Objects.search_records(
        query: "self ref",
        exclude_id: a.id,
        actor: ctx.user,
        tenant: ctx.ws
      )

    ids = Enum.map(results, & &1.id)
    refute a.id in ids
    assert b.id in ids
  end

  test "results carry title + object_type for display", ctx do
    _a = ctx.rec.(ctx.type_a, "Displayable")
    {:ok, [r]} = Objects.search_records(query: "displayable", actor: ctx.user, tenant: ctx.ws)
    assert r.title == "Displayable"
    assert r.object_type_id == ctx.type_a.id
  end
end
