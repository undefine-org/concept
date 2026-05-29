defmodule ConceptWeb.Objects.RecordDetailComponent do
  @moduledoc """
  Linear-style slide-over for a single `Record`: edit every field (generic,
  via `FieldTypeComponent.input`), reassign, and move along the workflow with
  guard requirements shown inline.

  This is the surface that closes the §6 acceptance loop — a human fills a
  field (e.g. `pr_url`) to satisfy a `requires_proof` guard, then transitions.

  ## Structural notes
  - Field editing autosaves per field on blur (`save_field` event →
    `Objects.update_record_fields/3` merging one key into the bag).
  - Assignee + transition reuse the existing domain actions; the slide-over
    adds no new server authority.
  - LiveView purity (EX9001): all data access through `Concept.Objects` /
    `Concept.Accounts` code-interface fns.

  The parent LiveView owns open/close; it passes `record_id`, `members`, and
  the board graph (`field_defs`, `states`, `transitions`, `states_by_id`) so
  the component renders without re-querying the type.
  """
  use ConceptWeb, :live_component

  alias Concept.Objects
  alias ConceptWeb.Objects.FieldTypeComponent

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    {:ok, load(socket)}
  end

  defp load(socket) do
    %{record_id: id, workspace: ws, current_user: user} = socket.assigns

    case Objects.get_record(id, actor: user, tenant: ws.id, load: [:state]) do
      {:ok, record} ->
        socket
        |> assign(:record, record)
        |> assign(:moves, Objects.moves_for(record, socket.assigns.board))
        |> assign(:error, nil)

      _ ->
        assign(socket, record: nil, moves: [], error: "Record not found")
    end
  end

  @impl true
  def handle_event("save_field", %{"key" => key, "value" => value}, socket) do
    %{record: record, workspace: ws, current_user: user} = socket.assigns
    fields = Map.put(record.fields || %{}, key, normalize(value))

    socket =
      case Objects.update_record_fields(record, fields, actor: user, tenant: ws.id) do
        {:ok, _} -> load(socket) |> notify_changed()
        {:error, _} -> assign(socket, :error, "Couldn't save #{key}")
      end

    {:noreply, socket}
  end

  def handle_event("assign", %{"assignee_id" => assignee_id}, socket) do
    %{record: record, workspace: ws, current_user: user} = socket.assigns
    assignee = if assignee_id == "", do: nil, else: assignee_id

    socket =
      case Objects.assign_record(record, assignee, actor: user, tenant: ws.id) do
        {:ok, _} -> load(socket) |> notify_changed()
        {:error, _} -> assign(socket, :error, "Couldn't reassign")
      end

    {:noreply, socket}
  end

  def handle_event("move", %{"to" => to_state_id}, socket) do
    %{record: record, workspace: ws, current_user: user} = socket.assigns

    socket =
      case Objects.transition_record(record, to_state_id, actor: user, tenant: ws.id) do
        {:ok, _} ->
          load(socket) |> notify_changed()

        {:error, %Ash.Error.Invalid{} = err} ->
          assign(socket, :error, move_error(err))

        _ ->
          assign(socket, :error, "Move not allowed")
      end

    {:noreply, socket}
  end

  def handle_event("close", _params, socket) do
    send(self(), :close_record_detail)
    {:noreply, socket}
  end

  # Tell the parent to reload the board so card state stays in sync.
  defp notify_changed(socket) do
    send(self(), :record_changed)
    socket
  end

  defp normalize(""), do: nil
  defp normalize(v), do: v

  defp move_error(%Ash.Error.Invalid{errors: errors}) do
    errors
    |> Enum.map(&Map.get(&1, :message, ""))
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("; ")
    |> case do
      "" -> "Move not allowed"
      msg -> msg
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="fixed inset-0 z-40">
      <%!-- scrim --%>
      <div class="absolute inset-0 bg-black/20" phx-click="close" phx-target={@myself} />

      <%!-- panel --%>
      <div class="absolute right-0 top-0 flex h-full w-full max-w-md flex-col bg-white shadow-xl">
        <%= if @record do %>
          <div class="flex items-center justify-between border-b border-notion-divider px-5 py-3">
            <span class="inline-flex items-center gap-2">
              <span class={[
                "rounded px-1.5 py-0.5 text-xs font-medium",
                state_chip(@record)
              ]}>
                {state_label(@record)}
              </span>
              <h2 class="text-sm font-semibold text-notion-text">{@record.title}</h2>
            </span>
            <button
              type="button"
              phx-click="close"
              phx-target={@myself}
              class="text-notion-text-light hover:text-notion-text"
              aria-label="Close"
            >
              <.icon name="hero-x-mark" class="h-5 w-5" />
            </button>
          </div>

          <div class="flex-1 space-y-5 overflow-y-auto px-5 py-4">
            <p :if={@error} class="rounded bg-red-50 px-2 py-1 text-xs text-red-700">{@error}</p>

            <%!-- fields --%>
            <div :for={fd <- @field_defs} class="space-y-1">
              <label class="flex items-center gap-1.5 text-xs font-medium text-notion-text-light">
                <span>{field_icon(fd)}</span>
                {fd.name}
              </label>

              <form phx-change="save_field" phx-target={@myself}>
                <input type="hidden" name="key" value={fd.key} />
                <.field_control
                  field_def={fd}
                  value={Map.get(@record.fields || %{}, fd.key)}
                  members={@members}
                  myself={@myself}
                />
              </form>
            </div>

            <%!-- assignee --%>
            <div class="space-y-1">
              <label class="text-xs font-medium text-notion-text-light">Assignee</label>
              <form phx-change="assign" phx-target={@myself}>
                <select
                  name="assignee_id"
                  class="w-full rounded-md border border-notion-divider px-2 py-1 text-sm"
                >
                  <option value="">Unassigned</option>
                  <option
                    :for={m <- @members}
                    value={member_id(m)}
                    selected={to_string(@record.assignee_id) == member_id(m)}
                  >
                    {member_name(m)}
                  </option>
                </select>
              </form>
            </div>

            <%!-- transitions --%>
            <div :if={@moves != []} class="space-y-1">
              <label class="text-xs font-medium text-notion-text-light">Move to</label>
              <div class="flex flex-col gap-1.5">
                <button
                  :for={move <- @moves}
                  type="button"
                  phx-click="move"
                  phx-value-to={move.to_state.id}
                  phx-target={@myself}
                  class="flex items-center justify-between rounded-md border border-notion-divider px-2.5 py-1.5 text-sm text-notion-text transition hover:bg-notion-gray"
                >
                  <span>→ {move.to_state.name}</span>
                  <span :if={move.requirements != []} class="text-xs text-notion-text-light">
                    🔒 {Enum.join(move.requirements, "; ")}
                  </span>
                </button>
              </div>
            </div>
          </div>
        <% else %>
          <div class="p-5 text-sm text-notion-text-light">{@error || "Loading…"}</div>
        <% end %>
      </div>
    </div>
    """
  end

  # Wraps FieldTypeComponent.input in a form field bound to the field key.
  attr :field_def, :map, required: true
  attr :value, :any, default: nil
  attr :members, :list, default: []
  attr :myself, :any, required: true

  defp field_control(assigns) do
    # Unique id/name per field so multiple field forms don't collide on the
    # default "value" DOM id. The handler reads "value" from params, so keep
    # the param name "value" but give the input a key-scoped id.
    form = to_form(%{"value" => assigns.value}, id: "field-#{assigns.field_def.key}")
    assigns = assign(assigns, :form_field, form[:value])

    ~H"""
    <FieldTypeComponent.input field_def={@field_def} field={@form_field} members={@members} />
    """
  end

  defp field_icon(%{field_type: ft}) do
    case Concept.Objects.FieldTypes.lookup_safe(ft) do
      {:ok, mod} -> if function_exported?(mod, :icon, 0), do: mod.icon(), else: ""
      _ -> ""
    end
  end

  defp state_label(%{state: %{name: name}}) when is_binary(name), do: name
  defp state_label(_), do: "—"

  defp state_chip(%{state: %{category: cat}}) do
    case cat do
      :todo -> "bg-blue-100 text-blue-800"
      :doing -> "bg-yellow-100 text-yellow-800"
      :review -> "bg-purple-100 text-purple-800"
      :done -> "bg-green-100 text-green-800"
      _ -> "bg-notion-gray text-notion-text-light"
    end
  end

  defp state_chip(_), do: "bg-notion-gray text-notion-text-light"

  defp member_id(%{id: id}), do: to_string(id)
  defp member_id(_), do: ""

  defp member_name(%{email: email}) when not is_nil(email),
    do: email |> to_string() |> String.split("@") |> List.first()

  defp member_name(_), do: "Member"
end
