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
        conversations =
          if is_nil(socket.assigns.current_user) or is_nil(socket.assigns[:workspace_id]) do
            []
          else
            Concept.Knowledge.Chat.my_conversations!(
              actor: socket.assigns.current_user,
              tenant: socket.assigns.workspace_id
            )
          end

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
        |> assign_new(:participants, fn -> [] end)
        |> assign_new(:pending_mentions, fn -> [] end)
        |> assign_new(:addresses_host, fn -> true end)
        |> assign_new(:mention_query, fn -> nil end)
        |> assign_new(:mention_suggestions, fn -> [] end)
        |> assign_new(:draft_text, fn -> "" end)
        |> stream(:conversations, conversations)
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
        class="w-72 border-r border-notion-divider bg-notion-sidebar flex flex-col overflow-y-auto"
      >
        <div class="py-4 px-6">
          <div class="text-sm font-semibold text-notion-text-light mb-3">Conversations</div>
          <button
            phx-click="new_chat"
            phx-target={@myself}
            class="ora-btn ora-btn--primary w-full justify-center mb-3"
          >
            <.icon name="hero-plus-micro" class="size-4" /> New Chat
          </button>
          <ul class="flex flex-col-reverse" phx-update="stream" id={"#{@id}-conversations-list"}>
            <%= for {id, conversation} <- @streams.conversations do %>
              <li id={id}>
                <button
                  phx-click="select_conversation"
                  phx-target={@myself}
                  phx-value-id={conversation.id}
                  class={[
                    "block py-2 px-3 transition border-l-2 pl-2 mb-1 w-full text-left text-sm",
                    if(@conversation && @conversation.id == conversation.id,
                      do: "border-notion-blue font-medium text-notion-text",
                      else: "border-transparent text-notion-text-light hover:text-notion-text"
                    )
                  ]}
                >
                  {build_conversation_title_string(conversation.title)}
                </button>
              </li>
            <% end %>
          </ul>
        </div>
      </div>

      <div class="flex-1 flex flex-col min-w-0">
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
            class="ora-chat-messages"
          >
              <%!-- Dispatch on Concept.Chat.MessageKind.render_mode/1 — the single
                    source of truth. Host replies SEEP in (fused continuation,
                    no avatar); humans/agents take a row. Raw tool plumbing never
                    renders in the stream — it lives behind "Why this answer?". --%>
            <%= for {id, message} <- @streams.messages do %>
              <% mode = Concept.Chat.MessageKind.render_mode(message) %>
              <div
                id={id}
                data-render-mode={mode}
                class={[
                  "ora-chat-message",
                  mode == :human_row && "ora-chat-message--user",
                  mode == :agent_row && "ora-chat-message--agent",
                  mode in [:host_seep, :host_note] && "ora-chat-message--seep"
                ]}
              >
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
                </div>
              </div>
            <% end %>
          </div>
        </div>

        <div
          :if={@agent_responding}
          class="px-4 py-2 text-xs text-notion-text-light flex items-center gap-2"
        >
          <span class="inline-block w-2 h-2 rounded-full bg-notion-blue animate-pulse" />
          <span>AshAi is responding…</span>
        </div>

        <div
          :if={@conversation}
          id={"#{@id}-participant-rail"}
          class="flex flex-wrap items-center gap-2 px-4 py-2 border-t border-notion-divider bg-notion-sidebar/40"
        >
          <span class="text-xs uppercase tracking-wide text-notion-text-light mr-1">
            In this conversation
          </span>
          <%!-- Crystallize: talk becomes durable document on the host page
               (PLAN-010 §6.4). Only meaningful when the host IS a page. --%>
          <button
            :if={@host_type == :page and @host_id}
            type="button"
            id={"#{@id}-crystallize-btn"}
            phx-click="crystallize"
            phx-target={@myself}
            class="ml-auto inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs bg-emerald-100 text-emerald-700 hover:bg-emerald-200"
            title="Clone this conversation's blocks onto the page (copy, with provenance)"
          >
            <.icon name="hero-sparkles-micro" class="size-3" /> Crystallize into Page
          </button>
          <%!-- The host's grounded voice: a voice, not a person (PLAN-010 §39). --%>
          <span
            class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs bg-notion-blue/10 text-notion-blue"
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
            <button type="submit" class="ora-btn ora-btn--primary">
              <.icon name="hero-paper-airplane-micro" class="size-4" /> Send
            </button>
          </.form>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("validate_message", %{"form" => params}, socket) do
    text = params["text"] || ""

    {mention_query, suggestions} = mention_state(text, socket)

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
    if true && is_nil(socket.assigns.current_user) do
      {:noreply, put_flash(socket, :error, "You must sign in to send messages")}
    else
      # Re-merge addressing into the submit params: AshPhoenix.Form.submit/2 with
      # `params:` REPLACES the param set built in assign_message_form, so host_type/
      # host_id/mentions/addresses_host must be present here too or the action
      # defaults (→ :workspace) win and a page message would mis-route.
      params = Map.merge(addressing_params(socket), params)

      case AshPhoenix.Form.submit(socket.assigns.message_form, params: params) do
        {:ok, message} ->
          socket = reset_composer(socket)

          if socket.assigns.conversation do
            socket
            |> assign(:agent_responding, true)
            |> assign(:has_messages, true)
            |> assign_message_form()
            |> stream_insert(:messages, message, at: 0)
            |> then(&{:noreply, &1})
          else
            send(self(), {:chat_component_navigate, message.conversation_id})
            {:noreply, assign_message_form(socket)}
          end

        {:error, form} ->
          {:noreply, assign(socket, :message_form, form)}
      end
    end
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
  def handle_event("seed_prompt", %{"prompt" => prompt}, socket) do
    socket =
      socket
      |> assign(:initial_text, prompt)
      |> assign_message_form()

    {:noreply, socket}
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

      ConceptWeb.Endpoint.subscribe("chat:messages:#{conversation.id}")

      socket
      |> maybe_warn_tool_data(messages)
      |> assign(:conversation, conversation)
      # Reflect the loaded conversation's actual host (a page/thread convo keeps
      # its host voice + crystallize affordance), falling back to :workspace.
      |> assign(:host_type, conversation.host_type || :workspace)
      |> assign(:host_id, conversation.host_id)
      |> assign(:participants, load_participants(socket, conversation.id))
      |> assign(:agent_responding, agent_response_pending?(messages))
      |> assign(:has_messages, messages != [])
      |> stream(:messages, messages, reset: true)
      |> assign_message_form()
    end
  end

  defp clear_conversation(socket) do
    if socket.assigns[:conversation] do
      ConceptWeb.Endpoint.unsubscribe("chat:messages:#{socket.assigns.conversation.id}")
    end

    socket
    |> assign(:conversation, nil)
    |> assign(:agent_responding, false)
    |> assign(:has_messages, false)
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
         topic: "chat:messages:" <> conversation_id,
         payload: message
       }) do
    if socket.assigns.conversation && socket.assigns.conversation.id == conversation_id do
      socket
      |> maybe_warn_tool_data(message)
      |> assign(:has_messages, true)
      |> stream_insert(:messages, message, at: 0)
      |> update_agent_responding(message)
    else
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

    stream_insert(socket, :conversations, conversation)
  end

  defp handle_broadcast(socket, _), do: socket

  def build_conversation_title_string(title) do
    cond do
      title == nil -> "Untitled conversation"
      is_binary(title) && String.length(title) > 25 -> String.slice(title, 0, 25) <> "..."
      is_binary(title) && String.length(title) <= 25 -> title
    end
  end

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
