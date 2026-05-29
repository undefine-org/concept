defmodule ConceptWeb.TasksLive do
  @moduledoc """
  Tasks board for a workspace's built-in Task type: columns by workflow
  category, create a task into Backlog, and move a task along its workflow's
  guarded transitions.

  LiveView purity (EX9001): all data access goes through `Concept.Objects`
  code-interface fns — no `Ash.Query` / `Ash.Changeset` here.
  """
  use ConceptWeb, :live_view

  alias Concept.Accounts
  alias Concept.Objects

  @columns [:backlog, :todo, :doing, :review, :done, :canceled]

  @impl true
  def mount(%{"workspace_slug" => slug}, _session, socket) do
    user = socket.assigns.current_user

    case Accounts.Workspace.by_slug(slug, actor: user) do
      {:ok, ws} ->
        {:ok,
         socket
         |> assign(:workspace, ws)
         |> assign(:page_title, "Tasks")
         |> assign(:new_title, "")
         |> assign(:columns, @columns)
         |> load_board()}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Workspace not found")
         |> push_navigate(to: ~p"/w")}
    end
  end

  @impl true
  def handle_event("create_task", %{"title" => title}, socket) when is_binary(title) do
    title = String.trim(title)

    if title == "" do
      {:noreply, socket}
    else
      %{workspace: ws, board: %{type: type}} = socket.assigns
      user = socket.assigns.current_user

      case Objects.create_record(type.id, %{fields: %{"title" => title}}, actor: user, tenant: ws.id) do
        {:ok, _record} ->
          {:noreply, socket |> assign(:new_title, "") |> load_board()}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not create task")}
      end
    end
  end

  def handle_event("move", %{"record" => record_id, "to" => to_state_id}, socket) do
    %{workspace: ws} = socket.assigns
    user = socket.assigns.current_user

    with {:ok, record} <- Objects.get_record(record_id, actor: user, tenant: ws.id),
         {:ok, _} <- Objects.transition_record(record, to_state_id, actor: user, tenant: ws.id) do
      {:noreply, load_board(socket)}
    else
      {:error, %Ash.Error.Invalid{} = err} ->
        {:noreply, put_flash(socket, :error, move_error(err))}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not move task")}
    end
  end

  # ── data loading (code-interface only) ───────────────────────────────

  defp load_board(socket) do
    %{workspace: ws} = socket.assigns
    user = socket.assigns.current_user

    case Objects.task_board(actor: user, tenant: ws.id) do
      {:ok, board} ->
        moves =
          board.columns
          |> Map.values()
          |> List.flatten()
          |> Map.new(fn r -> {r.id, Objects.available_moves(r, actor: user, tenant: ws.id)} end)

        socket
        |> assign(:board, board)
        |> assign(:moves, moves)
        |> assign(:board_error, nil)

      {:error, :no_task_type} ->
        assign(socket, board: nil, moves: %{}, board_error: "No Task type in this workspace yet.")
    end
  end

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

  # ── render ───────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="tasks-root" class="p-6">
        <div class="flex items-center justify-between mb-6">
          <h1 class="text-2xl font-bold text-notion-text">Tasks</h1>
          <.link
            navigate={~p"/w/#{@workspace.slug}"}
            class="text-sm text-notion-text-light hover:text-notion-text"
          >
            ← Workspace
          </.link>
        </div>

        <%= if @board_error do %>
          <div class="text-notion-text-light">{@board_error}</div>
        <% else %>
          <form phx-submit="create_task" id="new-task-form" class="mb-6 flex gap-2">
            <input
              type="text"
              name="title"
              value={@new_title}
              placeholder="New task…"
              autocomplete="off"
              class="flex-1 max-w-md rounded-md border border-notion-divider px-3 py-1.5 text-sm"
            />
            <button
              type="submit"
              class="rounded-md bg-notion-text px-3 py-1.5 text-sm font-medium text-white"
            >
              Add
            </button>
          </form>

          <div class="grid grid-cols-2 gap-4 md:grid-cols-3 lg:grid-cols-6">
            <div :for={cat <- @columns} class="rounded-lg bg-notion-gray/40 p-2" id={"col-#{cat}"}>
              <div class="mb-2 flex items-center justify-between px-1">
                <span class="text-xs font-semibold uppercase tracking-wide text-notion-text-light">
                  {column_label(@board.states, cat)}
                </span>
                <span class="text-xs text-notion-text-light">
                  {length(Map.get(@board.columns, cat, []))}
                </span>
              </div>

              <div class="space-y-2">
                <div
                  :for={record <- Map.get(@board.columns, cat, [])}
                  id={"task-#{record.id}"}
                  class="rounded-md border border-notion-divider bg-white p-2 shadow-sm"
                >
                  <div class="text-sm text-notion-text">{record_title(record)}</div>

                  <div :if={@moves[record.id] != []} class="mt-2 flex flex-wrap gap-1">
                    <button
                      :for={move <- @moves[record.id]}
                      type="button"
                      phx-click="move"
                      phx-value-record={record.id}
                      phx-value-to={move.to_state.id}
                      class="rounded bg-notion-gray px-1.5 py-0.5 text-xs text-notion-text hover:bg-notion-divider"
                    >
                      → {move.to_state.name}
                    </button>
                  </div>
                </div>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp column_label(states, cat) do
    case Enum.find(states, &(&1.category == cat)) do
      %{name: name} -> name
      _ -> cat |> to_string() |> String.capitalize()
    end
  end

  defp record_title(%{title: t}) when is_binary(t) and t != "", do: t
  defp record_title(_), do: "Untitled"

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}
end
