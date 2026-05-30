defmodule Concept.Objects.Scaffold do
  @moduledoc """
  The single source of truth for **"a usable object type"**.

  A bare `ObjectType` (via `create_object_type/1`) has no workflow and no
  fields — its records would be stateless and titleless. That bare primitive
  exists for tests and the generic MCP spine, but no human should ever land on
  it. Every type a *person* creates — and the built-in **Task** type — must be
  immediately usable: a default lifecycle to move records through, and a title
  field so records have a name on a card.

  This module builds that scaffold once, so two callers share it:

    * `Concept.Objects.scaffold_object_type/2` — the human editor's "Create
      type" path.
    * `Concept.Objects.Seeder` — onboarding's built-in Task type, which is
      `object_type/2` *plus* Task-specific extras (priority, blocked_by, and
      the human-acceptance guard on `→ Done`).

  "Invent a type → it works on a board" therefore holds **by construction**,
  for the LiveView editor and for the `create_<type>` MCP tool alike — both
  go through the same `Record`/`Workflow` actions, same policies, same data.

  ## Default lifecycle

  The six fixed categories (`docs/objects_and_tasks.md` §3), with **Backlog**
  initial and the standard linear flow plus cancel escapes. Generic types get
  *no* transition guards by default — the human-acceptance gate is a **Task**
  decision (see `Seeder`), not a universal database-builder default.
  """
  require Ash.Query

  alias Concept.Objects.{FieldDef, ObjectType, Transition, Workflow, WorkflowState}

  # {name, category, initial?}
  @states [
    {"Backlog", :backlog, true},
    {"Todo", :todo, false},
    {"Doing", :doing, false},
    {"Review", :review, false},
    {"Done", :done, false},
    {"Canceled", :canceled, false}
  ]

  # {from_category, to_category} — guard-free linear flow + cancel escapes.
  @edges [
    {:backlog, :todo},
    {:todo, :doing},
    {:doing, :review},
    {:review, :done},
    {:todo, :canceled},
    {:doing, :canceled}
  ]

  @doc """
  Build a default workflow (six categorized states, Backlog initial, the
  standard edges) in the tenant. Returns `{:ok, %{workflow: Workflow,
  states: %{category => WorkflowState}}}`.

  `opts` must carry `:tenant`; `:actor` and `:authorize?` are forwarded (the
  onboarding seeder passes a system actor with `authorize?: false`, the editor
  passes the member).
  """
  def default_workflow(name \\ "Default", opts) do
    ctx = ctx(opts)

    {:ok, wf} =
      Workflow
      |> Ash.Changeset.for_create(:create, %{name: name}, ctx)
      |> Ash.create()

    states =
      Enum.reduce(@states, %{}, fn {sname, cat, initial}, acc ->
        {:ok, state} =
          WorkflowState
          |> Ash.Changeset.for_create(
            :create,
            %{workflow_id: wf.id, name: sname, category: cat, is_initial?: initial},
            ctx
          )
          |> Ash.create()

        Map.put(acc, cat, state)
      end)

    for {from, to} <- @edges do
      {:ok, _} =
        Transition
        |> Ash.Changeset.for_create(
          :create,
          %{workflow_id: wf.id, from_state_id: states[from].id, to_state_id: states[to].id},
          ctx
        )
        |> Ash.create()
    end

    {:ok, %{workflow: wf, states: states}}
  end

  @doc """
  Create a **usable** object type: a default workflow (via `default_workflow/2`)
  and a designated text title field. Returns `{:ok, %ObjectType{}}`.

  `extra_type_attrs` lets the Task seeder pin `key`/`icon`/`is_system?`; user
  types omit it and let `SlugifyKey` derive the key from the name.

  `opts` must carry `:tenant`; `:actor`/`:authorize?` are forwarded.
  """
  def object_type(name, extra_type_attrs \\ %{}, opts) do
    ctx = ctx(opts)

    {:ok, %{workflow: wf}} = default_workflow(opts)

    attrs =
      extra_type_attrs
      |> Map.new()
      |> Map.merge(%{name: name, workflow_id: wf.id})

    {:ok, type} =
      ObjectType
      |> Ash.Changeset.for_create(:create, attrs, ctx)
      |> Ash.create()

    {:ok, _title} =
      FieldDef
      |> Ash.Changeset.for_create(
        :create,
        %{
          object_type_id: type.id,
          name: "Title",
          key: "title",
          field_type: :text,
          is_title?: true,
          required?: true
        },
        ctx
      )
      |> Ash.create()

    {:ok, type}
  end

  # Build the Ash action context from caller opts. `:tenant` is required;
  # `:actor`/`:authorize?` default to nil/true so the editor path authorizes
  # against the member, while the seeder opts in to a system bypass.
  defp ctx(opts) do
    [
      tenant: Keyword.fetch!(opts, :tenant),
      actor: Keyword.get(opts, :actor),
      authorize?: Keyword.get(opts, :authorize?, true)
    ]
  end
end
