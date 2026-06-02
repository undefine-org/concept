defmodule ConceptWeb.ChatComponent do
  use ConceptWeb, :live_component
  import ConceptWeb.Components.WhyThisAnswer
  @chat_ui_tools AshAi.ChatUI.Tools

  @impl true
  def mount(socket) do
    # Component-instance defaults set ONCE, before any update/2 (incl. the
    # broadcast clause). Guarantees host addressing + composer assigns exist at
    # render even on the first streamed message or a broadcast-first update.
    {:ok,
     socket
     |> assign(:host_type, :workspace)
     |> assign(:host_id, nil)
     |> assign(:participants, [])
     |> assign(:pending_mentions, [])
     |> assign(:addresses_host, true)
     |> assign(:mention_query, nil)
     |> assign(:mention_suggestions, [])
     |> assign(:draft_text, "")
     |> assign(:message_form_host_key, nil)}
  end

  @impl true
  def update(%{broadcast: broadcast}, socket) do
    {:ok, handle_broadcast(socket, broadcast)}
  end

  def update(assigns, socket) do
    socket = assign(socket, assigns)

    # Host addressing (PLAN-010 §6.1): a conversation is ALWAYS about a host.
    # Default :workspace host preserves today's workspace-chat behaviour; a page
    # view passes host_type: :page, host_id: <page_id> so find-or-create routes
    # to (or creates) that page's ROOT conversation.
    socket =
      socket
      |> assign_new(:host_type, fn -> :workspace end)
      |> assign_new(:host_id, fn -> nil end)

    # Handle initial_prompt if provided
    socket =
      if assigns[:initial_prompt] && !socket.assigns[:prompt_seeded] do
        socket
        |> assign(:prompt_seeded, true)
        |> assign(:initial_text, assigns.initial_prompt)
      else
        socket
      end

    socket =
      if !socket.assigns[:initialized] do
        # B1 (FUP-UX): resume the host's existing conversation on open instead
        # of dropping the user into a blank seed state. The panel reopened onto
        # the SAME {host_type, host_id} should show the live thread, not lose
        # it. We only auto-resume when the caller hasn't pinned an explicit
        # conversation_id (e.g. navigating to a specific thread).
        resumed_id =
          socket.assigns[:conversation_id] ||
            resume_host_conversation_id(socket)

        socket
        |> assign(:conversation_id, resumed_id)
        |> assign(:initialized, true)
        |> assign_new(:hide_sidebar, fn -> false end)
        |> assign_new(:conversation, fn -> nil end)
        |> assign_new(:conversation_id, fn -> nil end)
        |> assign_new(:agent_responding, fn -> false end)
        |> assign_new(:tool_data_warning_shown?, fn -> false end)
        |> assign_new(:has_messages, fn -> false end)
        |> assign_new(:send_error, fn -> nil end)
        |> assign_new(:participants, fn -> [] end)
        |> assign_new(:pending_mentions, fn -> [] end)
        |> assign_new(:addresses_host, fn -> true end)
        |> assign_new(:mention_query, fn -> nil end)
        |> assign_new(:mention_suggestions, fn -> [] end)
        |> assign_new(:draft_text, fn -> "" end)
        |> assign_new(:collapsed_hosts, fn -> MapSet.new() end)
        |> assign_new(:host_picker_open, fn -> false end)
        |> assign_new(:host_picker_query, fn -> "" end)
        |> assign_new(:host_picker_pages, fn -> [] end)
        |> assign_new(:add_people_open, fn -> false end)
        |> assign_new(:member_picks, fn -> MapSet.new() end)
        |> assign_new(:addable_members, fn -> [] end)
        |> assign_new(:thread_map, fn -> %{} end)
        |> assign_new(:open_thread, fn -> nil end)
        |> assign_new(:unread_boundary_id, fn -> nil end)
        |> assign_new(:latest_message_id, fn -> nil end)
        |> assign_new(:chat_presence, fn -> [] end)
        |> assign_new(:reactions_map, fn -> %{} end)
        |> assign_new(:my_membership_id, fn -> nil end)
        |> assign_new(:emoji_pop_for, fn -> nil end)
        |> assign_rail()
        |> stream(:messages, [])
        |> assign_message_form()
      else
        socket
      end

    socket =
      cond do
        socket.assigns[:conversation_id] &&
            socket.assigns[:conversation_id] != get_current_conversation_id(socket) ->
          load_conversation(socket, socket.assigns.conversation_id)

        !socket.assigns[:conversation_id] && socket.assigns.conversation ->
          clear_conversation(socket)

        true ->
          socket
      end

    # The message form bakes host_type/host_id into its create args at build
    # time. When the host changes (e.g. opening chat ON a page flips :workspace →
    # :page) with no active conversation, rebuild so a new message addresses the
    # CURRENT host — otherwise the first message would create a workspace
    # conversation despite the page header (caught in browser).
    host_key = {socket.assigns[:host_type], socket.assigns[:host_id]}

    socket =
      if is_nil(socket.assigns[:conversation]) and
           socket.assigns[:message_form_host_key] != host_key do
        # Preserve any half-typed draft across the host-driven form rebuild.
        draft = socket.assigns[:draft_text]

        socket
        |> assign(:message_form_host_key, host_key)
        |> then(fn s ->
          if draft not in [nil, ""], do: assign(s, :initial_text, draft), else: s
        end)
        |> assign_message_form()
      else
        socket
      end

    {:ok, socket}
  end

  @doc """
  Subscribes the calling process to PubSub topics for the given user.

  Call this from your parent LiveView's `mount/3`:

      if connected?(socket) do
        MyAppWeb.ChatComponent.subscribe(socket.assigns.current_user, socket)
      end
  """
  def subscribe(current_user, _socket) do
    if current_user do
      ConceptWeb.Endpoint.subscribe("chat:conversations:#{current_user.id}")
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="flex bg-white min-h-full max-h-full">
      <div
        :if={!@hide_sidebar}
        class="w-60 shrink-0 border-r border-notion-divider bg-notion-sidebar flex flex-col overflow-y-auto"
      >
        <div class="py-4 px-3">
          <%!-- The global host-picker: starting a conversation = choosing a
                host (workspace/page/person). Resolves to create_message. --%>
          <button
            phx-click="open_host_picker"
            phx-target={@myself}
            id={"#{@id}-new-conversation"}
            class="ora-btn ora-btn--ghost w-full justify-start gap-2 mb-3 text-notion-text-light"
          >
            <.icon name="hero-plus-micro" class="size-4" /> New conversation
          </button>

          <%!-- Adaptive rail (T1): host › conversation, grouped by
                Concept.Chat.RailModel. ≥2 convos → a collapsible host category;
                exactly 1 → the conversation inline with a muted in-<host> ref. --%>
          <nav id={"#{@id}-rail"} class="flex flex-col gap-4" aria-label="Conversations">
            <div :for={section <- rail_sections(@rail_groups)} class="flex flex-col">
              <div class="px-2 mb-1 text-[11px] font-semibold uppercase tracking-wide text-notion-text-light">
                {Concept.Chat.RailModel.section_label(section.section)}
              </div>
              <div :for={group <- section.groups} class="flex flex-col">
                <%= if group.mode == :category do %>
                  <% collapsed = MapSet.member?(@collapsed_hosts, host_key(group)) %>
                  <div class="group/host flex items-center gap-1 px-2 py-1 rounded hover:bg-notion-sidebar-hover">
                    <button
                      type="button"
                      phx-click="toggle_host_category"
                      phx-value-key={host_key(group)}
                      phx-target={@myself}
                      class="flex items-center gap-1 flex-1 min-w-0 text-left text-sm font-medium text-notion-text"
                    >
                      <.icon
                        name={
                          if(collapsed,
                            do: "hero-chevron-right-micro",
                            else: "hero-chevron-down-micro"
                          )
                        }
                        class="size-3.5 text-notion-text-light shrink-0"
                      />
                      <.icon
                        name={Concept.Chat.RailModel.glyph(group.host_type)}
                        class="size-4 shrink-0 text-notion-text-light"
                      />
                      <span class="truncate">{host_group_label(group, assigns)}</span>
                    </button>
                    <button
                      type="button"
                      phx-click="open_host_picker"
                      phx-value-host-type={group.host_type}
                      phx-value-host-id={group.host_id}
                      phx-target={@myself}
                      class="opacity-0 group-hover/host:opacity-100 transition shrink-0 text-notion-text-light hover:text-notion-text"
                      title={"New topic about #{host_group_label(group, assigns)}"}
                      aria-label={"New conversation about #{host_group_label(group, assigns)}"}
                    >
                      <.icon name="hero-plus-micro" class="size-3.5" />
                    </button>
                  </div>
                  <ul :if={!collapsed} class="ml-4 border-l border-notion-divider pl-2 flex flex-col">
                    <li :for={conversation <- group.conversations}>
                      <button
                        phx-click="select_conversation"
                        phx-target={@myself}
                        phx-value-id={conversation.id}
                        class={[
                          "block w-full text-left py-1 px-2 rounded text-sm truncate transition",
                          conv_selected?(@conversation, conversation) &&
                            "bg-notion-sidebar-hover font-medium text-notion-text",
                          !conv_selected?(@conversation, conversation) &&
                            "text-notion-text-light hover:text-notion-text"
                        ]}
                      >
                        {rail_conversation_title(conversation)}
                      </button>
                    </li>
                  </ul>
                <% else %>
                  <% conversation = hd(group.conversations) %>
                  <button
                    phx-click="select_conversation"
                    phx-target={@myself}
                    phx-value-id={conversation.id}
                    class={[
                      "group/inline flex flex-col px-2 py-1 rounded text-left transition",
                      conv_selected?(@conversation, conversation) && "bg-notion-sidebar-hover",
                      !conv_selected?(@conversation, conversation) && "hover:bg-notion-sidebar-hover"
                    ]}
                  >
                    <span class="flex items-center gap-1.5 min-w-0">
                      <.icon
                        name={Concept.Chat.RailModel.glyph(group.host_type)}
                        class="size-4 shrink-0 text-notion-text-light"
                      />
                      <span class={[
                        "truncate text-sm",
                        conv_selected?(@conversation, conversation) && "font-medium text-notion-text",
                        !conv_selected?(@conversation, conversation) && "text-notion-text"
                      ]}>
                        {rail_conversation_title(conversation)}
                      </span>
                    </span>
                    <%!-- the muted in-<host> ref, revealed on hover (§1.1) --%>
                    <span
                      :if={inline_host_ref(group, assigns)}
                      class="ml-5 text-xs text-notion-text-light opacity-0 group-hover/inline:opacity-100 transition truncate"
                    >
                      in {inline_host_ref(group, assigns)}
                    </span>
                  </button>
                <% end %>
              </div>
            </div>
            <p :if={@rail_groups == []} class="px-2 text-sm text-notion-text-light">
              No conversations yet.
            </p>
          </nav>
        </div>
      </div>

      <div class="relative flex-1 flex flex-col min-w-0">
        <.flash kind={:info} flash={@flash} />
        <.flash kind={:error} flash={@flash} />
        <.flash kind={:warning} flash={@flash} />

        <div class="flex items-center gap-3 px-4 py-3 border-b border-notion-divider">
          <span class="ora-avatar" style="background: var(--color-notion-blue);">
            <.icon name={host_icon(@host_type)} class="size-4 text-white" />
          </span>
          <div class="flex-1 min-w-0">
            <p :if={@conversation} class="text-sm font-medium truncate">
              {build_conversation_title_string(@conversation.title)}
            </p>
            <p class="text-xs text-notion-text-light" id={"#{@id}-host-label"}>
              {host_label(assigns)}
            </p>
          </div>
          <%!-- Live presence (T3): online collaborator dots on this conversation,
                reusing Phoenix.Presence. Excludes self. --%>
          <div
            :if={@conversation && chat_collaborators(assigns) != []}
            id={"#{@id}-chat-presence"}
            class="flex items-center -space-x-1 shrink-0"
          >
            <span
              :for={c <- chat_collaborators(assigns)}
              class="inline-flex items-center justify-center size-6 rounded-full text-[10px] font-bold text-white ring-2 ring-white"
              style={"background-color: #{c.color}"}
              title={c.display_name}
            >
              {c.display_name |> String.first() |> Kernel.||("?") |> String.upcase()}
            </span>
          </div>
          <%!-- Conversation-level action lives in the header (B7), not injected
                between messages. Only meaningful when the host IS a page. --%>
          <button
            :if={@host_type == :page and @host_id != nil and @conversation != nil}
            type="button"
            id={"#{@id}-crystallize-btn"}
            phx-click="crystallize"
            phx-target={@myself}
            class="shrink-0 inline-flex items-center gap-1 px-2 py-1 rounded-full text-xs bg-emerald-100 text-emerald-700 hover:bg-emerald-200"
            title="Clone this conversation's blocks onto the page (copy, with provenance)"
          >
            <.icon name="hero-sparkles-micro" class="size-3" /> Crystallize
          </button>
        </div>

        <div class="ora-chat-body flex-1">
          <div
            :if={!@has_messages}
            class="p-4 space-y-2"
          >
            <p class="text-xs uppercase tracking-wide text-notion-text-light">Try asking</p>
            <button
              type="button"
              class="block w-full text-left p-2 rounded hover:bg-notion-sidebar-hover text-sm text-notion-text"
              phx-click="seed_prompt"
              phx-value-prompt="Summarize this workspace"
              phx-target={@myself}
            >
              💡 Summarize this workspace
            </button>
            <button
              type="button"
              class="block w-full text-left p-2 rounded hover:bg-notion-sidebar-hover text-sm text-notion-text"
              phx-click="seed_prompt"
              phx-value-prompt="What pages mention"
              phx-target={@myself}
            >
              🔍 What pages mention …?
            </button>
            <button
              type="button"
              class="block w-full text-left p-2 rounded hover:bg-notion-sidebar-hover text-sm text-notion-text"
              phx-click="seed_prompt"
              phx-value-prompt="Outline a roadmap based on my notes"
              phx-target={@myself}
            >
              🗺 Outline a roadmap based on my notes
            </button>
          </div>
          <div
            id={"#{@id}-message-container"}
            phx-update="stream"
            phx-hook="ScrollToBottom MarkRead"
            phx-target={@myself}
            data-latest-id={@unread_boundary_id && latest_message_id(assigns)}
            class="ora-chat-messages"
          >
            <%!-- Dispatch on Concept.Chat.MessageKind.render_mode/1 — the single
                    source of truth. Host replies SEEP in (fused continuation,
                    no avatar); humans/agents take a row. Raw tool plumbing never
                    renders in the stream — it lives behind "Why this answer?". --%>
            <%= for {id, message} <- @streams.messages do %>
              <% mode = Concept.Chat.MessageKind.render_mode(message) %>
              <% is_boundary = @unread_boundary_id && message_id_of(message) == @unread_boundary_id %>
              <div
                id={id}
                data-render-mode={mode}
                class={[
                  "ora-chat-message group/msg relative",
                  is_boundary && "ora-chat-unread-boundary",
                  mode == :human_row && "ora-chat-message--user",
                  mode == :agent_row && "ora-chat-message--agent",
                  mode in [:host_seep, :host_note] && "ora-chat-message--seep"
                ]}
              >
                <%!-- Unread "New" divider (T2): rendered INSIDE the boundary
                      message's stream item so re-streaming it (on mark_read)
                      cleanly removes the divider. --%>
                <div
                  :if={is_boundary}
                  id={"#{@id}-unread-divider"}
                  class="absolute -top-2 left-0 right-0 flex items-center gap-2 text-[11px] font-semibold uppercase tracking-wide text-rose-500"
                >
                  <span class="h-px flex-1 bg-rose-200"></span>
                  New <span class="h-px flex-1 bg-rose-200"></span>
                </div>
                <%!-- Hover toolbar (T2): every message is a unit of work. Reply
                      in thread + copy link are real now; React (T4) and
                      Crystallize-this-message (T6, once bodies are blocks) slot
                      in here. No dead buttons — absent until real. --%>
                <div
                  id={"#{@id}-msg-toolbar-#{message_id_of(message)}"}
                  class="absolute -top-3 right-2 hidden group-hover/msg:flex items-center gap-0.5 bg-white border border-notion-divider rounded-lg shadow-sm px-0.5 py-0.5 z-10"
                >
                  <button
                    type="button"
                    id={"#{@id}-react-#{message_id_of(message)}"}
                    phx-click="open_emoji_pop"
                    phx-value-message={message_id_of(message)}
                    phx-target={@myself}
                    class="p-1 rounded hover:bg-notion-sidebar-hover text-notion-text-light hover:text-notion-text"
                    title="Add reaction"
                    aria-label="Add reaction"
                  >
                    <.icon name="hero-face-smile-micro" class="size-4" />
                  </button>
                  <button
                    type="button"
                    phx-click="open_thread"
                    phx-value-seed={message_id_of(message)}
                    phx-target={@myself}
                    class="p-1 rounded hover:bg-notion-sidebar-hover text-notion-text-light hover:text-notion-text"
                    title="Reply in thread"
                    aria-label="Reply in thread"
                  >
                    <.icon name="hero-chat-bubble-left-right-micro" class="size-4" />
                  </button>
                  <button
                    type="button"
                    id={"#{@id}-msg-copylink-#{message_id_of(message)}"}
                    phx-hook="CopyToClipboard"
                    data-clipboard-text={message_link(assigns, message)}
                    class="p-1 rounded hover:bg-notion-sidebar-hover text-notion-text-light hover:text-notion-text"
                    title="Copy link to message"
                    aria-label="Copy link to message"
                  >
                    <.icon name="hero-link-micro" class="size-4" />
                  </button>
                </div>
                <span :if={mode == :human_row} class="ora-chat-avatar">
                  <.icon name="hero-user-micro" class="size-4 text-notion-text-light" />
                </span>
                <span
                  :if={mode == :agent_row}
                  class="ora-chat-avatar"
                  title={sender_label(message, assigns)}
                >
                  <.icon name="hero-cpu-chip-micro" class="size-4 text-violet-500" />
                </span>
                <div class="flex flex-col gap-1 min-w-0 flex-1">
                  <%!-- Host seep: a quiet "from this <host>" voice label, not a
                        person's name. The blue rail comes from --seep. --%>
                  <div
                    :if={mode in [:host_seep, :host_note]}
                    class="ora-chat-seep-label flex items-center gap-1 text-xs text-notion-blue"
                  >
                    <.icon name="hero-sparkles-micro" class="size-3" />
                    <span>from {String.downcase(host_voice_name(@host_type || :workspace))}</span>
                  </div>
                  <div :if={String.trim(message.text || "") != ""} class="ora-chat-bubble">
                    {to_markdown(message.text || "")}
                  </div>
                  <div :if={Concept.Chat.MessageKind.host?(message)} class="mt-1">
                    <.why_this_answer message={message} />
                  </div>
                  <%!-- Thread chip (T2): present iff this message seeded a child
                        conversation. Makes seed_message_id visible. --%>
                  <button
                    :if={thread_for(assigns, message)}
                    type="button"
                    id={"#{@id}-thread-chip-#{message_id_of(message)}"}
                    phx-click="open_thread"
                    phx-value-seed={message_id_of(message)}
                    phx-target={@myself}
                    class="mt-1 inline-flex items-center gap-1 text-xs text-notion-blue hover:underline"
                  >
                    <.icon name="hero-chat-bubble-left-right-micro" class="size-3.5" />
                    {thread_reply_count(thread_for(assigns, message))}
                  </button>

                  <%!-- Reaction chips (T4): own-reaction outlined; click toggles. --%>
                  <div
                    :if={reactions_for(assigns, message) != []}
                    id={"#{@id}-reactions-#{message_id_of(message)}"}
                    class="mt-1 flex flex-wrap gap-1"
                  >
                    <button
                      :for={chip <- reactions_for(assigns, message)}
                      type="button"
                      phx-click="toggle_reaction"
                      phx-value-message={message_id_of(message)}
                      phx-value-emoji={chip.emoji}
                      phx-target={@myself}
                      class={[
                        "inline-flex items-center gap-1 px-1.5 py-0.5 rounded-full text-xs border",
                        chip.mine? && "border-notion-blue bg-notion-blue/10 text-notion-blue",
                        !chip.mine? && "border-notion-divider bg-notion-sidebar text-notion-text"
                      ]}
                    >
                      <span>{chip.emoji}</span>
                      <span>{chip.count}</span>
                    </button>
                  </div>

                  <%!-- Compact emoji picker opened from the toolbar react btn. --%>
                  <div
                    :if={@emoji_pop_for == message_id_of(message)}
                    id={"#{@id}-emoji-pop-#{message_id_of(message)}"}
                    class="mt-1 inline-flex items-center gap-1 p-1 rounded-lg bg-white border border-notion-divider shadow-sm"
                  >
                    <button
                      :for={emoji <- reaction_palette()}
                      type="button"
                      phx-click="react"
                      phx-value-message={message_id_of(message)}
                      phx-value-emoji={emoji}
                      phx-target={@myself}
                      class="p-0.5 rounded hover:bg-notion-sidebar-hover text-base leading-none"
                      aria-label={"React " <> emoji}
                    >
                      {emoji}
                    </button>
                  </div>
                </div>
              </div>
            <% end %>
          </div>

          <%!-- Thread panel (T2): a docked overlay showing a child conversation
                — the seed message pinned at top, the thread's replies below, its
                own composer. A thread is just a Conversation with a parent. --%>
          <div
            :if={@open_thread}
            id={"#{@id}-thread-panel"}
            class="absolute inset-y-0 right-0 w-80 max-w-[80%] bg-white border-l border-notion-divider shadow-xl flex flex-col z-10"
          >
            <div class="flex items-center gap-2 px-3 py-2 border-b border-notion-divider">
              <.icon name="hero-chat-bubble-left-right-micro" class="size-4 text-notion-blue" />
              <div class="flex-1 min-w-0">
                <p class="text-sm font-medium">Thread</p>
                <p class="text-xs text-notion-text-light truncate">
                  {thread_reply_count(@open_thread.thread)} · in this conversation
                </p>
              </div>
              <button
                type="button"
                phx-click="close_thread"
                phx-target={@myself}
                class="ora-btn ora-btn--ghost ora-btn--icon"
                aria-label="Close thread"
              >
                <.icon name="hero-x-mark-micro" class="size-4" />
              </button>
            </div>
            <div class="flex-1 overflow-y-auto p-3 flex flex-col gap-3">
              <%!-- Seed message, pinned. --%>
              <div class="rounded-lg bg-notion-sidebar/60 border border-notion-divider p-2">
                <p class="text-[10px] uppercase tracking-wide text-notion-text-light mb-1">
                  Seed message
                </p>
                <div class="text-sm">{to_markdown(@open_thread.seed_text || "")}</div>
              </div>
              <%!-- The thread's replies (the child conversation), oldest first. --%>
              <div
                :for={reply <- @open_thread.replies}
                class={[
                  "ora-chat-message",
                  Concept.Chat.MessageKind.render_mode(reply) == :human_row &&
                    "ora-chat-message--user",
                  Concept.Chat.MessageKind.host?(reply) && "ora-chat-message--seep"
                ]}
              >
                <div class="flex flex-col gap-1 min-w-0 flex-1">
                  <div
                    :if={Concept.Chat.MessageKind.host?(reply)}
                    class="ora-chat-seep-label flex items-center gap-1 text-xs text-notion-blue"
                  >
                    <.icon name="hero-sparkles-micro" class="size-3" />
                    <span>from {String.downcase(host_voice_name(@host_type || :workspace))}</span>
                  </div>
                  <div :if={String.trim(reply.text || "") != ""} class="ora-chat-bubble">
                    {to_markdown(reply.text || "")}
                  </div>
                </div>
              </div>
            </div>
            <form
              id={"#{@id}-thread-reply-form"}
              phx-submit="thread_reply"
              phx-target={@myself}
              class="flex items-center gap-2 p-3 border-t border-notion-divider"
            >
              <input
                type="text"
                name="form[text]"
                placeholder="Reply in thread…"
                autocomplete="off"
                class="ora-input flex-1"
              />
              <button type="submit" class="ora-btn ora-btn--primary ora-btn--sm">
                <.icon name="hero-paper-airplane-micro" class="size-4" />
              </button>
            </form>
          </div>
        </div>

        <%!-- Seen-by (T3): read receipts — participants whose cursor reached the
              latest message, as stacked avatars. --%>
        <div
          :if={@conversation && seen_by(assigns) != []}
          id={"#{@id}-seen-by"}
          class="px-4 py-1 flex items-center gap-1 text-xs text-notion-text-light"
        >
          <span class="mr-1">Seen by</span>
          <span class="flex items-center -space-x-1">
            <span
              :for={p <- seen_by(assigns)}
              class="inline-flex items-center justify-center size-4 rounded-full bg-notion-text-light text-white text-[9px] font-semibold ring-1 ring-white"
              title={seen_by_label(p)}
            >
              {seen_by_initial(p)}
            </span>
          </span>
        </div>

        <%!-- Human typing cue (T3): "X is typing…" beside the host's "is
              thinking" — people type, the host thinks. --%>
        <div
          :if={chat_typing_names(assigns) != []}
          id={"#{@id}-typing-cue"}
          class="px-4 py-1 text-xs text-notion-text-light flex items-center gap-1"
        >
          <span class="ora-typing" aria-hidden="true"><i></i><i></i><i></i></span>
          {chat_typing_label(chat_typing_names(assigns))}
        </div>

        <%!-- Responding cue rendered AS a forming seep (blue rail + skeleton),
              so a multi-second grounded answer reads as alive, not frozen. --%>
        <div :if={@agent_responding} class="ora-chat-message ora-chat-message--seep">
          <div class="flex flex-col gap-1 min-w-0 flex-1">
            <div class="ora-chat-seep-label flex items-center gap-1 text-xs text-notion-blue">
              <.icon name="hero-sparkles-micro" class="size-3" />
              <span>{String.downcase(host_voice_name(@host_type || :workspace))} is thinking</span>
              <span class="ora-typing" aria-hidden="true"><i></i><i></i><i></i></span>
            </div>
            <div class="space-y-1 mt-1" role="status" aria-label="Generating answer">
              <div class="ora-skeleton ora-skeleton-line"></div>
              <div class="ora-skeleton ora-skeleton-line"></div>
              <div class="ora-skeleton ora-skeleton-line"></div>
            </div>
          </div>
        </div>

        <div
          :if={@conversation}
          id={"#{@id}-participant-rail"}
          class="flex flex-wrap items-center gap-2 px-4 py-2 border-t border-notion-divider bg-notion-sidebar/40"
        >
          <span class="text-xs uppercase tracking-wide text-notion-text-light mr-1">
            In this conversation
          </span>
          <button
            type="button"
            id={"#{@id}-add-people-trigger"}
            phx-click="open_add_people"
            phx-target={@myself}
            class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs border border-dashed border-notion-divider text-notion-text-light hover:text-notion-text hover:border-notion-text-light"
            title="Add people to this conversation"
          >
            <.icon name="hero-plus-micro" class="size-3" /> Add people
          </button>
          <%!-- The host's grounded voice: a voice, not a person (PLAN-010 §39). --%>
          <span
            class="ml-auto inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs bg-notion-blue/10 text-notion-blue"
            title="The host's grounded AI voice"
          >
            <.icon name="hero-sparkles-micro" class="size-3" />
            {host_voice_name(@host_type)}
          </span>
          <span
            :for={participant <- @participants}
            class={[
              "inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs",
              participant.kind == :agent && "bg-violet-100 text-violet-700",
              participant.kind != :agent && "bg-notion-sidebar text-notion-text"
            ]}
            title={participant_name(participant)}
          >
            <.icon
              :if={participant.kind == :agent}
              name="hero-cpu-chip-micro"
              class="size-3 text-violet-500"
            />
            <span
              :if={participant.kind != :agent}
              class="inline-flex items-center justify-center size-4 rounded-full bg-notion-blue text-white text-[10px] font-semibold"
            >
              {participant_initial(participant)}
            </span>
            {participant_name(participant)}
          </span>
        </div>

        <%!-- B8: a failed send surfaces as a humane, retryable card (never a
              silent drop or a raw error). One click re-sends the same text. --%>
        <.error_card
          :if={@send_error}
          id={"#{@id}-send-error"}
          class="mx-4 mb-2"
        >
          Message could not be sent.
          <:actions>
            <button
              type="button"
              id={"#{@id}-retry-send"}
              phx-click="retry_send"
              phx-target={@myself}
              class="ora-btn ora-btn--ghost ora-btn--sm"
            >
              <.icon name="hero-arrow-path-micro" class="size-3.5 mr-1" /> Retry
            </button>
            <button
              type="button"
              phx-click="dismiss_send_error"
              phx-target={@myself}
              class="ora-btn ora-btn--ghost ora-btn--sm text-notion-text-light"
            >
              Dismiss
            </button>
          </:actions>
        </.error_card>

        <div id={"#{@id}-composer"} class="ora-chat-input-row relative">
          <%!-- Pending @-mention chips (participant ids carried into the message). --%>
          <div
            :if={@pending_mentions != []}
            id={"#{@id}-mention-chips"}
            class="flex flex-wrap gap-1 mb-2"
          >
            <span
              :for={mention <- @pending_mentions}
              class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs bg-violet-100 text-violet-700"
            >
              @{mention.label}
              <button
                type="button"
                phx-click="remove_mention"
                phx-value-id={mention.id}
                phx-target={@myself}
                class="hover:text-violet-900"
                aria-label={"Remove mention #{mention.label}"}
              >
                <.icon name="hero-x-mark-micro" class="size-3" />
              </button>
            </span>
          </div>

          <%!-- Mention suggestions: opened by a trailing @token in the draft. --%>
          <ul
            :if={@mention_query != nil and @mention_suggestions != []}
            id={"#{@id}-mention-suggestions"}
            class="absolute bottom-full mb-1 left-0 z-20 w-64 bg-white border border-notion-divider rounded-lg shadow-lg overflow-hidden"
          >
            <li :for={opt <- @mention_suggestions}>
              <button
                type="button"
                phx-click="pick_mention"
                phx-value-id={opt.id}
                phx-value-label={opt.label}
                phx-value-kind={opt.kind}
                phx-target={@myself}
                class="flex items-center gap-2 w-full text-left px-3 py-2 text-sm hover:bg-notion-sidebar-hover"
              >
                <.icon
                  name={if(opt.kind == "host", do: "hero-sparkles-micro", else: "hero-user-micro")}
                  class={[
                    "size-4",
                    opt.kind == "host" && "text-notion-blue",
                    opt.kind == "agent" && "text-violet-500"
                  ]}
                />
                {opt.label}
                <span :if={opt.kind == "host"} class="ml-auto text-xs text-notion-text-light">
                  AI voice
                </span>
              </button>
            </li>
          </ul>

          <.form
            :let={form}
            for={@message_form}
            phx-change="validate_message"
            phx-target={@myself}
            phx-debounce="blur"
            phx-submit="send_message"
            class="flex items-center gap-2 w-full"
          >
            <%!-- The reflex-killer: toggle whether the host's AI voice replies. --%>
            <button
              type="button"
              id={"#{@id}-toggle-host"}
              phx-click="toggle_host"
              phx-target={@myself}
              aria-pressed={to_string(@addresses_host != false)}
              title={
                if(@addresses_host != false,
                  do: "#{host_voice_name(@host_type)} will reply — click to silence",
                  else: "Human-only message — click to ask #{host_voice_name(@host_type)}"
                )
              }
              class={[
                "ora-btn ora-btn--icon",
                if(@addresses_host != false, do: "text-notion-blue", else: "text-notion-text-light")
              ]}
            >
              <.icon name="hero-sparkles-micro" class="size-4" />
            </button>
            <input
              name={form[:text].name}
              value={form[:text].value}
              type="text"
              phx-mounted={JS.focus()}
              phx-debounce="120"
              placeholder="Message — @ a person or the host"
              class="ora-input flex-1"
              autocomplete="off"
            />
            <button
              type="submit"
              class="ora-btn ora-btn--primary"
              aria-busy={to_string(@agent_responding)}
              disabled={@agent_responding}
            >
              <span :if={@agent_responding} class="ora-spinner mr-1.5" aria-hidden="true" />
              <.icon :if={!@agent_responding} name="hero-paper-airplane-micro" class="size-4" />
              <span class="ora-btn__label">Send</span>
            </button>
          </.form>
        </div>
      </div>

      <%!-- Host-picker (T1): starting a conversation = choosing a host. Search
            across the workspace + page hosts; pick one (+ optional topic) to
            create a conversation about it. People/DM hosts arrive in T5. --%>
      <.modal
        :if={@host_picker_open}
        id={"#{@id}-host-picker"}
        on_cancel={JS.push("close_host_picker", target: @myself)}
      >
        <:title>New conversation</:title>
        <div class="px-4 pb-4 flex flex-col gap-3 w-[480px] max-w-full">
          <p class="text-xs text-notion-text-light">Start a conversation about…</p>
          <form phx-change="filter_host_picker" phx-target={@myself} class="relative">
            <input
              type="text"
              name="q"
              value={@host_picker_query}
              placeholder="Search pages…"
              phx-debounce="120"
              autocomplete="off"
              class="ora-input w-full"
            />
          </form>

          <div class="max-h-80 overflow-y-auto flex flex-col gap-3">
            <div>
              <div class="px-1 mb-1 text-[11px] font-semibold uppercase tracking-wide text-notion-text-light">
                Workspace
              </div>
              <button
                type="button"
                phx-click="start_conversation"
                phx-value-host-type="workspace"
                phx-target={@myself}
                class="flex items-center gap-2 w-full text-left px-2 py-2 rounded hover:bg-notion-sidebar-hover text-sm"
              >
                <.icon
                  name={Concept.Chat.RailModel.glyph(:workspace)}
                  class="size-4 text-notion-blue"
                />
                <span class="flex-1">Workspace</span>
                <span class="text-xs text-notion-text-light">the whole workspace</span>
              </button>
            </div>

            <div :if={@host_picker_pages != []}>
              <div class="px-1 mb-1 text-[11px] font-semibold uppercase tracking-wide text-notion-text-light">
                Pages
              </div>
              <button
                :for={page <- @host_picker_pages}
                type="button"
                phx-click="start_conversation"
                phx-value-host-type="page"
                phx-value-host-id={page.id}
                phx-target={@myself}
                class="flex items-center gap-2 w-full text-left px-2 py-2 rounded hover:bg-notion-sidebar-hover text-sm"
              >
                <.icon
                  name={Concept.Chat.RailModel.glyph(:page)}
                  class="size-4 text-notion-text-light"
                />
                <span class="flex-1 truncate">{page.title}</span>
                <span class="text-xs text-notion-text-light">about this page</span>
              </button>
            </div>

            <p
              :if={@host_picker_query != "" and @host_picker_pages == []}
              class="px-1 text-sm text-notion-text-light"
            >
              No pages match “{@host_picker_query}”. The Workspace host is always available.
            </p>
          </div>
        </div>
      </.modal>

      <%!-- Add-people (T1): the UI for Participant.join. Member checklist → join
            per selection. The host's grounded voice is a FIXED chip (a voice,
            not a member, §39) — it has no checkbox and can't be removed. --%>
      <.modal
        :if={@add_people_open}
        id={"#{@id}-add-people"}
        on_cancel={JS.push("close_add_people", target: @myself)}
      >
        <:title>Add people</:title>
        <div class="px-4 pb-4 flex flex-col gap-3 w-[460px] max-w-full">
          <%!-- Fixed host-voice presence. --%>
          <div class="flex items-center gap-2 px-2 py-1.5 rounded-lg bg-notion-blue/10">
            <.icon name="hero-sparkles-micro" class="size-4 text-notion-blue" />
            <span class="text-sm text-notion-blue">{host_voice_name(@host_type)}</span>
            <span class="ml-auto text-xs text-notion-blue/70">AI voice · always present</span>
          </div>

          <div class="px-1 text-[11px] font-semibold uppercase tracking-wide text-notion-text-light">
            Workspace members
          </div>
          <div class="max-h-72 overflow-y-auto flex flex-col">
            <button
              :for={member <- @addable_members}
              type="button"
              phx-click="toggle_member_pick"
              phx-value-id={member.id}
              phx-target={@myself}
              class="flex items-center gap-2 w-full text-left px-2 py-2 rounded hover:bg-notion-sidebar-hover text-sm"
            >
              <span class={[
                "inline-flex items-center justify-center size-4 rounded border",
                MapSet.member?(@member_picks, member.id) &&
                  "bg-notion-blue border-notion-blue text-white",
                !MapSet.member?(@member_picks, member.id) && "border-notion-divider"
              ]}>
                <.icon
                  :if={MapSet.member?(@member_picks, member.id)}
                  name="hero-check-micro"
                  class="size-3"
                />
              </span>
              <span class="inline-flex items-center justify-center size-5 rounded-full bg-notion-blue text-white text-[10px] font-semibold shrink-0">
                {member_initial(member)}
              </span>
              <span class="flex-1 truncate">{member_label(member)}</span>
              <span
                :if={member.role == :agent}
                class="text-[10px] px-1.5 py-0.5 rounded-full bg-violet-100 text-violet-700"
              >
                agent
              </span>
            </button>
            <p :if={@addable_members == []} class="px-1 py-2 text-sm text-notion-text-light">
              Everyone in the workspace is already here.
            </p>
          </div>

          <div class="flex items-center justify-between pt-2 border-t border-notion-divider">
            <span class="text-xs text-notion-text-light">
              {MapSet.size(@member_picks)} selected
            </span>
            <div class="flex items-center gap-2">
              <button
                type="button"
                phx-click="close_add_people"
                phx-target={@myself}
                class="ora-btn ora-btn--ghost ora-btn--sm"
              >
                Cancel
              </button>
              <button
                type="button"
                id={"#{@id}-add-people-confirm"}
                phx-click="confirm_add_people"
                phx-target={@myself}
                disabled={MapSet.size(@member_picks) == 0}
                class="ora-btn ora-btn--primary ora-btn--sm"
              >
                Add to conversation
              </button>
            </div>
          </div>
        </div>
      </.modal>
    </div>
    """
  end

  @impl true
  def handle_event("validate_message", %{"form" => params}, socket) do
    text = params["text"] || ""

    {mention_query, suggestions} = mention_state(text, socket)

    # T3: reflect typing in presence so others see "X is typing". Only meaningful
    # in an open conversation (a tracked presence topic exists).
    if conv = socket.assigns[:conversation] do
      track_chat_presence(socket, conv.id, String.trim(text) != "")
    end

    {:noreply,
     socket
     |> assign(:draft_text, text)
     |> assign(:mention_query, mention_query)
     |> assign(:mention_suggestions, suggestions)
     |> assign(:message_form, AshPhoenix.Form.validate(socket.assigns.message_form, params))}
  end

  @impl true
  def handle_event("pick_mention", %{"kind" => "host"}, socket) do
    # Addressing the host's voice doesn't add a participant id — it flips the
    # "a grounded reply is owed" switch and strips the trailing @token.
    {:noreply,
     socket
     |> assign(:addresses_host, true)
     |> close_mentions_with_stripped_draft()}
  end

  def handle_event("pick_mention", %{"id" => id, "label" => label, "kind" => kind}, socket) do
    pending = socket.assigns[:pending_mentions] || []

    pending =
      if Enum.any?(pending, &(&1.id == id)),
        do: pending,
        else: pending ++ [%{id: id, label: label, kind: kind}]

    {:noreply,
     socket
     |> assign(:pending_mentions, pending)
     |> close_mentions_with_stripped_draft()}
  end

  def handle_event("remove_mention", %{"id" => id}, socket) do
    pending = Enum.reject(socket.assigns[:pending_mentions] || [], &(&1.id == id))
    {:noreply, assign(socket, :pending_mentions, pending)}
  end

  def handle_event("toggle_host", _params, socket) do
    {:noreply, assign(socket, :addresses_host, !(socket.assigns[:addresses_host] != false))}
  end

  @impl true
  def handle_event("send_message", %{"form" => params}, socket) do
    submit_message(socket, params)
  end

  @impl true
  def handle_event("crystallize", _params, socket) do
    # Talk → document: clone the conversation's message blocks onto the host page
    # (copy + provenance, idempotent — BUG-068). Page-hosted only; target = host.
    cond do
      is_nil(socket.assigns.current_user) ->
        {:noreply, put_flash(socket, :error, "You must sign in to crystallize")}

      socket.assigns[:host_type] != :page or is_nil(socket.assigns[:host_id]) ->
        {:noreply, socket}

      true ->
        case Concept.Knowledge.Chat.crystallize_conversation(
               socket.assigns.conversation.id,
               socket.assigns.host_id,
               socket.assigns[:workspace_id],
               actor: socket.assigns.current_user,
               tenant: socket.assigns[:workspace_id]
             ) do
          {:ok, block_ids} ->
            send(self(), {:conversation_crystallized, socket.assigns.host_id})

            {:noreply,
             put_flash(
               socket,
               :info,
               "Crystallized #{length(block_ids)} block(s) onto the page."
             )}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Could not crystallize this conversation.")}
        end
    end
  end

  @impl true
  def handle_event("select_conversation", %{"id" => id}, socket) do
    send(self(), {:chat_component_navigate, id})
    {:noreply, socket}
  end

  @impl true
  def handle_event("new_chat", _, socket) do
    send(self(), {:chat_component_navigate, nil})
    {:noreply, socket}
  end

  @impl true
  def handle_event("open_host_picker", params, socket) do
    # Starting a conversation = choosing a host. A host may be pre-bound when
    # launched from a category's "+" (host_type/host_id present) — then we skip
    # straight to creating about that host. Otherwise open the picker.
    case prebound_host(params) do
      %{host_type: ht, host_id: id} ->
        start_conversation(socket, ht, id, nil)

      nil ->
        {:noreply,
         socket
         |> assign(:host_picker_open, true)
         |> assign(:host_picker_query, "")
         |> assign(:host_picker_pages, host_picker_pages(socket, ""))}
    end
  end

  def handle_event("close_host_picker", _params, socket) do
    {:noreply, assign(socket, :host_picker_open, false)}
  end

  def handle_event("filter_host_picker", %{"q" => q}, socket) do
    {:noreply,
     socket
     |> assign(:host_picker_query, q)
     |> assign(:host_picker_pages, host_picker_pages(socket, q))}
  end

  def handle_event("start_conversation", params, socket) do
    # The picker's search box filters the host list; it is NOT the topic. Leave
    # the title nil so the generate_name trigger auto-titles once messages
    # accrue (an explicit topic field can be added later if wanted).
    host_type = String.to_existing_atom(params["host-type"] || "workspace")
    host_id = params["host-id"]
    start_conversation(socket, host_type, host_id, nil)
  end

  def handle_event("open_emoji_pop", %{"message" => message_id}, socket) do
    # Toggle the compact emoji picker for a message (one open at a time). The
    # picker lives inside the streamed message item, so re-stream the affected
    # message(s) for the toggle to take visual effect.
    current = socket.assigns[:emoji_pop_for]
    next = if current == message_id, do: nil, else: message_id

    socket = assign(socket, :emoji_pop_for, next)
    socket = restream_message(socket, message_id)
    socket = if current && current != message_id, do: restream_message(socket, current), else: socket

    {:noreply, socket}
  end

  def handle_event("react", %{"message" => message_id, "emoji" => emoji}, socket) do
    do_react(socket, message_id, emoji)
  end

  def handle_event("toggle_reaction", %{"message" => message_id, "emoji" => emoji}, socket) do
    # If I already reacted with this emoji, remove it; else add it.
    chips = Map.get(socket.assigns[:reactions_map] || %{}, message_id, [])
    mine? = Enum.any?(chips, &(&1.emoji == emoji and &1.mine?))

    if mine? do
      unreact_one(socket, message_id, emoji)
    else
      do_react(socket, message_id, emoji)
    end
  end

  def handle_event("mark_read", %{"message_id" => message_id}, socket) do
    # Advance my participant's read cursor to the viewed message (the unread
    # cursor that powers the divider and, later, the inbox). Idempotent-ish:
    # find my participant, mark_read. Clear the divider locally on success.
    conversation = socket.assigns[:conversation]
    user = socket.assigns[:current_user]

    with %_{} <- user,
         %{} = conv <- conversation,
         participants <- load_participants(socket, conv.id),
         %{} = mine <-
           Enum.find(participants, fn p ->
             match?(%{membership: %{user_id: uid}} when uid == user.id, p)
           end),
         {:ok, _} <-
           Concept.Knowledge.Chat.mark_participant_read(mine, %{last_read_message_id: message_id},
             actor: user,
             tenant: socket.assigns[:workspace_id]
           ) do
      # The divider lives inside a streamed message item; clearing the boundary
      # assign alone won't re-render an existing stream item, so re-stream the
      # ex-boundary message to drop its divider from the DOM.
      boundary = socket.assigns[:unread_boundary_id]

      socket =
        socket
        |> assign(:unread_boundary_id, nil)
        |> restream_message(boundary)

      {:noreply, socket}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("open_thread", %{"seed" => seed_id}, socket) do
    # Open the thread for a seed message. A thread may not exist yet (opened from
    # the toolbar's Reply-in-thread on a message that has no replies): show an
    # empty panel anchored on the seed; the first reply spawns the child
    # conversation. If it exists, load + subscribe to its messages.
    thread = Map.get(socket.assigns[:thread_map] || %{}, seed_id)
    seed_text = seed_message_text(socket, seed_id)

    replies =
      if thread, do: Enum.sort_by(thread.messages || [], & &1.inserted_at, DateTime), else: []

    if thread, do: ConceptWeb.Endpoint.subscribe("chat:messages:#{thread.id}")

    {:noreply,
     assign(socket, :open_thread, %{
       seed_id: seed_id,
       seed_text: seed_text,
       thread: thread,
       replies: replies
     })}
  end

  def handle_event("close_thread", _params, socket) do
    # ot.thread is nil for a toolbar-opened panel with no replies yet — only
    # unsubscribe when a child conversation actually exists (was subscribed).
    case socket.assigns[:open_thread] do
      %{thread: %{id: tid}} -> ConceptWeb.Endpoint.unsubscribe("chat:messages:#{tid}")
      _ -> :ok
    end

    {:noreply, assign(socket, :open_thread, nil)}
  end

  def handle_event("thread_reply", %{"form" => %{"text" => text}}, socket) do
    open_thread = socket.assigns[:open_thread]

    cond do
      is_nil(socket.assigns[:current_user]) ->
        {:noreply, put_flash(socket, :error, "You must sign in to reply")}

      is_nil(open_thread) or String.trim(text || "") == "" ->
        {:noreply, socket}

      true ->
        # A thread reply is a message posted into the child conversation. Pass
        # reply_to_message_id (the seed) so the action routes to the same thread
        # rather than spawning a new one.
        case Concept.Knowledge.Chat.create_message(
               %{
                 text: text,
                 addresses_host: false,
                 reply_to_message_id: open_thread.seed_id
               },
               actor: socket.assigns.current_user,
               tenant: socket.assigns[:workspace_id]
             ) do
          {:ok, _message} ->
            {:noreply, refresh_open_thread(socket)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not post the reply.")}
        end
    end
  end

  def handle_event("open_add_people", _params, socket) do
    {:noreply,
     socket
     |> assign(:add_people_open, true)
     |> assign(:member_picks, MapSet.new())
     |> assign(:addable_members, addable_members(socket))}
  end

  def handle_event("close_add_people", _params, socket) do
    {:noreply, assign(socket, :add_people_open, false)}
  end

  def handle_event("toggle_member_pick", %{"id" => id}, socket) do
    picks = socket.assigns[:member_picks] || MapSet.new()

    picks =
      if MapSet.member?(picks, id), do: MapSet.delete(picks, id), else: MapSet.put(picks, id)

    {:noreply, assign(socket, :member_picks, picks)}
  end

  def handle_event("confirm_add_people", _params, socket) do
    conversation = socket.assigns[:conversation]
    picks = socket.assigns[:member_picks] || MapSet.new()

    if conversation && MapSet.size(picks) > 0 do
      failures =
        Enum.count(picks, fn membership_id ->
          match?(
            {:error, _},
            Concept.Knowledge.Chat.join_conversation(
              %{
                workspace_id: socket.assigns[:workspace_id],
                conversation_id: conversation.id,
                membership_id: membership_id
              },
              actor: socket.assigns.current_user,
              tenant: socket.assigns[:workspace_id]
            )
          )
        end)

      socket =
        socket
        |> assign(:add_people_open, false)
        |> assign(:member_picks, MapSet.new())
        |> assign(:participants, load_participants(socket, conversation.id))

      # A silent partial failure is easy to miss — surface it (mirrors
      # start_conversation's error branch).
      socket =
        if failures > 0,
          do: put_flash(socket, :error, "Could not add #{failures} member(s)."),
          else: socket

      {:noreply, socket}
    else
      {:noreply, assign(socket, :add_people_open, false)}
    end
  end

  def handle_event("toggle_host_category", %{"key" => key}, socket) do
    collapsed = socket.assigns[:collapsed_hosts] || MapSet.new()

    collapsed =
      if MapSet.member?(collapsed, key),
        do: MapSet.delete(collapsed, key),
        else: MapSet.put(collapsed, key)

    {:noreply, assign(socket, :collapsed_hosts, collapsed)}
  end

  @impl true
  def handle_event("seed_prompt", %{"prompt" => prompt}, socket) do
    # One-click: a seed prompt sends immediately (B6/C7), same path as Send.
    submit_message(socket, %{"text" => prompt})
  end

  @impl true
  def handle_event("retry_send", _params, socket) do
    # B8: re-dispatch the text that failed, through the identical submit path.
    case socket.assigns[:send_error] do
      %{text: text} when is_binary(text) and text != "" ->
        submit_message(socket, %{"text" => text})

      _ ->
        {:noreply, assign(socket, :send_error, nil)}
    end
  end

  @impl true
  def handle_event("dismiss_send_error", _params, socket) do
    {:noreply, assign(socket, :send_error, nil)}
  end

  # Shared submit path for the composer form AND one-click seed prompts. Builds
  # the same addressing merge + form submit + optimistic stream insert so a seed
  # button behaves exactly like typing the prompt and hitting Send (B6/C7).
  defp submit_message(socket, params) do
    if is_nil(socket.assigns.current_user) do
      {:noreply, put_flash(socket, :error, "You must sign in to send messages")}
    else
      # Re-merge addressing into the submit params: AshPhoenix.Form.submit/2 with
      # `params:` REPLACES the param set built in assign_message_form, so host_type/
      # host_id/mentions/addresses_host must be present here too or the action
      # defaults (→ :workspace) win and a page message would mis-route.
      params = Map.merge(addressing_params(socket), params)

      case AshPhoenix.Form.submit(socket.assigns.message_form, params: params) do
        {:ok, message} ->
          socket = socket |> reset_composer() |> assign(:send_error, nil)

          if socket.assigns.conversation do
            socket
            |> assign(:agent_responding, true)
            |> assign(:has_messages, true)
            |> assign_message_form()
            |> stream_insert(:messages, message, at: -1)
            |> then(&{:noreply, &1})
          else
            send(self(), {:chat_component_navigate, message.conversation_id})
            {:noreply, assign_message_form(socket)}
          end

        {:error, form} ->
          # B8: surface a humane, retryable failure instead of a silent no-op.
          # The attempted text is held so one click re-sends it verbatim.
          {:noreply,
           socket
           |> assign(:message_form, form)
           |> assign(:send_error, %{text: params["text"] || params[:text] || ""})}
      end
    end
  end

  # B1: find the most-recent existing conversation for the current host so the
  # panel resumes it on open. Returns a conversation id or nil (→ blank state
  # with seed prompts, the correct first-run experience). Root conversations
  # only (parent_conversation_id == nil) — threads are opened explicitly.
  defp resume_host_conversation_id(socket) do
    with %_{} = user <- socket.assigns[:current_user],
         ws when not is_nil(ws) <- socket.assigns[:workspace_id] do
      host_type = socket.assigns[:host_type] || :workspace
      host_id = socket.assigns[:host_id]

      # `:for_host` already excludes threads and sorts most-recent-first.
      Concept.Knowledge.Chat.conversations_for_host!(host_type, host_id,
        actor: user,
        tenant: ws
      )
      |> List.first()
      |> case do
        nil -> nil
        conversation -> conversation.id
      end
    else
      _ -> nil
    end
  end

  defp load_conversation(socket, conversation_id) do
    if true && is_nil(socket.assigns.current_user) do
      socket
      |> put_flash(:error, "You must sign in to access conversations")
      |> clear_conversation()
    else
      conversation =
        Concept.Knowledge.Chat.get_conversation!(conversation_id,
          actor: socket.assigns.current_user,
          tenant: socket.assigns[:workspace_id]
        )

      messages =
        Concept.Knowledge.Chat.message_history!(conversation.id,
          stream?: true,
          tenant: socket.assigns[:workspace_id]
        )

      # Switching directly A→B (no clear in between): untrack/unsubscribe the
      # previously-open conversation so we don't leak as a stale online/typing
      # collaborator in A.
      case socket.assigns[:conversation] do
        %{id: prev_id} when prev_id != conversation.id ->
          ConceptWeb.Endpoint.unsubscribe("chat:messages:#{prev_id}")
          untrack_chat_presence(socket, prev_id)

        _ ->
          :ok
      end

      ConceptWeb.Endpoint.subscribe("chat:messages:#{conversation.id}")
      track_chat_presence(socket, conversation.id, false)

      socket
      |> maybe_warn_tool_data(messages)
      |> assign(:conversation, conversation)
      |> assign(:chat_presence, chat_presence_list(socket, conversation.id))
      # Reflect the loaded conversation's actual host (a page/thread convo keeps
      # its host voice + crystallize affordance), falling back to :workspace.
      |> assign(:host_type, conversation.host_type || :workspace)
      |> assign(:host_id, conversation.host_id)
      |> assign(:participants, load_participants(socket, conversation.id))
      |> assign(:reactions_map, load_reactions_map(socket, conversation.id))
      |> assign(:my_membership_id, my_membership_id(socket))
      |> assign(:emoji_pop_for, nil)
      |> then(fn s ->
        # Reuse the participants just loaded (avoid a duplicate read for the
        # cursor); pass them into the unread-boundary computation.
        assign(s, :unread_boundary_id, unread_boundary(s, s.assigns.participants, messages))
      end)
      |> assign(:thread_map, load_thread_map(socket, conversation.id))
      |> assign(:open_thread, nil)
      |> assign(:latest_message_id, messages |> Enum.at(0) |> message_id_of())
      |> assign(:agent_responding, agent_response_pending?(messages))
      |> assign(:has_messages, messages != [])
      # message_history! sorts newest-first; the list renders top-anchored
      # (oldest → newest, newest at the bottom) so we reverse to natural order.
      |> stream(:messages, Enum.reverse(messages), reset: true)
      |> assign_message_form()
    end
  end

  # Unread boundary (T2): the id of the FIRST message past my participant's
  # last_read_message_id cursor — the stream renders a "New" divider before it.
  # nil when nothing is unread (cursor at/after the latest message). `messages`
  # is newest-first (message_history! order).
  defp unread_boundary(socket, participants, messages) do
    cursor = my_read_cursor(socket, participants)
    # natural (oldest→newest) order to find the first unread
    ordered = Enum.reverse(messages)

    cond do
      ordered == [] ->
        nil

      # No cursor → everything is unread; boundary is the first message.
      is_nil(cursor) ->
        ordered |> Enum.at(0) |> message_id_of()

      true ->
        # First message whose id sorts after the cursor (uuid_v7 ids are
        # time-ordered, so string compare = chronological).
        ordered
        |> Enum.find(fn m -> message_id_of(m) > cursor end)
        |> case do
          nil -> nil
          m -> message_id_of(m)
        end
    end
  end

  # My participant's read cursor, from an already-loaded participant list (nil
  # if none / not joined).
  defp my_read_cursor(socket, participants) do
    user = socket.assigns[:current_user]

    with %_{} <- user,
         list when is_list(list) <- participants,
         %{} = mine <-
           Enum.find(list, fn p ->
             match?(%{membership: %{user_id: uid}} when uid == user.id, p)
           end) do
      mine.last_read_message_id
    else
      _ -> nil
    end
  end

  # Threads (T2): a thread is a child conversation seeded from a message. Load
  # the parent conversation's threads (with their messages) into a map keyed by
  # seed_message_id, so the stream can render a "N replies" chip under exactly
  # the messages that seeded one. The seed_message_id is the visible primitive.
  defp load_thread_map(socket, conversation_id) do
    Concept.Knowledge.Chat.get_conversation!(conversation_id,
      actor: socket.assigns.current_user,
      tenant: socket.assigns[:workspace_id],
      load: [threads: [:messages]]
    ).threads
    |> Enum.filter(& &1.seed_message_id)
    |> Map.new(fn thread -> {thread.seed_message_id, thread} end)
  rescue
    _ -> %{}
  end

  # ── Reactions (T4) ───────────────────────────────────────────────────
  # A {message_id => [%{emoji, count, mine?}]} map for the open conversation,
  # so the stream renders reaction chips per message (own-reaction highlighted).
  defp load_reactions_map(socket, conversation_id) do
    mine = my_membership_id(socket)

    Concept.Knowledge.Chat.reactions_for_conversation!(conversation_id,
      actor: socket.assigns.current_user,
      tenant: socket.assigns[:workspace_id]
    )
    |> Enum.group_by(& &1.message_id)
    |> Map.new(fn {message_id, reactions} ->
      chips =
        reactions
        |> Enum.group_by(& &1.emoji)
        |> Enum.map(fn {emoji, rs} ->
          %{emoji: emoji, count: length(rs), mine?: Enum.any?(rs, &(&1.membership_id == mine))}
        end)
        |> Enum.sort_by(& &1.emoji)

      {message_id, chips}
    end)
  rescue
    _ -> %{}
  end

  # The current user's membership id in this workspace (the reactor identity).
  defp my_membership_id(socket) do
    with %_{} = user <- socket.assigns[:current_user],
         ws when not is_nil(ws) <- socket.assigns[:workspace_id],
         {:ok, %{id: id}} <- Concept.Accounts.get_membership(user.id, ws, actor: user) do
      id
    else
      _ -> nil
    end
  end

  defp reactions_for(assigns, message) do
    Map.get(assigns[:reactions_map] || %{}, message_id_of(message), [])
  end

  # The quick-react palette shown in the compact popover.
  defp reaction_palette, do: ["👍", "❤️", "🎉", "🚀", "👀", "😄"]

  defp do_react(socket, message_id, emoji) do
    with mid when not is_nil(mid) <- socket.assigns[:my_membership_id],
         {:ok, _} <-
           Concept.Knowledge.Chat.react(
             %{
               workspace_id: socket.assigns[:workspace_id],
               message_id: message_id,
               membership_id: mid,
               emoji: emoji
             },
             actor: socket.assigns.current_user,
             tenant: socket.assigns[:workspace_id]
           ) do
      {:noreply, socket |> assign(:emoji_pop_for, nil) |> refresh_reactions(message_id)}
    else
      _ -> {:noreply, assign(socket, :emoji_pop_for, nil)}
    end
  end

  defp unreact_one(socket, message_id, emoji) do
    # Find my reaction row for this emoji and destroy it.
    mine = socket.assigns[:my_membership_id]

    Concept.Knowledge.Chat.reactions_for_message!(message_id,
      actor: socket.assigns.current_user,
      tenant: socket.assigns[:workspace_id]
    )
    |> Enum.find(fn r -> r.membership_id == mine and r.emoji == emoji end)
    |> case do
      nil ->
        {:noreply, socket}

      reaction ->
        Concept.Knowledge.Chat.unreact(reaction,
          actor: socket.assigns.current_user,
          tenant: socket.assigns[:workspace_id]
        )

        {:noreply, refresh_reactions(socket, message_id)}
    end
  end

  # Recompute the reactions map and re-stream the affected message so its chips
  # re-render (the chips live inside the streamed item).
  defp refresh_reactions(socket, message_id) do
    socket =
      if conv = socket.assigns[:conversation] do
        assign(socket, :reactions_map, load_reactions_map(socket, conv.id))
      else
        socket
      end

    restream_message(socket, message_id)
  end

  # ── Presence + typing (T3) ───────────────────────────────────────────────
  # Reuse Phoenix.Presence (the editor's mechanism) on a per-conversation topic.
  defp chat_presence_topic(conversation_id), do: "chat:conversation:#{conversation_id}:presence"

  # Track the current user on the conversation's presence topic. `typing?`
  # carries the live composer state. Subscribes once so presence_diff flows in.
  defp track_chat_presence(socket, conversation_id, typing?) do
    user = socket.assigns[:current_user]
    topic = chat_presence_topic(conversation_id)

    if user do
      ConceptWeb.Endpoint.subscribe(topic)

      meta = %{
        display_name: user.email |> to_string() |> String.split("@") |> hd(),
        color: ConceptWeb.Colors.for_user_id(user.id),
        online_at: System.system_time(:second),
        typing: typing?
      }

      # update if already tracked (typing flips), else track.
      case ConceptWeb.Presence.update(self(), topic, user.id, meta) do
        {:error, _} -> ConceptWeb.Presence.track(self(), topic, user.id, meta)
        _ -> :ok
      end
    end
  end

  # Presence entries for a conversation, as a list of %{id, display_name, color,
  # typing} (one per present user), excluding nothing — the template filters self.
  defp chat_presence_list(_socket, conversation_id) do
    chat_presence_topic(conversation_id)
    |> ConceptWeb.Presence.list()
    |> Enum.map(fn {user_id, %{metas: metas}} ->
      meta = List.first(metas) || %{}

      %{
        id: user_id,
        display_name: Map.get(meta, :display_name, ""),
        color: Map.get(meta, :color, "#9B9A97"),
        typing: Enum.any?(metas, &Map.get(&1, :typing, false))
      }
    end)
  end

  defp untrack_chat_presence(socket, conversation_id) do
    if user = socket.assigns[:current_user] do
      ConceptWeb.Presence.untrack(self(), chat_presence_topic(conversation_id), user.id)
      ConceptWeb.Endpoint.unsubscribe(chat_presence_topic(conversation_id))
    end
  end

  # Online collaborators other than me (for the header dots).
  defp chat_collaborators(assigns) do
    me = assigns[:current_user] && assigns.current_user.id
    (assigns[:chat_presence] || []) |> Enum.reject(&(&1.id == me))
  end

  # Humans (other than me) currently typing — the "X is typing" cue.
  defp chat_typing_names(assigns) do
    assigns
    |> chat_collaborators()
    |> Enum.filter(& &1.typing)
    |> Enum.map(& &1.display_name)
  end

  # Seen-by (T3): participants (other than me) whose read cursor has reached the
  # latest message — the read-receipt trust signal. Derived from
  # last_read_message_id; nil latest → nobody.
  defp seen_by(assigns) do
    latest = assigns[:latest_message_id]
    me = assigns[:current_user] && assigns.current_user.id

    if latest do
      for p <- assigns[:participants] || [],
          p.last_read_message_id == latest,
          membership_user_id(p) != me,
          do: p
    else
      []
    end
  end

  defp membership_user_id(%{membership: %{user_id: id}}), do: id
  defp membership_user_id(_), do: nil

  defp seen_by_label(%{membership: %{display_name: n}}) when is_binary(n) and n != "", do: n
  defp seen_by_label(_), do: "Member"

  defp seen_by_initial(p),
    do: p |> seen_by_label() |> String.first() |> Kernel.||("?") |> String.upcase()

  defp chat_typing_label([name]), do: "#{name} is typing…"
  defp chat_typing_label([a, b]), do: "#{a} and #{b} are typing…"
  defp chat_typing_label(names) when length(names) > 2, do: "several people are typing…"
  defp chat_typing_label(_), do: ""

  # A shareable link to a message: the workspace URL anchored on the message id.
  # A message is already addressable by id; the link is a pure client-side copy.
  defp message_link(assigns, message) do
    base = ConceptWeb.Endpoint.url()
    mid = message_id_of(message)

    case assigns[:conversation] do
      %{id: cid} -> "#{base}/chat/#{cid}#msg-#{mid}"
      _ -> "#{base}/chat#msg-#{mid}"
    end
  end

  # The thread seeded from this message, if any (nil otherwise).
  defp thread_for(assigns, message) do
    Map.get(assigns[:thread_map] || %{}, message_id_of(message))
  end

  defp thread_reply_count(nil), do: "0 replies"

  defp thread_reply_count(thread) do
    n = length(thread.messages || [])
    "#{n} #{ngettext("reply", "replies", n)}"
  end

  defp message_id_of(%{id: id}), do: id
  defp message_id_of(%{"id" => id}), do: id
  defp message_id_of(_), do: nil

  defp latest_message_id(assigns), do: assigns[:latest_message_id]

  # Re-insert a single message into the stream by id (e.g. to re-render its
  # wrapper after the unread boundary moved off it). No-op when id/conv is nil.
  defp restream_message(socket, nil), do: socket

  defp restream_message(socket, message_id) do
    case Concept.Knowledge.Chat.get_message(message_id,
           actor: socket.assigns[:current_user],
           tenant: socket.assigns[:workspace_id]
         ) do
      {:ok, message} -> stream_insert(socket, :messages, message)
      _ -> socket
    end
  end

  # The seed message's text, read from the current stream-backing thread_map's
  # parent conversation. We refetch the single message to render the seed pinned.
  defp seed_message_text(socket, seed_id) do
    case Concept.Knowledge.Chat.get_message(seed_id,
           actor: socket.assigns.current_user,
           tenant: socket.assigns[:workspace_id]
         ) do
      {:ok, %{text: text}} -> text
      _ -> ""
    end
  end

  # Re-load the open thread's replies + the thread_map after a reply lands.
  defp refresh_open_thread(socket) do
    conversation = socket.assigns[:conversation]
    ot = socket.assigns[:open_thread]

    if conversation && ot do
      thread_map = load_thread_map(socket, conversation.id)
      thread = Map.get(thread_map, ot.seed_id, ot.thread)
      replies = Enum.sort_by(thread.messages || [], & &1.inserted_at, DateTime)

      socket
      |> assign(:thread_map, thread_map)
      |> assign(:open_thread, %{ot | thread: thread, replies: replies})
    else
      socket
    end
  end

  defp clear_conversation(socket) do
    if socket.assigns[:conversation] do
      ConceptWeb.Endpoint.unsubscribe("chat:messages:#{socket.assigns.conversation.id}")
      untrack_chat_presence(socket, socket.assigns.conversation.id)
    end

    socket
    |> assign(:conversation, nil)
    |> assign(:agent_responding, false)
    |> assign(:has_messages, false)
    |> assign(:thread_map, %{})
    |> assign(:open_thread, nil)
    |> assign(:unread_boundary_id, nil)
    |> assign(:latest_message_id, nil)
    |> assign(:chat_presence, [])
    |> assign(:reactions_map, %{})
    |> assign(:emoji_pop_for, nil)
    |> stream(:messages, [], reset: true)
    |> assign_message_form()
  end

  # ── Mention composer (PLAN-010 §6.3) ────────────────────────────────────
  # Mentionable targets = the conversation's participants + the host's voice.
  # A trailing "@token" in the draft opens a server-rendered suggestion list
  # (no custom JS → fully driveable by Phoenix.LiveViewTest).
  @mention_regex ~r/@([\p{L}0-9_]*)$/u

  defp mention_state(text, socket) do
    case Regex.run(@mention_regex, text) do
      [_, query] ->
        {query, mention_suggestions(query, socket)}

      _ ->
        {nil, []}
    end
  end

  defp mention_suggestions(query, socket) do
    q = String.downcase(query)

    host = %{
      id: "host",
      label: host_voice_name(socket.assigns[:host_type] || :workspace),
      kind: "host"
    }

    participant_opts =
      for participant <- socket.assigns[:participants] || [] do
        %{
          id: participant.id,
          label: participant_name(participant),
          kind: to_string(participant.kind)
        }
      end

    [host | participant_opts]
    |> Enum.filter(fn opt -> q == "" or String.contains?(String.downcase(opt.label), q) end)
    |> Enum.take(6)
  end

  # Strip the trailing @token from the draft and close the suggestion list.
  defp close_mentions_with_stripped_draft(socket) do
    stripped = Regex.replace(@mention_regex, socket.assigns[:draft_text] || "", "")

    socket
    |> assign(:draft_text, stripped)
    |> assign(:initial_text, stripped)
    |> assign(:mention_query, nil)
    |> assign(:mention_suggestions, [])
    |> assign_message_form()
  end

  defp reset_composer(socket) do
    socket
    |> assign(:pending_mentions, [])
    |> assign(:addresses_host, true)
    |> assign(:mention_query, nil)
    |> assign(:mention_suggestions, [])
    |> assign(:draft_text, "")
  end

  # Participant rail (PLAN-010 §6.2). Participants ARE memberships (humans &
  # external agents). The host's grounded voice has NO participant row by design
  # (§39) — it's rendered as a synthetic entry from the conversation's host_type.
  defp load_participants(socket, conversation_id) do
    Concept.Knowledge.Chat.participants_for_conversation!(conversation_id,
      actor: socket.assigns.current_user,
      tenant: socket.assigns[:workspace_id],
      load: [:kind, :membership]
    )
  rescue
    _ -> []
  end

  defp participant_name(%{membership: %{display_name: name}}) when is_binary(name) and name != "",
    do: name

  defp participant_name(%{kind: :agent}), do: "Agent"
  defp participant_name(_), do: "Member"

  defp participant_initial(participant) do
    participant
    |> participant_name()
    |> String.first()
    |> Kernel.||("?")
    |> String.upcase()
  end

  defp get_current_conversation_id(socket) do
    if socket.assigns[:conversation], do: socket.assigns.conversation.id, else: nil
  end

  defp handle_broadcast(socket, %Phoenix.Socket.Broadcast{
         event: "presence_diff",
         topic: "chat:conversation:" <> rest
       }) do
    # Recompute presence for the open conversation (online dots + typing cue).
    conversation_id = String.trim_trailing(rest, ":presence")

    if socket.assigns[:conversation] && socket.assigns.conversation.id == conversation_id do
      assign(socket, :chat_presence, chat_presence_list(socket, conversation_id))
    else
      socket
    end
  end

  defp handle_broadcast(socket, %Phoenix.Socket.Broadcast{
         topic: "chat:messages:" <> conversation_id,
         payload: message
       }) do
    open_thread = socket.assigns[:open_thread]

    cond do
      socket.assigns.conversation && socket.assigns.conversation.id == conversation_id ->
        socket
        |> maybe_warn_tool_data(message)
        |> assign(:has_messages, true)
        |> stream_insert(:messages, message, at: -1)
        |> update_agent_responding(message)

      # A reply landed on the OPEN thread's child conversation (another
      # participant, or a grounded host reply) — refresh the panel so it appears
      # live, not only on reopen.
      match?(%{thread: %{id: ^conversation_id}}, open_thread) ->
        refresh_open_thread(socket)

      true ->
        socket
    end
  end

  defp handle_broadcast(socket, %Phoenix.Socket.Broadcast{
         topic: "chat:conversations:" <> _,
         payload: conversation
       }) do
    socket =
      if socket.assigns.conversation && socket.assigns.conversation.id == conversation.id do
        assign(socket, :conversation, conversation)
      else
        socket
      end

    # Only re-derive the rail when grouping can actually change: a new
    # conversation, or a changed title/host. The chat:conversations topic also
    # fires on every budget tick (decrement/replenish), which can't affect
    # grouping — re-projecting (2 DB reads) on those would be wasteful.
    if rail_grouping_changed?(socket, conversation),
      do: assign_rail(socket),
      else: socket
  end

  defp handle_broadcast(socket, _), do: socket

  # True iff this broadcast could change the rail's host grouping: a conversation
  # not yet in the rail, or one whose title/host differs from the held copy.
  # Budget-only updates (same id, title, host) return false — no DB re-read.
  defp rail_grouping_changed?(socket, conversation) do
    case Enum.find(socket.assigns[:rail_conversations] || [], &(&1.id == conversation.id)) do
      nil ->
        true

      existing ->
        Map.get(existing, :title) != Map.get(conversation, :title) or
          Map.get(existing, :host_type) != Map.get(conversation, :host_type) or
          Map.get(existing, :host_id) != Map.get(conversation, :host_id)
    end
  end

  def build_conversation_title_string(title) do
    cond do
      title == nil -> "Untitled conversation"
      is_binary(title) && String.length(title) > 25 -> String.slice(title, 0, 25) <> "..."
      is_binary(title) && String.length(title) <= 25 -> title
    end
  end

  # ── Adaptive rail (T1) ───────────────────────────────────────────────────
  # The rail is a PROJECTION over the conversation list, not a stream: it must
  # group the whole set (streams aren't enumerable). We hold the raw list for
  # re-derivation and a {page_id => title} label map for inline/category labels.
  defp assign_rail(socket) do
    conversations =
      if is_nil(socket.assigns[:current_user]) or is_nil(socket.assigns[:workspace_id]) do
        []
      else
        Concept.Knowledge.Chat.my_conversations!(
          actor: socket.assigns.current_user,
          tenant: socket.assigns.workspace_id
        )
      end

    socket
    |> assign(:rail_conversations, conversations)
    |> assign(:rail_groups, Concept.Chat.RailModel.group_by_host(conversations))
    |> assign(:page_labels, page_label_map(socket, conversations))
  end

  # Resolve page-host titles once (a single list_tree read), keyed by page id.
  # Pages not found fall back to a generic label at render.
  defp page_label_map(socket, conversations) do
    needs_pages? = Enum.any?(conversations, &(host_type_of(&1) == :page))

    with true <- needs_pages?,
         %_{} = user <- socket.assigns[:current_user],
         ws when not is_nil(ws) <- socket.assigns[:workspace_id],
         {:ok, pages} <- Concept.Pages.list_tree(actor: user, tenant: ws) do
      pages
      |> flatten_pages()
      |> Map.new(fn p -> {p.id, p.title} end)
    else
      _ -> %{}
    end
  end

  defp flatten_pages(pages) do
    Enum.flat_map(pages, fn p ->
      [p | flatten_pages(child_pages(p))]
    end)
  end

  defp child_pages(%{children: children}) when is_list(children), do: children
  defp child_pages(_), do: []

  defp host_type_of(%{host_type: t}), do: t
  defp host_type_of(%{"host_type" => t}), do: t
  defp host_type_of(_), do: :workspace

  # Display sections in Hostable.types() order, each carrying its host groups.
  defp rail_sections(groups) do
    groups
    |> Enum.chunk_by(&Concept.Chat.RailModel.section_for(&1.host_type))
    |> Enum.map(fn chunk ->
      %{section: Concept.Chat.RailModel.section_for(hd(chunk).host_type), groups: chunk}
    end)
  end

  defp host_key(group), do: "#{group.host_type}:#{group.host_id || "_"}"

  defp prebound_host(%{"host-type" => t, "host-id" => id}) when is_binary(t) and t != "",
    do: %{host_type: String.to_existing_atom(t), host_id: id}

  defp prebound_host(_), do: nil

  # The page hosts offered by the picker, filtered by the search query. The
  # workspace host is always offered (rendered statically). DM hosts (users)
  # arrive in T5 once Accounts.User is Hostable.
  defp host_picker_pages(socket, query) do
    q = String.downcase(query || "")

    with %_{} = user <- socket.assigns[:current_user],
         ws when not is_nil(ws) <- socket.assigns[:workspace_id],
         {:ok, pages} <- Concept.Pages.list_tree(actor: user, tenant: ws) do
      pages
      |> flatten_pages()
      |> Enum.filter(fn p -> q == "" or String.contains?(String.downcase(p.title || ""), q) end)
      |> Enum.take(20)
    else
      _ -> []
    end
  end

  # Workspace members who are not already participants of this conversation —
  # the addable set for the people-picker.
  defp addable_members(socket) do
    conversation = socket.assigns[:conversation]

    with %_{} = user <- socket.assigns[:current_user],
         ws when not is_nil(ws) <- socket.assigns[:workspace_id],
         {:ok, members} <- Concept.Accounts.list_members(ws, actor: user) do
      existing =
        if conversation do
          (socket.assigns[:participants] || [])
          |> Enum.map(& &1.membership_id)
          |> MapSet.new()
        else
          MapSet.new()
        end

      Enum.reject(members, &MapSet.member?(existing, &1.id))
    else
      _ -> []
    end
  end

  defp member_label(%{user: %{email: email}}) when not is_nil(email), do: to_string(email)
  defp member_label(_), do: "Member"

  defp member_initial(member) do
    member |> member_label() |> String.first() |> Kernel.||("?") |> String.upcase()
  end

  # Create (or route to) a conversation about the chosen host, then navigate to
  # it. This is the discuss action's resolution: a conversation is always about
  # a host. An optional topic seeds the conversation title.
  defp start_conversation(socket, host_type, host_id, topic) do
    if is_nil(socket.assigns[:current_user]) do
      {:noreply, put_flash(socket, :error, "You must sign in to start a conversation")}
    else
      attrs =
        %{host_type: host_type, host_id: host_id, workspace_id: socket.assigns[:workspace_id]}
        |> then(fn a -> if topic, do: Map.put(a, :title, topic), else: a end)

      case Concept.Knowledge.Chat.create_conversation(attrs,
             actor: socket.assigns.current_user,
             tenant: socket.assigns[:workspace_id]
           ) do
        {:ok, conversation} ->
          send(self(), {:chat_component_navigate, conversation.id})
          {:noreply, assign(socket, :host_picker_open, false)}

        {:error, _} ->
          {:noreply,
           socket
           |> assign(:host_picker_open, false)
           |> put_flash(:error, "Could not start the conversation.")}
      end
    end
  end

  defp conv_selected?(nil, _conversation), do: false
  defp conv_selected?(current, conversation), do: current.id == conversation.id

  defp rail_conversation_title(%{title: title}), do: build_conversation_title_string(title)
  defp rail_conversation_title(_), do: "Untitled conversation"

  # The label for a host category header / inline host glyph row.
  defp host_group_label(%{host_type: :workspace}, _assigns), do: "Workspace"

  defp host_group_label(%{host_type: :page, host_id: id}, assigns) do
    Map.get(assigns[:page_labels] || %{}, id) || "Page"
  end

  defp host_group_label(%{host_type: type}, _assigns), do: "#{type}"

  # The muted "in <host>" ref shown on hover for an inline (single-conversation)
  # host. Nil for the workspace host (no useful ref — it's the default place).
  defp inline_host_ref(%{host_type: :workspace}, _assigns), do: nil
  defp inline_host_ref(group, assigns), do: host_group_label(group, assigns)

  defp assign_message_form(socket) do
    # Build base arguments with optional scope+profile from assigns
    base_args = %{}

    base_args =
      if socket.assigns[:message_scope],
        do: Map.put(base_args, :scope, socket.assigns.message_scope),
        else: base_args

    base_args =
      if socket.assigns[:message_profile],
        do: Map.put(base_args, :profile, socket.assigns.message_profile),
        else: base_args

    base_args =
      if socket.assigns[:initial_text],
        do: Map.put(base_args, :text, socket.assigns.initial_text),
        else: base_args

    # Addressing (PLAN-010 §6.1/§6.3): host_type/host_id/mentions/addresses_host
    # are baked into the form's create args here AND re-merged into the submit
    # params by send_message/3 (AshPhoenix.Form.submit/2 with `params:` REPLACES
    # the param set, so they must be present at submit too — see addressing_params/1).
    base_args = Map.merge(base_args, addressing_params(socket))

    tenant = socket.assigns[:workspace_id]

    form =
      if socket.assigns.conversation do
        Concept.Knowledge.Chat.form_to_create_message(
          actor: socket.assigns.current_user,
          tenant: tenant,
          params: base_args,
          private_arguments: %{conversation_id: socket.assigns.conversation.id}
        )
        |> to_form()
      else
        Concept.Knowledge.Chat.form_to_create_message(
          actor: socket.assigns.current_user,
          tenant: tenant,
          params: base_args
        )
        |> to_form()
      end

    socket
    |> assign(:message_form, form)
    |> assign(:initial_text, nil)
    |> assign(:message_form_host_key, {socket.assigns[:host_type], socket.assigns[:host_id]})
  end

  # The addressing args, as STRING-keyed params (so they merge cleanly into the
  # form-submitted params and survive AshPhoenix.Form.submit/2's param replace).
  defp addressing_params(socket) do
    %{
      "host_type" => to_string(socket.assigns[:host_type] || :workspace),
      "host_id" => socket.assigns[:host_id],
      "mentions" => Enum.map(socket.assigns[:pending_mentions] || [], & &1.id),
      "addresses_host" => socket.assigns[:addresses_host] != false
    }
  end

  defp maybe_warn_tool_data(socket, messages) when is_list(messages) do
    Enum.reduce(messages, socket, fn message, acc ->
      maybe_warn_tool_data(acc, message)
    end)
  end

  defp maybe_warn_tool_data(socket, message) do
    if agent_message?(message) do
      case @chat_ui_tools.extract(message) do
        {:ok, _} ->
          socket

        {:error, _} ->
          maybe_put_tool_data_warning(socket)
      end
    else
      socket
    end
  end

  defp maybe_put_tool_data_warning(socket) do
    if socket.assigns[:tool_data_warning_shown?] do
      socket
    else
      socket
      |> put_flash(:warning, "Some tool call data could not be displayed.")
      |> assign(:tool_data_warning_shown?, true)
    end
  end

  defp message_source(%{source: source}), do: source
  defp message_source(%{"source" => source}), do: source
  defp message_source(_), do: nil

  defp sender_participant_id(%{sender_participant_id: id}), do: id
  defp sender_participant_id(%{"sender_participant_id" => id}), do: id
  defp sender_participant_id(_), do: nil

  # Presentation discriminator (PLAN-010 §6.1). The domain keeps `source`
  # (:user/:agent) as the transitional shim and `sender_participant_id` as the
  # forward-looking identity: nil ⇒ the HOST's grounded voice spoke (no identity);
  # present ⇒ an external agent. Humans are :user-sourced.
  defp sender_kind(message) do
    cond do
      message_source(message) in [:user, "user"] -> :human
      not is_nil(sender_participant_id(message)) -> :agent
      true -> :host
    end
  end

  defp sender_label(message, assigns) do
    case sender_kind(message) do
      :human -> "You"
      :agent -> "Agent"
      :host -> host_voice_name(assigns[:host_type] || :workspace)
    end
  end

  # The host's voice label — it speaks AS the host, not as a person.
  defp host_voice_name(:page), do: "This page"
  defp host_voice_name(:workspace), do: "Concept AI"
  defp host_voice_name(host_type), do: "This #{host_type}"

  defp host_label(assigns) do
    case assigns[:host_type] || :workspace do
      :workspace -> "Concept AI · workspace"
      :page -> "Conversation about this page"
      host_type -> "Conversation about this #{host_type}"
    end
  end

  defp host_icon(:page), do: "hero-document-text-micro"
  defp host_icon(:workspace), do: "hero-sparkles-micro"
  defp host_icon(_), do: "hero-cube-micro"

  defp message_complete?(%{complete: complete}), do: complete in [true, "true"]
  defp message_complete?(%{"complete" => complete}), do: complete in [true, "true"]
  defp message_complete?(_), do: false

  defp user_message?(message), do: message_source(message) in [:user, "user"]
  defp agent_message?(message), do: message_source(message) in [:agent, "agent"]

  defp update_agent_responding(socket, message) do
    cond do
      user_message?(message) ->
        assign(socket, :agent_responding, true)

      agent_message?(message) ->
        assign(socket, :agent_responding, !message_complete?(message))

      true ->
        socket
    end
  end

  defp agent_response_pending?(messages) do
    case Enum.find(messages, fn message -> user_message?(message) or agent_message?(message) end) do
      nil -> false
      message -> user_message?(message) || !message_complete?(message)
    end
  end

  defp to_markdown(text) do
    MDEx.to_html(text,
      extension: [
        strikethrough: true,
        tagfilter: true,
        table: true,
        autolink: true,
        tasklist: true,
        footnotes: true,
        shortcodes: true
      ],
      parse: [
        smart: true,
        relaxed_tasklist_matching: true,
        relaxed_autolinks: true
      ],
      render: [
        github_pre_lang: true,
        unsafe: true
      ],
      sanitize: MDEx.Document.default_sanitize_options()
    )
    |> case do
      {:ok, html} ->
        html
        |> Phoenix.HTML.raw()

      {:error, _} ->
        text
    end
  end
end
