defmodule ConceptWeb.Objects.WorkflowEditorComponent do
  @moduledoc """
  Workflow editor embedded in the object-type editor: manage a type's
  lifecycle — states (each mapped to a fixed `category`) and the guarded
  transitions between them. List-first (a drag canvas is a tracked FUP).

  Mirrors the design's two-layer lifecycle: state *names* are user-open; each
  maps to one fixed agent-legible `category`. Transitions carry an ordered
  guard list, each configured via its `Guard.render_config_form/2` — a generic
  projection over the `Guards` registry (no per-guard branching), the same
  discipline as fields.

  LiveView purity (EX9001): all access via `Concept.Objects` code-interface.
  The parent passes `type`, `workspace`, `current_user`.
  """
  use ConceptWeb, :live_component

  alias Concept.Objects
  alias Concept.Objects.{Guards, WorkflowState}

  @impl true
  def update(assigns, socket) do
    {:ok, socket |> assign(assigns) |> load()}
  end

  defp load(socket) do
    %{type: type, workspace: ws} = socket.assigns
    user = socket.assigns.current_user

    if is_nil(type.workflow_id) do
      socket
      |> assign(:workflow_id, nil)
      |> assign(:states, [])
      |> assign(:transitions, [])
      |> assign_new(:new_state_name, fn -> "" end)
      |> assign_new(:new_state_category, fn -> "todo" end)
    else
      {:ok, states} = Objects.list_workflow_states(type.workflow_id, actor: user, tenant: ws.id)
      {:ok, transitions} = Objects.list_transitions(type.workflow_id, actor: user, tenant: ws.id)

      socket
      |> assign(:workflow_id, type.workflow_id)
      |> assign(:states, states)
      |> assign(:transitions, transitions)
      |> assign_new(:new_state_name, fn -> "" end)
      |> assign_new(:new_state_category, fn -> "todo" end)
    end
  end

  # ── events ───────────────────────────────────────────────────────────

  @impl true
  def handle_event("create_workflow", _params, socket) do
    %{type: type, workspace: ws} = socket.assigns
    user = socket.assigns.current_user

    with {:ok, wf} <-
           Objects.create_workflow("#{type.name} workflow", actor: user, tenant: ws.id),
         {:ok, updated} <-
           Objects.set_object_type_workflow(type, wf.id, actor: user, tenant: ws.id) do
      {:noreply, socket |> assign(:type, updated) |> load()}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("add_state", %{"name" => name, "category" => category}, socket) do
    name = String.trim(name)
    %{workspace: ws, workflow_id: wf_id, states: states} = socket.assigns
    user = socket.assigns.current_user

    with false <- name == "" or is_nil(wf_id),
         {:ok, cat} <- parse_category(category),
         {:ok, state} <-
           Objects.create_workflow_state(wf_id, name, cat, actor: user, tenant: ws.id),
         :ok <- maybe_mark_first_initial(state, states, user, ws.id) do
      {:noreply, socket |> assign(:new_state_name, "") |> load()}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("update_state", %{"state_id" => id} = params, socket) do
    %{workspace: ws, states: states} = socket.assigns
    user = socket.assigns.current_user
    state = Enum.find(states, &(&1.id == id))

    with %{} <- state,
         name <- blank_to(params["name"], state.name),
         {:ok, cat} <- parse_category(params["category"] || to_string(state.category)),
         {:ok, _} <- Objects.update_workflow_state(state, name, cat, actor: user, tenant: ws.id) do
      {:noreply, load(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("make_initial", %{"state_id" => id}, socket) do
    %{workspace: ws, states: states} = socket.assigns
    user = socket.assigns.current_user
    state = Enum.find(states, &(&1.id == id))

    with %{} <- state,
         {:ok, _} <-
           Objects.mark_workflow_state_initial(state, actor: user, tenant: ws.id) do
      {:noreply, load(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("add_transition", %{"from" => from_id, "to" => to_id}, socket) do
    %{workspace: ws, workflow_id: wf_id} = socket.assigns
    user = socket.assigns.current_user

    with false <- from_id == "" or to_id == "" or from_id == to_id,
         {:ok, _} <-
           Objects.create_transition(wf_id, from_id, to_id, actor: user, tenant: ws.id) do
      {:noreply, load(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("add_guard", %{"transition_id" => tid, "kind" => kind}, socket) do
    %{workspace: ws, transitions: transitions} = socket.assigns
    user = socket.assigns.current_user
    transition = Enum.find(transitions, &(&1.id == tid))

    with %{} <- transition,
         {:ok, _} <- Guards.lookup(kind),
         guards <- (transition.guards || []) ++ [%{"kind" => kind, "config" => %{}}],
         {:ok, _} <-
           Objects.set_transition_guards(transition, guards, actor: user, tenant: ws.id) do
      {:noreply, load(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("update_guard", %{"transition_id" => tid, "index" => idx} = params, socket) do
    %{workspace: ws, transitions: transitions} = socket.assigns
    user = socket.assigns.current_user
    transition = Enum.find(transitions, &(&1.id == tid))

    with %{} <- transition,
         {i, ""} <- Integer.parse(idx),
         guards when is_list(guards) <- transition.guards,
         guard when not is_nil(guard) <- Enum.at(guards, i),
         raw <- Map.drop(params, ["transition_id", "index", "_target"]),
         config <- normalize_guard_config(guard["kind"], raw),
         updated <- List.replace_at(guards, i, Map.put(guard, "config", config)),
         {:ok, _} <-
           Objects.set_transition_guards(transition, updated, actor: user, tenant: ws.id) do
      {:noreply, load(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("remove_guard", %{"transition_id" => tid, "index" => idx}, socket) do
    %{workspace: ws, transitions: transitions} = socket.assigns
    user = socket.assigns.current_user
    transition = Enum.find(transitions, &(&1.id == tid))

    with %{} <- transition,
         {i, ""} <- Integer.parse(idx),
         guards when is_list(guards) <- transition.guards,
         updated <- List.delete_at(guards, i),
         {:ok, _} <-
           Objects.set_transition_guards(transition, updated, actor: user, tenant: ws.id) do
      {:noreply, load(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  # ── helpers ──────────────────────────────────────────────────────────

  # The first state of a fresh workflow becomes its initial state. Pure: both
  # calls go through the Objects code-interface (EX9001).
  defp maybe_mark_first_initial(state, existing_states, user, tenant) do
    if existing_states == [] do
      case Objects.mark_workflow_state_initial(state, actor: user, tenant: tenant) do
        {:ok, _} -> :ok
        err -> err
      end
    else
      :ok
    end
  end

  # Let each guard normalize its raw form config into the stored shape
  # (e.g. requires_fields: comma-string → list). Identity when the guard
  # doesn't implement the optional callback.
  defp normalize_guard_config(kind, raw) do
    case Guards.lookup(kind) do
      {:ok, mod} ->
        if function_exported?(mod, :normalize_config, 1), do: mod.normalize_config(raw), else: raw

      _ ->
        raw
    end
  end

  defp parse_category(str) do
    cat = String.to_existing_atom(str)
    if cat in WorkflowState.categories(), do: {:ok, cat}, else: {:error, :bad_category}
  rescue
    ArgumentError -> {:error, :bad_category}
  end

  defp blank_to(nil, default), do: default
  defp blank_to("", default), do: default
  defp blank_to(v, _), do: String.trim(v)

  defp state_name(states, id) do
    case Enum.find(states, &(&1.id == id)) do
      %{name: n} -> n
      _ -> "?"
    end
  end

  defp guard_describe(%{"kind" => kind} = g) do
    case Guards.lookup(kind) do
      {:ok, mod} -> mod.describe(Map.get(g, "config", %{}))
      _ -> kind
    end
  end

  defp guard_describe(_), do: "?"

  # ── render ───────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <section id={@id} class="mb-8">
      <h2 class="mb-3 text-sm font-semibold uppercase tracking-wide text-notion-text-light">
        Workflow
      </h2>

      <%= if @workflow_id == nil do %>
        <div class="rounded-md border border-dashed border-notion-divider p-4 text-center">
          <p class="mb-3 text-sm text-notion-text-light">This type has no workflow yet.</p>
          <button
            type="button"
            phx-click="create_workflow"
            phx-target={@myself}
            class="rounded-md bg-notion-text px-3 py-1.5 text-sm font-medium text-white transition hover:opacity-80"
          >
            Add a workflow
          </button>
        </div>
      <% else %>
        <h3 class="mb-2 text-xs font-semibold uppercase tracking-wide text-notion-text-light">
          States
        </h3>
        <div class="space-y-2">
          <div
            :for={state <- @states}
            id={"state-#{state.id}"}
            class="flex items-center gap-2 rounded-md border border-notion-divider p-2"
          >
            <form
              phx-change="update_state"
              phx-target={@myself}
              class="flex flex-1 items-center gap-2"
            >
              <input type="hidden" name="state_id" value={state.id} />
              <input
                type="text"
                name="name"
                value={state.name}
                class="flex-1 rounded border border-notion-divider px-2 py-1 text-sm"
              />
              <select name="category" class="rounded border border-notion-divider px-2 py-1 text-sm">
                <option
                  :for={cat <- WorkflowState.categories()}
                  value={cat}
                  selected={state.category == cat}
                >
                  {cat}
                </option>
              </select>
            </form>
            <span
              :if={state.is_initial?}
              class="rounded bg-green-100 px-1.5 py-0.5 text-xs text-green-800"
            >
              initial
            </span>
            <button
              :if={!state.is_initial?}
              type="button"
              phx-click="make_initial"
              phx-value-state_id={state.id}
              phx-target={@myself}
              class="text-xs text-notion-text-light hover:text-notion-text"
            >
              set initial
            </button>
          </div>
        </div>

        <form
          phx-submit="add_state"
          phx-target={@myself}
          id="add-state-form"
          class="mt-2 flex gap-2"
        >
          <input
            type="text"
            name="name"
            value={@new_state_name}
            placeholder="New state name…"
            autocomplete="off"
            class="flex-1 rounded-md border border-notion-divider px-3 py-1.5 text-sm"
          />
          <select name="category" class="rounded-md border border-notion-divider px-2 py-1.5 text-sm">
            <option
              :for={cat <- WorkflowState.categories()}
              value={cat}
              selected={to_string(cat) == @new_state_category}
            >
              {cat}
            </option>
          </select>
          <button
            type="submit"
            class="rounded-md bg-notion-text px-3 py-1.5 text-sm font-medium text-white transition hover:opacity-80"
          >
            Add state
          </button>
        </form>

        <h3 class="mt-6 mb-2 text-xs font-semibold uppercase tracking-wide text-notion-text-light">
          Transitions
        </h3>
        <div class="space-y-2">
          <div
            :for={t <- @transitions}
            id={"transition-#{t.id}"}
            class="rounded-md border border-notion-divider p-2"
          >
            <div class="flex items-center gap-2 text-sm text-notion-text">
              <span class="font-medium">{state_name(@states, t.from_state_id)}</span>
              <span class="text-notion-text-light">→</span>
              <span class="font-medium">{state_name(@states, t.to_state_id)}</span>
            </div>

            <div :if={t.guards not in [nil, []]} class="mt-2 space-y-2 pl-3">
              <div
                :for={{guard, idx} <- Enum.with_index(t.guards)}
                class="rounded border border-notion-divider/60 bg-notion-gray/30 p-2"
              >
                <div class="flex items-center justify-between">
                  <span class="text-xs text-notion-text-light">🔒 {guard_describe(guard)}</span>
                  <button
                    type="button"
                    phx-click="remove_guard"
                    phx-value-transition_id={t.id}
                    phx-value-index={idx}
                    phx-target={@myself}
                    class="text-xs text-red-600 hover:text-red-800"
                  >
                    remove
                  </button>
                </div>
                <form phx-change="update_guard" phx-target={@myself} class="mt-1">
                  <input type="hidden" name="transition_id" value={t.id} />
                  <input type="hidden" name="index" value={idx} />
                  {guard_config_form(%{guard: guard})}
                </form>
              </div>
            </div>

            <form phx-submit="add_guard" phx-target={@myself} class="mt-2 flex gap-2 pl-3">
              <input type="hidden" name="transition_id" value={t.id} />
              <select name="kind" class="rounded border border-notion-divider px-2 py-1 text-xs">
                <option :for={g <- Guards.palette()} value={g.kind}>{g.label}</option>
              </select>
              <button
                type="submit"
                class="rounded border border-notion-divider px-2 py-1 text-xs text-notion-text hover:bg-notion-gray"
              >
                + guard
              </button>
            </form>
          </div>
        </div>

        <form
          :if={length(@states) >= 2}
          phx-submit="add_transition"
          phx-target={@myself}
          id="add-transition-form"
          class="mt-2 flex items-center gap-2"
        >
          <select name="from" class="rounded-md border border-notion-divider px-2 py-1.5 text-sm">
            <option value="">From…</option>
            <option :for={s <- @states} value={s.id}>{s.name}</option>
          </select>
          <span class="text-notion-text-light">→</span>
          <select name="to" class="rounded-md border border-notion-divider px-2 py-1.5 text-sm">
            <option value="">To…</option>
            <option :for={s <- @states} value={s.id}>{s.name}</option>
          </select>
          <button
            type="submit"
            class="rounded-md bg-notion-text px-3 py-1.5 text-sm font-medium text-white transition hover:opacity-80"
          >
            Add transition
          </button>
        </form>
      <% end %>
    </section>
    """
  end

  # Renders a guard's config form via its registry module (generic projection).
  defp guard_config_form(assigns) do
    %{"kind" => kind} = assigns.guard
    config = Map.get(assigns.guard, "config", %{})

    case Guards.lookup(kind) do
      {:ok, mod} ->
        if function_exported?(mod, :render_config_form, 2) do
          mod.render_config_form(config, to_form(%{}))
        else
          ~H""
        end

      _ ->
        ~H""
    end
  end
end
