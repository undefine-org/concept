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
        {:ok, list} -> build_block_tree(list)
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
      |> assign(:locked_blocks, %{})

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="page-editor-root" phx-hook=".PageScroll">
      <div id="page-editor-content" class="space-y-1 relative" phx-hook="AskSelection">
        <ul :if={@blocks != []} id={"block-list-#{@page_id}"} phx-hook="BlockList" class="space-y-1">
          <li :for={b <- @blocks} data-block-id={b.id}>
            <ConceptWeb.BlockRender.block
              block={b}
              locked_by={@locked_blocks[b.id]}
              locked_blocks={@locked_blocks}
            />
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
        <div
          id="format-toolbar-host"
          phx-hook="FormatToolbar"
          phx-update="ignore"
          class="ora-format-host"
        >
          <ora-format-toolbar />
          <ora-link-editor />
        </div>
        <div
          id="slash-menu-host"
          phx-hook="SlashMenu"
          phx-update="ignore"
        >
          <ora-slash-menu />
        </div>
        <ConceptWeb.CompositePicker.picker id="composite-picker" />
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".PageScroll">
        export default {
          mounted() {
            this.scrollToHash()
            this.hashHandler = () => this.scrollToHash()
            this.titleEnterHandler = () => this.focusFirstBlock()
            window.addEventListener('hashchange', this.hashHandler)
            window.addEventListener('ora:title-enter', this.titleEnterHandler)
            this.handleEvent('scroll_to_block', ({block_id}) => this.flashBlock(`block-${block_id}`))
          },
          destroyed() {
            window.removeEventListener('hashchange', this.hashHandler)
            window.removeEventListener('ora:title-enter', this.titleEnterHandler)
          },
          focusFirstBlock() {
            const first = this.el.querySelector('ora-block')
            if (!first) {
              this.pushEvent('add_first_block', {})
              return
            }
            // Place caret at the start of the first block's contenteditable.
            const editable = first.querySelector('[contenteditable="true"]') ||
                             first.querySelector('[data-editor]')
            if (editable) {
              editable.focus()
              const sel = window.getSelection()
              const range = document.createRange()
              range.selectNodeContents(editable)
              range.collapse(true)
              sel.removeAllRanges()
              sel.addRange(range)
            }
          },
          scrollToHash() {
            const hash = window.location.hash
            if (!hash.startsWith('#block-')) return
            this.flashBlock(hash.slice(1))
          },
          flashBlock(elementId) {
            const el = document.getElementById(elementId)
            if (!el) return
            el.scrollIntoView({behavior: 'smooth', block: 'center'})
            el.classList.add('ora-block-flash')
            setTimeout(() => el.classList.remove('ora-block-flash'), 1600)
          }
        }
      </script>
    </div>
    """
  end

  @impl true
  def handle_event("focus_block", %{"block_id" => id} = params, socket) do
    user = socket.assigns.current_user
    ws_id = socket.assigns.workspace.id
    page_id = socket.assigns.page_id

    block = Enum.find(socket.assigns.blocks, &(&1.id == id))

    # Broadcast focus event for live citation rail
    if text = Map.get(params, "text") do
      Phoenix.PubSub.broadcast(
        Concept.PubSub,
        "workspace:#{ws_id}:focus_block",
        {:focus_block, id, text, page_id}
      )
    end

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
        topic = "workspace:#{ws_id}:page:#{page_id}:presence"

        ConceptWeb.Presence.update(self(), topic, user.id, fn meta ->
          Map.put(meta, :locked_block_id, id)
        end)

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
    user = socket.assigns.current_user
    ws_id = socket.assigns.workspace.id
    page_id = socket.assigns.page_id
    topic = "workspace:#{ws_id}:page:#{page_id}:presence"

    ConceptWeb.Presence.update(self(), topic, user.id, fn meta ->
      Map.delete(meta, :locked_block_id)
    end)

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
  def handle_event("insert_paragraph_below", payload, socket) do
    handle_event("insert_block_below", Map.put(payload, "type", "paragraph"), socket)
  end

  @impl true
  def handle_event("insert_block_below", %{"block_id" => source_id, "type" => type_str}, socket) do
    user = socket.assigns.current_user
    ws_id = socket.assigns.workspace.id
    page_id = socket.assigns.page_id
    blocks = socket.assigns.blocks

    source_idx = Enum.find_index(blocks, &(&1.id == source_id))

    socket =
      if source_idx do
        case Concept.Pages.BlockTypes.resolve(type_str) do
          {:ok, type_atom} ->
            source = Enum.at(blocks, source_idx)
            next_block = Enum.at(blocks, source_idx + 1)

            position =
              if next_block do
                Concept.Pages.FractionalIndex.between(source.position, next_block.position)
              else
                Concept.Pages.FractionalIndex.after_(source.position)
              end

            case Pages.create_block(page_id, type_atom, ws_id, nil, %{position: position},
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

          {:error, :unknown_type} ->
            socket
        end
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("nav_block_tab", %{"block_id" => block_id, "direction" => direction}, socket)
      when direction in ["next", "prev"] do
    user = socket.assigns.current_user
    ws_id = socket.assigns.workspace.id
    page_id = socket.assigns.page_id

    siblings =
      with {:ok, flat} <- Pages.list_for_page(page_id, actor: user, tenant: ws_id),
           current when not is_nil(current) <- Enum.find(flat, &(&1.id == block_id)),
           parent_id when not is_nil(parent_id) <- current.parent_block_id do
        flat
        |> Enum.filter(&(&1.parent_block_id == parent_id))
        |> Enum.sort_by(& &1.position)
      else
        _ -> []
      end

    target =
      case Enum.find_index(siblings, &(&1.id == block_id)) do
        nil ->
          nil

        idx when direction == "next" ->
          Enum.at(siblings, idx + 1)

        idx when direction == "prev" and idx > 0 ->
          Enum.at(siblings, idx - 1)

        _ ->
          nil
      end

    socket =
      if target do
        push_event(socket, "focus_block_caret", %{
          block_id: target.id,
          position: if(direction == "next", do: "start", else: "end")
        })
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("insert_composite_below", %{"type" => type_str} = payload, socket)
      when type_str in ["table", "columns"] do
    user = socket.assigns.current_user
    ws_id = socket.assigns.workspace.id
    page_id = socket.assigns.page_id
    blocks = socket.assigns.blocks
    source_id = Map.get(payload, "block_id")

    source = source_id && Enum.find(blocks, &(&1.id == source_id))
    source_idx = source && Enum.find_index(blocks, &(&1.id == source_id))

    position =
      cond do
        is_nil(source) ->
          nil

        true ->
          next_block = Enum.at(blocks, source_idx + 1)

          if next_block do
            Concept.Pages.FractionalIndex.between(source.position, next_block.position)
          else
            Concept.Pages.FractionalIndex.after_(source.position)
          end
      end

    result =
      case type_str do
        "table" ->
          rows = payload |> Map.get("rows", 2) |> ensure_int(2)
          cols = payload |> Map.get("cols", 2) |> ensure_int(2)

          Pages.create_table(ws_id, page_id, rows, cols,
            actor: user,
            tenant: ws_id,
            position: position
          )

        "columns" ->
          count = payload |> Map.get("count", 2) |> ensure_int(2)

          Pages.create_columns(ws_id, page_id, count,
            actor: user,
            tenant: ws_id,
            position: position
          )
      end

    socket =
      case result do
        {:ok, _parent} ->
          {:ok, list} = Pages.list_for_page(page_id, actor: user, tenant: ws_id)
          assign(socket, :blocks, build_block_tree(list))

        {:error, _reason} ->
          socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "reorder_block",
        %{"block_id" => block_id, "prev_id" => prev_id, "next_id" => next_id},
        socket
      ) do
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
  def handle_event(
        "ask_selection",
        %{"text" => text, "block_id" => _block_id, "page_id" => page_id},
        socket
      ) do
    ws_id = socket.assigns.workspace.id

    Phoenix.PubSub.broadcast(
      Concept.PubSub,
      "palette:#{ws_id}",
      {:palette_ask_with_seed, text, page_id}
    )

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

    self_id = socket.assigns.current_user.id

    locked_blocks =
      presence_list
      |> Enum.reject(fn {user_id, _} -> user_id == self_id end)
      |> Enum.flat_map(fn {user_id, %{metas: metas}} ->
        metas
        |> Enum.filter(&Map.get(&1, :locked_block_id))
        |> Enum.map(fn meta ->
          {meta.locked_block_id,
           %{user_id: user_id, color: ConceptWeb.Colors.for_user_id(user_id)}}
        end)
      end)
      |> Map.new()

    {:noreply,
     socket
     |> assign(:presence_users, users)
     |> assign(:locked_blocks, locked_blocks)}
  end

  @impl true
  def handle_info(_, socket), do: {:noreply, socket}

  @doc "Push a scroll_to_block event to the client."
  def push_scroll_to_block(socket, block_id) do
    push_event(socket, "scroll_to_block", %{block_id: block_id})
  end

  @impl true
  def terminate(_reason, socket) do
    for {id, true} <- socket.assigns.held_locks do
      release_if_held(socket, id)
    end

    :ok
  end

  # Build a depth-1 block tree from a flat `list_for_page` result.
  # Top-level blocks (parent_block_id == nil) become the outer list;
  # each parent has its `children` association populated with its direct
  # children sorted by position. Composite renderers (Table/Columns) read
  # `block.children` to lay out cells without an extra round-trip.
  defp build_block_tree(flat_blocks) do
    by_parent = Enum.group_by(flat_blocks, & &1.parent_block_id)

    top_level =
      by_parent
      |> Map.get(nil, [])
      |> Enum.sort_by(& &1.position)

    Enum.map(top_level, fn block ->
      children = by_parent |> Map.get(block.id, []) |> Enum.sort_by(& &1.position)
      %{block | children: children}
    end)
  end

  defp ensure_int(v, _default) when is_integer(v), do: v

  defp ensure_int(v, default) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      _ -> default
    end
  end

  defp ensure_int(_, default), do: default

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
