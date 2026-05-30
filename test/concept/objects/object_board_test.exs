defmodule Concept.Objects.ObjectBoardTest do
  @moduledoc """
  Thread ① — the database-builder thesis made reachable: a *user-created* type
  must be immediately usable (scaffolded with a default workflow + title field)
  and rendered on a *generic* board, exactly like the built-in Task type.

  `Objects.scaffold_object_type/2` is the single "make a usable type" path
  shared by the human editor and the Task `Seeder`. `Objects.object_board/2`
  is the generic board over any type; `task_board/1` is one instance of it.
  """
  use Concept.DataCase, async: true

  alias Concept.Objects

  setup do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "board_#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    {:ok, [ws]} = Concept.Accounts.Workspace.for_user(user.id, actor: user)
    %{user: user, ws: ws.id}
  end

  describe "scaffold_object_type/2" do
    test "creates a usable type: default workflow (6 categories, backlog initial) + title field",
         ctx do
      {:ok, type} = Objects.scaffold_object_type("Customer", actor: ctx.user, tenant: ctx.ws)

      assert type.name == "Customer"
      assert is_binary(type.workflow_id), "a scaffolded type must point at a workflow"

      {:ok, states} =
        Objects.list_workflow_states(type.workflow_id, actor: ctx.user, tenant: ctx.ws)

      cats = states |> Enum.map(& &1.category) |> Enum.sort()
      assert cats == Enum.sort([:backlog, :todo, :doing, :review, :done, :canceled])
      assert Enum.find(states, & &1.is_initial?).category == :backlog

      {:ok, fields} = Objects.list_field_defs(type.id, actor: ctx.user, tenant: ctx.ws)
      title = Enum.find(fields, & &1.is_title?)
      assert title, "a scaffolded type must have a designated title field"
      assert title.field_type == :text
    end

    test "records created in a scaffolded type land in the initial state with title set", ctx do
      {:ok, type} = Objects.scaffold_object_type("Customer", actor: ctx.user, tenant: ctx.ws)

      {:ok, rec} =
        Objects.create_record(type.id, %{fields: %{"title" => "Acme Inc"}},
          actor: ctx.user,
          tenant: ctx.ws
        )

      assert rec.title == "Acme Inc"
      assert is_binary(rec.state_id), "record must enter the workflow's initial state"

      {:ok, states} =
        Objects.list_workflow_states(type.workflow_id, actor: ctx.user, tenant: ctx.ws)

      initial = Enum.find(states, & &1.is_initial?)
      assert rec.state_id == initial.id
    end

    test "scaffolded default edges allow the linear flow (backlog -> todo)", ctx do
      {:ok, type} = Objects.scaffold_object_type("Customer", actor: ctx.user, tenant: ctx.ws)
      {:ok, board} = Objects.object_board(type.id, actor: ctx.user, tenant: ctx.ws)

      {:ok, rec} =
        Objects.create_record(type.id, %{fields: %{"title" => "Acme"}},
          actor: ctx.user,
          tenant: ctx.ws
        )

      moves = Objects.moves_for(rec, board)
      to_cats = Enum.map(moves, & &1.to_state.category)
      assert :todo in to_cats, "backlog record must be movable to todo"
    end
  end

  describe "object_board/2" do
    test "groups a scaffolded type's records into columns keyed by state id", ctx do
      {:ok, type} = Objects.scaffold_object_type("Customer", actor: ctx.user, tenant: ctx.ws)

      {:ok, rec} =
        Objects.create_record(type.id, %{fields: %{"title" => "Acme"}},
          actor: ctx.user,
          tenant: ctx.ws
        )

      {:ok, board} = Objects.object_board(type.id, actor: ctx.user, tenant: ctx.ws)

      assert board.type.id == type.id
      assert length(board.states) == 6
      initial = Enum.find(board.states, & &1.is_initial?)
      assert Enum.any?(Map.get(board.columns, initial.id, []), &(&1.id == rec.id))
      assert %MapSet{} = board.blocked_ids
    end

    test "errors for an unknown type id", ctx do
      assert {:error, _} =
               Objects.object_board(Ash.UUID.generate(), actor: ctx.user, tenant: ctx.ws)
    end
  end

  describe "task_board/1 delegates to object_board" do
    test "still resolves the seeded Task type with the same board shape", ctx do
      {:ok, board} = Objects.task_board(actor: ctx.user, tenant: ctx.ws)

      assert board.type.key == "task"
      assert is_list(board.states)
      assert is_map(board.columns)
      assert %MapSet{} = board.blocked_ids
      assert Map.has_key?(board, :transitions)
      assert Map.has_key?(board, :field_defs)
      assert Map.has_key?(board, :states_by_id)
    end
  end
end
