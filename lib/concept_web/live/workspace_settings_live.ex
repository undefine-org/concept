defmodule ConceptWeb.WorkspaceSettingsLive do
  @moduledoc """
  Workspace settings shell: Members and API keys (tabbed).

  LiveView purity (EX9001): all data access goes through
  `Concept.Accounts` code-interface fns — no `Ash.Query`/`Ash.Changeset` here.
  """
  use ConceptWeb, :live_view

  alias Concept.Accounts

  @tabs [
    {"members", "Members"},
    {"api_keys", "API keys"}
  ]

  @role_whitelist %{
    "owner" => :owner,
    "admin" => :admin,
    "member" => :member,
    "agent" => :agent
  }

  # ── lifecycle ────────────────────────────────────────────────────────

  @impl true
  def mount(%{"workspace_slug" => slug}, _session, socket) do
    user = socket.assigns.current_user

    case Accounts.Workspace.by_slug(slug, actor: user) do
      {:ok, ws} ->
        {:ok,
         socket
         |> assign(:workspace, ws)
         |> assign(:tab, "members")
         |> assign(:tabs, @tabs)
         |> assign(:new_plaintext, nil)
         |> load_members()
         |> load_api_keys()}

      _ ->
        {:ok, socket |> put_flash(:error, "Workspace not found") |> push_navigate(to: ~p"/w")}
    end
  end

  # ── events ───────────────────────────────────────────────────────────

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, socket |> assign(:tab, tab) |> assign(:new_plaintext, nil)}
  end

  def handle_event("add_member", %{"email" => email}, socket) do
    %{workspace: ws} = socket.assigns
    user = socket.assigns.current_user

    case Accounts.add_member(ws.id, String.trim(email), actor: user, tenant: ws.id) do
      {:ok, _} ->
        {:noreply, socket |> load_members() |> put_flash(:info, "Member added")}

      {:error, :user_not_found} ->
        {:noreply, put_flash(socket, :error, "No user with that email")}

      {:error, :already_member} ->
        {:noreply, put_flash(socket, :error, "User is already a member")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not add member")}
    end
  end

  def handle_event("set_role", %{"membership_id" => id, "role" => role_str}, socket) do
    %{workspace: ws, members: members} = socket.assigns
    user = socket.assigns.current_user

    case Map.fetch(@role_whitelist, role_str) do
      {:ok, role} ->
        membership = Enum.find(members, &(&1.id == id))

        if membership do
          case Accounts.set_member_role(membership, role, actor: user, tenant: ws.id) do
            {:ok, _} -> {:noreply, load_members(socket)}
            {:error, _} -> {:noreply, put_flash(socket, :error, "Could not update role")}
          end
        else
          {:noreply, socket}
        end

      :error ->
        {:noreply, put_flash(socket, :error, "Invalid role")}
    end
  end

  def handle_event("issue_key", %{"name" => name}, socket) do
    %{workspace: ws} = socket.assigns
    user = socket.assigns.current_user

    case Accounts.issue_api_key(ws.id, %{name: String.trim(name)}, actor: user, tenant: ws.id) do
      {:ok, %{api_key: _key, plaintext: plaintext}} ->
        {:noreply,
         socket
         |> assign(:new_plaintext, plaintext)
         |> load_api_keys()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not issue API key")}
    end
  end

  def handle_event("revoke_key", %{"id" => id}, socket) do
    %{workspace: ws, api_keys: keys} = socket.assigns
    user = socket.assigns.current_user

    key = Enum.find(keys, &(&1.id == id))

    if key do
      case Accounts.revoke_api_key(key, actor: user, tenant: ws.id) do
        :ok -> {:noreply, socket |> assign(:new_plaintext, nil) |> load_api_keys()}
        {:error, _} -> {:noreply, put_flash(socket, :error, "Could not revoke key")}
      end
    else
      {:noreply, socket}
    end
  end

  # Catch-all: ignore any unhandled events rather than crashing the LV.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # ── data loading (code-interface only) ───────────────────────────────

  defp load_members(socket) do
    %{workspace: ws} = socket.assigns
    user = socket.assigns.current_user

    case Accounts.list_members(ws.id, actor: user, tenant: ws.id) do
      {:ok, members} -> assign(socket, :members, members)
      _ -> assign(socket, :members, [])
    end
  end

  defp load_api_keys(socket) do
    %{workspace: ws} = socket.assigns
    user = socket.assigns.current_user

    case Accounts.list_api_keys(ws.id, actor: user, tenant: ws.id) do
      {:ok, keys} -> assign(socket, :api_keys, keys)
      _ -> assign(socket, :api_keys, [])
    end
  end

  # ── render ───────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="settings-root" class="mx-auto max-w-3xl p-6">
        <div class="mb-6 flex items-center justify-between">
          <h1 class="text-2xl font-bold text-notion-text">Settings</h1>
          <.link
            navigate={~p"/w/#{@workspace.slug}"}
            class="text-sm text-notion-text-light hover:text-notion-text"
          >
            ← Workspace
          </.link>
        </div>

        <div class="flex gap-4 border-b border-notion-divider mb-6">
          <button
            :for={{id, label} <- @tabs}
            type="button"
            phx-click="switch_tab"
            phx-value-tab={id}
            class={[
              "px-3 py-2 text-sm font-medium border-b-2 -mb-px transition-colors",
              if(@tab == id,
                do: "border-notion-text text-notion-text",
                else: "border-transparent text-notion-text-light hover:text-notion-text"
              )
            ]}
          >
            {label}
          </button>
        </div>

        <%= case @tab do %>
          <% "members" -> %>
            {members_tab(assigns)}
          <% "api_keys" -> %>
            {api_keys_tab(assigns)}
          <% _ -> %>
            <div></div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  def members_tab(assigns) do
    ~H"""
    <div id="members-tab">
      <form phx-submit="add_member" id="add-member-form" class="mb-6 flex gap-2">
        <input
          type="email"
          name="email"
          placeholder="Email address…"
          autocomplete="off"
          required
          class="flex-1 rounded-md border border-notion-divider px-3 py-1.5 text-sm focus:border-notion-text focus:outline-none"
        />
        <button
          type="submit"
          class="rounded-md bg-notion-text px-3 py-1.5 text-sm font-medium text-white transition hover:opacity-80"
        >
          Add member
        </button>
      </form>

      <ul class="divide-y divide-notion-divider rounded-lg border border-notion-divider">
        <li
          :for={member <- @members}
          id={"member-#{member.id}"}
          class="flex items-center justify-between px-4 py-3"
        >
          <span class="text-sm text-notion-text">{member.user.email}</span>
          <div class="flex items-center gap-2">
            <span class={[
              "rounded px-1.5 py-0.5 text-xs font-medium capitalize",
              role_badge_class(member.role)
            ]}>
              {member.role}
            </span>
            <form phx-change="set_role" phx-value-membership_id={member.id}>
              <select
                name="role"
                id={"role-select-#{member.id}"}
                class="rounded border border-notion-divider px-2 py-1 text-xs bg-white"
              >
                <option
                  :for={
                    {label, val} <- [
                      {"Owner", "owner"},
                      {"Admin", "admin"},
                      {"Member", "member"},
                      {"Agent", "agent"}
                    ]
                  }
                  value={val}
                  selected={to_string(member.role) == val}
                >
                  {label}
                </option>
              </select>
            </form>
          </div>
        </li>
        <li :if={@members == []} class="px-4 py-6 text-center text-sm text-notion-text-light">
          No members yet.
        </li>
      </ul>
    </div>
    """
  end

  def api_keys_tab(assigns) do
    ~H"""
    <div id="api-keys-tab">
      <form phx-submit="issue_key" id="issue-key-form" class="mb-6 flex gap-2">
        <input
          type="text"
          name="name"
          placeholder="Key name…"
          autocomplete="off"
          required
          class="flex-1 rounded-md border border-notion-divider px-3 py-1.5 text-sm focus:border-notion-text focus:outline-none"
        />
        <button
          type="submit"
          class="rounded-md bg-notion-text px-3 py-1.5 text-sm font-medium text-white transition hover:opacity-80"
        >
          Issue key
        </button>
      </form>

      <div
        :if={@new_plaintext}
        id="new-plaintext-box"
        class="mb-6 rounded-lg border border-yellow-200 bg-yellow-50 p-4"
      >
        <p class="mb-2 text-sm font-medium text-yellow-800">
          Copy this key now — it will be shown only once.
        </p>
        <div class="flex items-center gap-2">
          <code class="flex-1 rounded bg-white px-3 py-2 text-sm break-all border border-yellow-200">
            {@new_plaintext}
          </code>
        </div>
      </div>

      <ul class="divide-y divide-notion-divider rounded-lg border border-notion-divider">
        <li
          :for={key <- @api_keys}
          id={"api-key-#{key.id}"}
          class="flex items-center justify-between px-4 py-3"
        >
          <div class="flex flex-col">
            <span class="text-sm font-medium text-notion-text">
              {Map.get(key, :name) || "Untitled"}
            </span>
            <span class="text-xs text-notion-text-light">
              <%= if inserted_at = Map.get(key, :inserted_at) do %>
                Created {format_datetime(inserted_at)} ·
              <% end %>
              <%= if expires_at = Map.get(key, :expires_at) do %>
                Expires {format_datetime(expires_at)}
              <% else %>
                Never expires
              <% end %>
            </span>
          </div>
          <button
            type="button"
            id={"revoke-key-#{key.id}"}
            phx-click="revoke_key"
            phx-value-id={key.id}
            class="rounded border border-notion-divider px-2 py-1 text-xs text-red-600 hover:bg-red-50"
          >
            Revoke
          </button>
        </li>
        <li :if={@api_keys == []} class="px-4 py-6 text-center text-sm text-notion-text-light">
          No API keys yet.
        </li>
      </ul>
    </div>
    """
  end

  # ── helpers ──────────────────────────────────────────────────────────

  defp role_badge_class(:agent), do: "bg-purple-100 text-purple-800"
  defp role_badge_class(:owner), do: "bg-yellow-100 text-yellow-800"
  defp role_badge_class(_), do: "bg-notion-gray text-notion-text-light"

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  end

  defp format_datetime(_), do: "-"
end
