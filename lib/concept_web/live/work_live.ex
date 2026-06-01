defmodule ConceptWeb.WorkLive do
  @moduledoc """
  The pull-model "Work" surface for a workspace member (human or agent):

    * **My work** — every record assigned to me, across all object types,
      grouped by lifecycle category (todo / doing / review / …).
    * **Ready to pick** — unassigned, unblocked records in a `:todo` state,
      across all object types. One click **Claims** a record (assigns it to me)
      and it moves into "My work".

  This is the read counterpart to the board's push model: the board places
  work into columns; here a member finds work to take. Both project the same
  `Concept.Objects` domain (see `work_view/1`), so the MCP `record_ready_all`
  / `record_mine` tools and this LiveView show agents and humans the same set.

  LiveView purity (EX9001): all data access goes through `Concept.Objects` /
  `Concept.Accounts` code-interface fns — no `Ash.Query` / `Ash.Changeset`.
  """
  use ConceptWeb, :live_view



  alias Concept.Accounts
  alias Concept.Objects
  alias Concept.Pages

  # Order categories present in "My work" for a stable, intuitive layout.
  @category_order [:todo, :doing, :review, :backlog, :done, :canceled]

  @impl true
  def mount(%{"workspace_slug" => slug}, _session, socket) do
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
         |> assign(:page_title, "My work")
         |> load_work()}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Workspace not found")
         |> push_navigate(to: ~p"/w")}
    end
  end

  # Workspace-shell events from the shared sidebar → back to the workspace.
  @impl true
  def handle_event(event, _params, socket)
      when event in ~w(open_command_palette toggle_chat new_page) do
    {:noreply, push_navigate(socket, to: ~p"/w/#{socket.assigns.workspace.slug}")}
  end

  def handle_event("escape", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("claim", %{"record" => record_id}, socket) do
    %{workspace: ws} = socket.assigns
    user = socket.assigns.current_user

    with {:ok, record} <- Objects.get_record(record_id, actor: user, tenant: ws.id),
         {:ok, _} <- Objects.assign_record(record, user.id, actor: user, tenant: ws.id) do
      {:noreply, socket |> put_flash(:info, "Claimed") |> load_work()}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not claim this record")}
    end
  end

  defp load_work(socket) do
    %{workspace: ws} = socket.assigns
    user = socket.assigns.current_user

    case Objects.work_view(actor: user, tenant: ws.id) do
      {:ok, %{mine: mine, ready: ready, blocked_ids: blocked_ids}} ->
        socket
        |> assign(:mine_by_category, group_by_category(mine))
        |> assign(:mine_count, length(mine))
        |> assign(:ready, ready)
        |> assign(:blocked_ids, blocked_ids)
        |> assign(:work_error, nil)

      {:error, _} ->
        socket
        |> assign(:mine_by_category, [])
        |> assign(:mine_count, 0)
        |> assign(:ready, [])
        |> assign(:blocked_ids, MapSet.new())
        |> assign(:work_error, "Could not load your work right now.")
    end
  end

  # Returns an ordered list of `{category, [records]}` for stable rendering.
  defp group_by_category(records) do
    grouped = Enum.group_by(records, &record_category/1)

    present =
      @category_order
      |> Enum.filter(&Map.has_key?(grouped, &1))
      |> Enum.map(&{&1, Map.fetch!(grouped, &1)})

    # Any category not in the known order (defensive) appended at the end.
    extra =
      grouped
      |> Map.drop(@category_order)
      |> Enum.to_list()

    present ++ extra
  end

  defp record_category(%{state: %{category: c}}) when is_atom(c), do: c
  defp record_category(_), do: :backlog

  # ── render ───────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.workspace
      id="work-shell"
      flash={@flash}
      current_scope={@current_scope}
      workspace={@workspace}
      pages={@pages}
      current_user={@current_user}
    >
          <div id="work-root" class="mx-auto max-w-5xl p-6">
            <div class="mb-6 flex items-center justify-between">
              <h1 class="text-2xl font-bold text-notion-text">My work</h1>
              <.link
                navigate={~p"/w/#{@workspace.slug}"}
                class="text-sm text-notion-text-light hover:text-notion-text"
              >
                ← Workspace
              </.link>
            </div>

            <%= if @work_error do %>
              <div class="text-notion-text-light">{@work_error}</div>
            <% else %>
              <div class="grid grid-cols-1 gap-8 lg:grid-cols-2">
                <%!-- My work --%>
                <section id="my-work">
                  <h2 class="mb-3 flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-notion-text-light">
                    Assigned to me
                    <span class="rounded-full bg-notion-gray px-1.5 py-0.5 text-notion-text-light">
                      {@mine_count}
                    </span>
                  </h2>

                  <.empty_state
                    :if={@mine_count == 0}
                    icon="✓"
                    title="Nothing assigned to you yet"
                    class="py-8"
                  >
                    Claim something ready from the right to get started.
                  </.empty_state>

                  <div :for={{category, records} <- @mine_by_category} class="mb-5">
                    <div class="mb-1.5 flex items-center gap-1.5 px-1">
                      <span class={["h-2 w-2 rounded-full", category_dot(category)]} />
                      <span class="text-xs font-medium uppercase tracking-wide text-notion-text-light">
                        {category}
                      </span>
                    </div>

                    <ul class="space-y-2">
                      <li
                        :for={record <- records}
                        id={"mine-#{record.id}"}
                        class="rounded-md border border-notion-divider bg-white p-3 shadow-sm"
                      >
                        <div class="flex items-start justify-between gap-2">
                          <span class="text-sm font-medium text-notion-text">
                            {record_title(record)}
                          </span>
                          <span
                            :if={MapSet.member?(@blocked_ids, record.id)}
                            class="shrink-0 rounded bg-red-50 px-1.5 py-0.5 text-xs font-medium text-red-600"
                            title="Waiting on an unfinished dependency"
                          >
                            🚧 Blocked
                          </span>
                        </div>
                        <div class="mt-1.5 flex flex-wrap items-center gap-1.5">
                          <span class="rounded bg-notion-gray px-1.5 py-0.5 text-xs text-notion-text-light">
                            {type_name(record)}
                          </span>
                          <span :if={record.state} class="text-xs text-notion-text-light">
                            {record.state.name}
                          </span>
                        </div>
                      </li>
                    </ul>
                  </div>
                </section>

                <%!-- Ready to pick --%>
                <section id="ready-to-pick">
                  <h2 class="mb-3 flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-notion-text-light">
                    Ready to pick
                    <span class="rounded-full bg-notion-gray px-1.5 py-0.5 text-notion-text-light">
                      {length(@ready)}
                    </span>
                  </h2>

                  <p :if={@ready == []} class="text-sm text-notion-text-light/70">
                    No unclaimed work is ready right now.
                  </p>

                  <ul class="space-y-2">
                    <li
                      :for={record <- @ready}
                      id={"ready-#{record.id}"}
                      class="flex items-center justify-between gap-2 rounded-md border border-notion-divider bg-white p-3 shadow-sm"
                    >
                      <div class="min-w-0">
                        <div class="truncate text-sm font-medium text-notion-text">
                          {record_title(record)}
                        </div>
                        <div class="mt-1 flex flex-wrap items-center gap-1.5">
                          <span class="rounded bg-notion-gray px-1.5 py-0.5 text-xs text-notion-text-light">
                            {type_name(record)}
                          </span>
                          <span :if={record.state} class="text-xs text-notion-text-light">
                            {record.state.name}
                          </span>
                        </div>
                      </div>
                      <button
                        type="button"
                        phx-click="claim"
                        phx-value-record={record.id}
                        class="shrink-0 rounded-md bg-notion-text px-2.5 py-1 text-xs font-medium text-white transition hover:opacity-80"
                      >
                        Claim
                      </button>
                    </li>
                  </ul>
                </section>
              </div>
            <% end %>
          </div>
    </Layouts.workspace>
    """
  end

  defp record_title(%{title: t}) when is_binary(t) and t != "", do: t
  defp record_title(_), do: "Untitled"

  defp type_name(%{object_type: %{name: n}}) when is_binary(n), do: n
  defp type_name(_), do: "Record"

  defp category_dot(:backlog), do: "bg-notion-text-light/40"
  defp category_dot(:todo), do: "bg-blue-400"
  defp category_dot(:doing), do: "bg-yellow-400"
  defp category_dot(:review), do: "bg-purple-400"
  defp category_dot(:done), do: "bg-green-500"
  defp category_dot(:canceled), do: "bg-notion-text-light/30"
  defp category_dot(_), do: "bg-notion-text-light/40"
end
