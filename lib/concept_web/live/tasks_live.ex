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
  alias ConceptWeb.Objects.FieldTypeComponent


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
         |> assign(:assignee_field_def, %{field_type: :user, config: %{}, key: "assignee"})
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

      case Objects.create_record(type.id, %{fields: %{"title" => title}},
             actor: user,
             tenant: ws.id
           ) do
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
          |> Map.new(fn r -> {r.id, Objects.moves_for(r, board)} end)

        socket
        |> assign(:board, board)
        |> assign(:moves, moves)
        |> assign(:members, load_members(ws.id, user))
        |> assign(:card_fields, card_fields(board.field_defs))
        |> assign(:board_error, nil)

      {:error, :no_task_type} ->
        empty_board(socket, "No Task type in this workspace yet.")

      {:error, _other} ->
        empty_board(socket, "Could not load the task board.")
    end
  end

  defp empty_board(socket, message) do
    assign(socket, board: nil, moves: %{}, members: [], card_fields: [], board_error: message)
  end

  # Members feed the :user field renderer + assignee avatars. Defensive: the
  # board still renders if membership loading fails.
  defp load_members(ws_id, user) do
    # Authorizing the membership read proves the actor belongs to this
    # workspace; the User resource read policy is self-only, so resolve the
    # (already-authorized) member ids directly for display. Co-members seeing
    # each other's name is the intended behaviour.
    with {:ok, memberships} <- Accounts.Membership.list_for_workspace(ws_id, actor: user),
         ids = Enum.map(memberships, & &1.user_id),
         {:ok, users} <- Accounts.list_users_by_ids(ids) do
      users
    else
      _ -> []
    end
  end

  # Heuristic (design doc §3.3): show select + user fields on cards (priority,
  # etc.), excluding the title (the card heading). A dedicated
  # `show_on_card?` FieldDef attribute is a later refinement.
  defp card_fields(field_defs) do
    field_defs
    |> Enum.reject(& &1.is_title?)
    |> Enum.filter(&(&1.field_type in [:select, :user]))
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
              class="flex-1 max-w-md rounded-md border border-notion-divider px-3 py-1.5 text-sm focus:border-notion-text focus:outline-none"
            />
            <button
              type="submit"
              class="rounded-md bg-notion-text px-3 py-1.5 text-sm font-medium text-white transition hover:opacity-80"
            >
              Add
            </button>
          </form>

          <div id="tasks-board" phx-hook="TaskBoard" class="flex gap-3 overflow-x-auto pb-4">
            <div
              :for={state <- @board.states}
              class="w-64 shrink-0 rounded-lg bg-notion-gray/40 p-2"
              id={"col-#{state.category}"}
              data-state-id={state.id}
            >
              <div class="mb-2 flex items-center justify-between px-1">
                <span class="inline-flex items-center gap-1.5">
                  <span class={["h-2 w-2 rounded-full", category_dot(state.category)]} />
                  <span class="text-xs font-semibold uppercase tracking-wide text-notion-text-light">
                    {state.name}
                  </span>
                </span>
                <span class="text-xs text-notion-text-light">
                  {length(Map.get(@board.columns, state.id, []))}
                </span>
              </div>

              <div class="space-y-2 min-h-[2rem]">
                <div
                  :for={record <- Map.get(@board.columns, state.id, [])}
                  id={"task-#{record.id}"}
                  data-record-id={record.id}
                  class="group cursor-grab rounded-md border border-notion-divider bg-white p-2.5 shadow-sm transition hover:shadow-md active:cursor-grabbing"
                >
                  <div class="text-sm font-medium text-notion-text">{record_title(record)}</div>

                  <div
                    :if={@card_fields != [] or record.assignee_id}
                    class="mt-1.5 flex flex-wrap items-center gap-1.5"
                  >
                    <FieldTypeComponent.value
                      :for={fd <- @card_fields}
                      :if={Map.get(record.fields || %{}, fd.key) not in [nil, "", []]}
                      field_def={fd}
                      value={Map.get(record.fields || %{}, fd.key)}
                      members={@members}
                    />
                    <FieldTypeComponent.value
                      :if={record.assignee_id}
                      field_def={@assignee_field_def}
                      value={record.assignee_id}
                      members={@members}
                    />
                  </div>

                  <div :if={@moves[record.id] != []} class="mt-2 flex flex-wrap gap-1">
                    <button
                      :for={move <- @moves[record.id]}
                      type="button"
                      phx-click="move"
                      phx-value-record={record.id}
                      phx-value-to={move.to_state.id}
                      title={requirements_title(move)}
                      class="inline-flex items-center gap-1 rounded bg-notion-gray px-1.5 py-0.5 text-xs text-notion-text transition hover:bg-notion-divider"
                    >
                      → {move.to_state.name}<span :if={move.requirements != []} class="text-notion-text-light">🔒</span>
                    </button>
                  </div>
                </div>

                <p
                  :if={Map.get(@board.columns, state.id, []) == []}
                  class="px-1 py-2 text-xs text-notion-text-light/60"
                >
                  No tasks
                </p>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp record_title(%{title: t}) when is_binary(t) and t != "", do: t
  defp record_title(_), do: "Untitled"

  defp requirements_title(%{requirements: []}), do: nil
  defp requirements_title(%{requirements: reqs}), do: "Requires: " <> Enum.join(reqs, "; ")

  defp category_dot(:backlog), do: "bg-notion-text-light/40"
  defp category_dot(:todo), do: "bg-blue-400"
  defp category_dot(:doing), do: "bg-yellow-400"
  defp category_dot(:review), do: "bg-purple-400"
  defp category_dot(:done), do: "bg-green-500"
  defp category_dot(:canceled), do: "bg-notion-text-light/30"
  defp category_dot(_), do: "bg-notion-text-light/40"

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}
end
