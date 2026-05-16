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

    user =
      socket.assigns[:current_user] || %{id: user_id, email: session["user_email"] || "unknown"}

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
    <div class="space-y-1 relative">
      <ul :if={@blocks != []} id={"block-list-#{@page_id}"} phx-hook="BlockList" class="space-y-1">
        <li :for={b <- @blocks} data-block-id={b.id}>
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
      <div id="format-toolbar-host" phx-hook="FormatToolbar" phx-update="ignore" class="ora-format-host">
        <ora-format-toolbar />
        <ora-link-editor />
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("focus_block", %{"block_id" => id}, socket) do
    user = socket.assigns.current_user
    ws_id = socket.assigns.workspace.id

    block = Enum.find(socket.assigns.blocks, &(&1.id == id))

    self_held? =
      Map.get(socket.assigns.held_locks, id) ||
        (block && block.lock_state == :locked && block.lock_holder_id == user.id)

    lock_result =
      cond do
        self_held? ->
          Pages.refresh_lock(id, %{user_id: user.id, ttl_seconds: 30}, actor: user, tenant: ws_id)

        block && block.lock_state == :locked ->
          {:error, :lock_held_by_other}

        true ->
          Pages.acquire_lock(id, %{user_id: user.id, ttl_seconds: 30}, actor: user, tenant: ws_id)
      end

    case lock_result do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:held_locks, Map.put(socket.assigns.held_locks, id, true))
         |> push_event("lock_granted", %{block_id: id})}

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
        {:noreply,
         socket
         |> assign(:blocks, [block])
         |> push_event("focus_block_caret", %{block_id: block.id, position: "start"})}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not create block: #{inspect(error)}")}
    end
  end

  @impl true
  def handle_event("insert_paragraph_below", %{"block_id" => source_id}, socket) do
    user = socket.assigns.current_user
    ws_id = socket.assigns.workspace.id
    page_id = socket.assigns.page_id
    blocks = socket.assigns.blocks

    source_idx = Enum.find_index(blocks, &(&1.id == source_id))

    socket =
      if source_idx do
        source = Enum.at(blocks, source_idx)
        next_block = Enum.at(blocks, source_idx + 1)

        position =
          if next_block do
            Concept.Pages.FractionalIndex.between(source.position, next_block.position)
          else
            Concept.Pages.FractionalIndex.after_(source.position)
          end

        case Pages.create_block(page_id, :paragraph, ws_id, nil, %{position: position},
               actor: user,
               tenant: ws_id
             ) do
          {:ok, new_block} ->
            socket
            |> assign(:blocks, List.insert_at(blocks, source_idx + 1, new_block))
            |> push_event("focus_block_caret", %{
              block_id: new_block.id,
              position: "start"
            })

          {:error, _error} ->
            socket
        end
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("reorder_block", %{"block_id" => block_id, "prev_id" => prev_id, "next_id" => next_id}, socket) do
    user = socket.assigns.current_user
    ws_id = socket.assigns.workspace.id
    blocks = socket.assigns.blocks

    block = Enum.find(blocks, &(&1.id == block_id))

    if is_nil(block) do
      {:noreply, socket}
    else
      prev_block = prev_id && Enum.find(blocks, &(&1.id == prev_id))
      next_block = next_id && Enum.find(blocks, &(&1.id == next_id))

      new_position =
        cond do
          prev_block && next_block ->
            Concept.Pages.FractionalIndex.between(prev_block.position, next_block.position)

          prev_block && is_nil(next_block) ->
            Concept.Pages.FractionalIndex.after_(prev_block.position)

          is_nil(prev_block) && next_block ->
            Concept.Pages.FractionalIndex.before_(next_block.position)

          true ->
            Concept.Pages.FractionalIndex.initial()
        end

      if new_position == block.position do
        {:noreply, socket}
      else
        case Pages.reorder_block(block, new_position, actor: user, tenant: ws_id) do
          {:ok, updated_block} ->
            blocks =
              blocks
              |> Enum.map(fn b -> if b.id == block_id, do: updated_block, else: b end)
              |> Enum.sort_by(& &1.position)

            {:noreply, assign(socket, :blocks, blocks)}

          {:error, _} ->
            {:noreply, socket}
        end
      end
    end
  end

  @impl true
  def handle_event("nav_block", %{"direction" => direction, "block_id" => block_id}, socket) do
    blocks = socket.assigns.blocks
    idx = Enum.find_index(blocks, &(&1.id == block_id))

    socket =
      cond do
        is_nil(idx) ->
          socket

        direction == "down" && idx < length(blocks) - 1 ->
          next = Enum.at(blocks, idx + 1)
          push_event(socket, "focus_block_caret", %{block_id: next.id, position: "start"})

        direction == "up" && idx > 0 ->
          prev = Enum.at(blocks, idx - 1)
          push_event(socket, "focus_block_caret", %{block_id: prev.id, position: "end"})

        true ->
          socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("delete_block_merge", %{"block_id" => block_id}, socket) do
    user = socket.assigns.current_user
    ws_id = socket.assigns.workspace.id
    blocks = socket.assigns.blocks

    idx = Enum.find_index(blocks, &(&1.id == block_id))

    socket =
      cond do
        # No-op if only block or not found
        is_nil(idx) or length(blocks) <= 1 ->
          socket

        true ->
          block = Enum.at(blocks, idx)

          case Pages.archive_block(block, actor: user, tenant: ws_id) do
            {:ok, _archived} ->
              previous_block = Enum.at(blocks, idx - 1)

              if previous_block do
                push_event(socket, "focus_block_caret", %{
                  block_id: previous_block.id,
                  position: "end"
                })
              else
                socket
              end

            {:error, _error} ->
              socket
          end
      end

    {:noreply, socket}
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

    # Dedup: handle_event paths (add_first_block, insert_paragraph_below)
    # already inserted the block locally; broadcast is the path for *other*
    # users' inserts.
    if Enum.any?(socket.assigns.blocks, &(&1.id == block.id)) do
      {:noreply, socket}
    else
      blocks =
        (socket.assigns.blocks ++ [block])
        |> Enum.sort_by(& &1.position)

      {:noreply, assign(socket, :blocks, blocks)}
    end
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
