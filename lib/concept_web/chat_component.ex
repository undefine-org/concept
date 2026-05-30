defmodule ConceptWeb.ChatComponent do
  use ConceptWeb, :live_component
  import ConceptWeb.Components.WhyThisAnswer
  @chat_ui_tools AshAi.ChatUI.Tools

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

        socket
        |> assign(:initialized, true)
        |> assign_new(:hide_sidebar, fn -> false end)
        |> assign_new(:conversation, fn -> nil end)
        |> assign_new(:conversation_id, fn -> nil end)
        |> assign_new(:agent_responding, fn -> false end)
        |> assign_new(:tool_data_warning_shown?, fn -> false end)
        |> assign_new(:has_messages, fn -> false end)
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
            <%= for {id, message} <- @streams.messages do %>
              <div
                id={id}
                class={[
                  "ora-chat-message",
                  sender_kind(message) == :human && "ora-chat-message--user",
                  sender_kind(message) in [:agent, :host] && "ora-chat-message--agent"
                ]}
              >
                <span
                  :if={sender_kind(message) in [:agent, :host]}
                  class="ora-chat-avatar"
                  title={sender_label(message, assigns)}
                >
                  <.icon
                    name={if(sender_kind(message) == :host, do: "hero-sparkles-micro", else: "hero-cpu-chip-micro")}
                    class={[
                      "size-4",
                      sender_kind(message) == :host && "text-notion-blue",
                      sender_kind(message) == :agent && "text-violet-500"
                    ]}
                  />
                </span>
                <span :if={sender_kind(message) == :human} class="ora-chat-avatar">
                  <.icon name="hero-user-micro" class="size-4 text-notion-text-light" />
                </span>
                <div class="flex flex-col gap-1 min-w-0">
                  <div :if={String.trim(message.text || "") != ""} class="ora-chat-bubble">
                    {to_markdown(message.text || "")}
                  </div>
                  <div
                    :if={sender_kind(message) in [:agent, :host] && tool_calls(message) != []}
                    class="flex flex-wrap gap-1"
                  >
                    <span :for={tool_call <- tool_calls(message)} class="ora-chat-toolcall">
                      {tool_call.name}<span :if={tool_call.arguments != %{}}> ({tool_call.arguments_preview})</span>
                    </span>
                  </div>
                  <div
                    :if={sender_kind(message) in [:agent, :host] && tool_results(message) != []}
                    class="flex flex-col gap-1"
                  >
                    <div
                      :for={tool_result <- tool_results(message)}
                      class={[
                        "ora-chat-toolresult",
                        tool_result.is_error && "ora-chat-toolresult--error"
                      ]}
                    >
                      <span class="font-semibold">
                        {if tool_result.is_error, do: "error", else: "result"}
                      </span>
                      <span :if={tool_result.name}> ({tool_result.name})</span>: {tool_result.content_preview}
                    </div>
                  </div>
                  <div :if={sender_kind(message) in [:agent, :host]} class="mt-1">
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

        <div class="ora-chat-input-row">
          <.form
            :let={form}
            for={@message_form}
            phx-change="validate_message"
            phx-target={@myself}
            phx-debounce="blur"
            phx-submit="send_message"
            class="flex items-center gap-2 w-full"
          >
            <input
              name={form[:text].name}
              value={form[:text].value}
              type="text"
              phx-mounted={JS.focus()}
              placeholder="Type your message…"
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
    {:noreply,
     assign(socket, :message_form, AshPhoenix.Form.validate(socket.assigns.message_form, params))}
  end

  @impl true
  def handle_event("send_message", %{"form" => params}, socket) do
    if true && is_nil(socket.assigns.current_user) do
      {:noreply, put_flash(socket, :error, "You must sign in to send messages")}
    else
      case AshPhoenix.Form.submit(socket.assigns.message_form, params: params) do
        {:ok, message} ->
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

    # Host addressing: include host_type/host_id so a brand-new message routes to
    # (or creates) the host's ROOT conversation via find-or-create. Once a
    # conversation is loaded we post into it directly (conversation_id wins in
    # CreateConversationIfNotProvided's resolution order).
    base_args =
      base_args
      |> Map.put(:host_type, socket.assigns[:host_type] || :workspace)
      |> Map.put(:host_id, socket.assigns[:host_id])

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
  end

  defp tool_calls(message), do: safe_extract(message).tool_calls

  defp tool_results(message), do: safe_extract(message).tool_results

  defp safe_extract(message) do
    case @chat_ui_tools.extract(message) do
      {:ok, extracted} ->
        extracted

      {:error, _} ->
        %{tool_calls: [], tool_results: []}
    end
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
