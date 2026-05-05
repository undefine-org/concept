defmodule ConceptWeb.PageEditorLive do
  @moduledoc "LiveView for editing a single page's blocks."
  use ConceptWeb, :live_view

  alias Concept.Pages

  require Logger

  @impl true
  def mount(_params, session, socket) do
    ws_id = session["workspace_id"]
    page_id = session["page_id"]
    user_id = session["user_id"]

    user = socket.assigns[:current_user] || %{id: user_id}
    ws = %{id: ws_id}

    Phoenix.PubSub.subscribe(Concept.PubSub, "workspace:#{ws_id}:page:#{page_id}:blocks")
    Phoenix.PubSub.subscribe(Concept.PubSub, "workspace:#{ws_id}:page:#{page_id}:presence")

    ConceptWeb.Presence.track(self(), "workspace:#{ws_id}:page:#{page_id}:presence", user.id, %{
      display_name: user.email |> to_string |> String.split("@") |> hd,
      online_at: System.system_time(:second),
      color: ConceptWeb.Colors.for_user_id(user.id)
    })

    blocks =
      case Pages.list_for_page(page_id, actor: user, tenant: ws_id) do
        {:ok, list} -> list
        _ -> []
      end

    socket =
      socket
      |> assign(:workspace, ws)
      |> assign(:page_id, page_id)
      |> assign(:current_user, user)
      |> assign(:blocks, blocks)
      |> assign(:held_locks, %{})
      |> assign(:presence_users, [])

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-1">
      <ul :if={@blocks != []} class="space-y-1">
        <li :for={b <- @blocks}>
          <ConceptWeb.BlockRender.block block={b} />
        </li>
      </ul>
      <div :if={@blocks == []} class="py-8 text-center">
        <button
          phx-click="add_first_block"
          class="text-notion-text-light hover:text-notion-text transition-colors cursor-pointer"
        >
          + Click to add your first block
        </button>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("focus_block", %{"block_id" => id}, socket) do
    user = socket.assigns.current_user
    ws_id = socket.assigns.workspace.id

    case Pages.acquire_lock(id, %{user_id: user.id, ttl_seconds: 30}, actor: user, tenant: ws_id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:held_locks, Map.put(socket.assigns.held_locks, id, true))
         |> push_event("lock_granted", %{block_id: id})}

      {:error, %{constraint: "lock_held_by_other"}} ->
        {:noreply, push_event(socket, "lock_denied", %{block_id: id})}

      _ ->
        {:noreply, push_event(socket, "lock_denied", %{block_id: id})}
    end
  end

  @impl true
  def handle_event("blur_block", %{"block_id" => id}, socket) do
    socket = release_if_held(socket, id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("save_content", %{"block_id" => id, "state" => json_string}, socket) do
    user = socket.assigns.current_user
    ws_id = socket.assigns.workspace.id

    case Jason.decode(json_string) do
      {:ok, content} ->
        block = Enum.find(socket.assigns.blocks, &(&1.id == id))

        if block do
          case Pages.update_content(block, content, actor: user, tenant: ws_id) do
            {:ok, _} -> :ok
            {:error, error} -> Logger.warning("Block save failed: #{inspect(error)}")
          end
        end

        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("refresh_lock", %{"block_id" => id}, socket) do
    user = socket.assigns.current_user
    ws_id = socket.assigns.workspace.id

    if socket.assigns.held_locks[id] do
      Pages.refresh_lock(id, %{user_id: user.id, ttl_seconds: 30}, actor: user, tenant: ws_id)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("add_first_block", _params, socket) do
    user = socket.assigns.current_user
    ws_id = socket.assigns.workspace.id
    page_id = socket.assigns.page_id

    case Pages.create_block(page_id, :paragraph, ws_id, nil, actor: user, tenant: ws_id) do
      {:ok, block} ->
        {:noreply, assign(socket, :blocks, [block])}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not create block: #{inspect(error)}")}
    end
  end

  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{event: "block_updated", payload: notification},
        socket
      ) do
    block = notification.data
    updater = notification.actor

    socket =
      if updater && updater.id != socket.assigns.current_user.id do
        socket =
          cond do
            block.lock_state == :locked && block.lock_holder_id != socket.assigns.current_user.id ->
              push_event(socket, "set_locked_by", %{
                block_id: block.id,
                user_id: block.lock_holder_id,
                color: ConceptWeb.Colors.for_user_id(block.lock_holder_id)
              })

            block.lock_state == :unlocked ->
              push_event(socket, "lock_granted", %{block_id: block.id})

            true ->
              socket
          end

        push_event(socket, "apply_remote", %{block_id: block.id, state: block.content})
      else
        socket
      end

    blocks =
      Enum.map(socket.assigns.blocks, fn b ->
        if b.id == block.id, do: block, else: b
      end)

    {:noreply, assign(socket, :blocks, blocks)}
  end

  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{event: "block_created", payload: notification},
        socket
      ) do
    block = notification.data
    blocks = socket.assigns.blocks ++ [block]
    {:noreply, assign(socket, :blocks, blocks)}
  end

  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{event: "block_archived", payload: notification},
        socket
      ) do
    block = notification.data
    blocks = Enum.reject(socket.assigns.blocks, &(&1.id == block.id))
    {:noreply, assign(socket, :blocks, blocks)}
  end

  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{event: "presence_diff", payload: _payload},
        socket
      ) do
    presence_list =
      ConceptWeb.Presence.list(
        "workspace:#{socket.assigns.workspace.id}:page:#{socket.assigns.page_id}:presence"
      )

    users =
      Enum.map(presence_list, fn {user_id, %{metas: metas}} ->
        meta = List.first(metas)

        %{
          id: user_id,
          display_name: meta.display_name,
          color: meta.color,
          online_at: meta.online_at
        }
      end)
      |> Enum.uniq_by(& &1.id)

    {:noreply, assign(socket, :presence_users, users)}
  end

  @impl true
  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def terminate(_reason, socket) do
    for {id, true} <- socket.assigns.held_locks do
      release_if_held(socket, id)
    end

    :ok
  end

  defp release_if_held(socket, id) do
    if socket.assigns.held_locks[id] do
      user = socket.assigns.current_user
      ws_id = socket.assigns.workspace.id

      case Pages.release_lock(id, actor: user, tenant: ws_id) do
        {:ok, _} -> assign(socket, :held_locks, Map.delete(socket.assigns.held_locks, id))
        _ -> socket
      end
    else
      socket
    end
  end
end
