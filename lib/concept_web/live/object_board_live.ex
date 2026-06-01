defmodule ConceptWeb.ObjectBoardLive do
  @moduledoc """
  The generic record board for **any** object type: columns by workflow state,
  create a record into the initial state, move records along their workflow's
  guarded transitions, and open a record in the detail slide-over.

  Two live actions, one surface:

    * `:tasks` @ `/w/:slug/tasks` — the built-in Task type (`Objects.task_board/1`).
    * `:board` @ `/w/:slug/o/:type_id` — any type (`Objects.object_board/2`).

  This is the database-builder thesis made reachable by humans: invent a type
  in the editor, and it gets a working board here — the same `Objects` actions
  the `create_<type>` MCP tool drives, same policies, same data. The Task board
  is just the seeded instance of this one surface (no parallel implementation).

  LiveView purity (EX9001): all data access goes through `Concept.Objects` /
  `Concept.Accounts` code-interface fns — no `Ash.Query` / `Ash.Changeset`.
  """
  use ConceptWeb, :live_view

  import ConceptWeb.Components.Sidebar

  alias Concept.Accounts
  alias Concept.Objects
  alias Concept.Pages
  alias ConceptWeb.Objects.FieldTypeComponent

  @impl true
  def mount(%{"workspace_slug" => slug} = params, _session, socket) do
    user = socket.assigns.current_user

    case Accounts.Workspace.by_slug(slug, actor: user) do
      {:ok, ws} ->
        pages =
          case Pages.list_tree(actor: user, tenant: ws.id) do
            {:ok, list} -> list
            _ -> []
          end

        {:ok,
         socket
         |> assign(:workspace, ws)
         |> assign(:pages, pages)
         |> assign(:type_id, params["type_id"])
         |> assign(:new_title, "")
         |> assign(:assignee_field_def, %{field_type: :user, config: %{}, key: "assignee"})
         |> assign(:open_record_id, nil)
         |> load_board()}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Workspace not found")
         |> push_navigate(to: ~p"/w")}
    end
  end

  # Sidebar/GlobalKeys events that belong to the workspace shell. From a board,
  # these navigate back to the workspace where command palette / chat / new-page
  # live, rather than being dead. Keeps the sidebar a single component without
  # duplicating its full machinery onto every standalone surface.
  @impl true
  def handle_event(event, _params, socket)
      when event in ~w(open_command_palette toggle_chat new_page) do
    {:noreply, push_navigate(socket, to: ~p"/w/#{socket.assigns.workspace.slug}")}
  end

  def handle_event("escape", _params, socket) do
    {:noreply, socket}
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
          {:noreply, put_flash(socket, :error, "Could not create #{type_label(type)}")}
      end
    end
  end

  def handle_event("open_record", %{"record" => record_id}, socket) do
    {:noreply, assign(socket, :open_record_id, record_id)}
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
        {:noreply, put_flash(socket, :error, "Could not move record")}
    end
  end

  # ── data loading (code-interface only) ───────────────────────────────

  defp load_board(socket) do
    %{workspace: ws, type_id: type_id} = socket.assigns
    user = socket.assigns.current_user

    result =
      if is_binary(type_id) do
        Objects.object_board(type_id, actor: user, tenant: ws.id)
      else
        Objects.task_board(actor: user, tenant: ws.id)
      end

    case result do
      {:ok, board} ->
        moves =
          board.columns
          |> Map.values()
          |> List.flatten()
          |> Map.new(fn r -> {r.id, Objects.moves_for(r, board)} end)

        socket
        |> assign(:board, board)
        |> assign(:page_title, board_title(socket.assigns.live_action, board.type))
        |> assign(:moves, moves)
        |> assign(:members, load_members(ws.id, user))
        |> assign(:card_fields, card_fields(board.field_defs))
        |> assign(:board_error, nil)

      {:error, :no_task_type} ->
        empty_board(socket, "No Task type in this workspace yet.")

      {:error, _other} ->
        empty_board(socket, "Could not load this board.")
    end
  end

  defp empty_board(socket, message) do
    socket
    |> assign(board: nil, moves: %{}, members: [], card_fields: [], board_error: message)
    |> assign_new(:page_title, fn -> "Board" end)
  end

  # Members feed the :user field renderer + assignee avatars. Defensive: the
  # board still renders if membership loading fails.
  defp load_members(ws_id, user) do
    with {:ok, memberships} <- Accounts.Membership.list_for_workspace(ws_id, actor: user),
         ids = Enum.map(memberships, & &1.user_id),
         {:ok, users} <- Accounts.list_users_by_ids(ids) do
      users
    else
      _ -> []
    end
  end

  # Heuristic (design doc §3.3): show select + user fields on cards (priority,
  # etc.), excluding the title (the card heading).
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

  defp type_label(%{name: name}) when is_binary(name), do: String.downcase(name)
  defp type_label(_), do: "record"

  # ── render ───────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.shell flash={@flash} current_scope={@current_scope}>
      <div id="board-root" class="flex min-h-screen" phx-hook="GlobalKeys">
        <.sidebar workspace={@workspace} pages={@pages} current_user={@current_user} />
        <main class="flex-1 overflow-y-auto bg-notion-bg">
      <div id="tasks-root" class="p-6">
        <div class="flex items-center justify-between mb-6">
          <h1 class="text-2xl font-bold text-notion-text">
            {@page_title}
          </h1>
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
              placeholder={"New #{type_label(@board.type)}…"}
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
                  phx-click="open_record"
                  phx-value-record={record.id}
                  class="group cursor-pointer rounded-md border border-notion-divider bg-white p-2.5 shadow-sm transition hover:shadow-md"
                >
                  <div class="flex items-start justify-between gap-2">
                    <span class="text-sm font-medium text-notion-text">{record_title(record)}</span>
                    <span
                      :if={MapSet.member?(@board.blocked_ids, record.id)}
                      class="shrink-0 rounded bg-red-50 px-1.5 py-0.5 text-xs font-medium text-red-600"
                      title="Waiting on an unfinished dependency"
                    >
                      🚧
                    </span>
                  </div>

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
                      phx-click={JS.push("move")}
                      phx-value-record={record.id}
                      phx-value-to={move.to_state.id}
                      title={requirements_title(move)}
                      onclick="event.stopPropagation()"
                      class="inline-flex items-center gap-1 rounded bg-notion-gray px-1.5 py-0.5 text-xs text-notion-text transition hover:bg-notion-divider"
                    >
                      → {move.to_state.name}<span
                        :if={move.requirements != []}
                        class="text-notion-text-light"
                      >🔒</span>
                    </button>
                  </div>
                </div>

                <p
                  :if={Map.get(@board.columns, state.id, []) == []}
                  class="px-1 py-2 text-xs text-notion-text-light/60"
                >
                  No {type_label(@board.type)}s
                </p>
              </div>
            </div>
          </div>
        <% end %>

        <.live_component
          :if={@open_record_id}
          module={ConceptWeb.Objects.RecordDetailComponent}
          id={"record-detail-#{@open_record_id}"}
          record_id={@open_record_id}
          workspace={@workspace}
          current_user={@current_user}
          members={@members}
          field_defs={@board.field_defs}
          board={@board}
        />
      </div>
      </main>
      </div>
    </Layouts.shell>
    """
  end

  # The built-in Task board keeps its canonical "Tasks" heading; any other
  # type's board is titled by the type's own name (e.g. "Customer").
  defp board_title(:tasks, _type), do: "Tasks"
  defp board_title(_action, %{name: name}) when is_binary(name), do: name
  defp board_title(_action, _type), do: "Board"

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
  def handle_info(:close_record_detail, socket) do
    {:noreply, assign(socket, :open_record_id, nil)}
  end

  def handle_info(:record_changed, socket) do
    {:noreply, load_board(socket)}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}
end
