defmodule ConceptWeb.ChatComponent do
  use ConceptWeb, :live_component
  @chat_ui_tools AshAi.ChatUI.Tools

  @impl true
  def update(%{broadcast: broadcast}, socket) do
    {:ok, handle_broadcast(socket, broadcast)}
  end

  def update(assigns, socket) do
    socket = assign(socket, assigns)

    socket =
      if !socket.assigns[:initialized] do
        conversations =
          if true && is_nil(socket.assigns.current_user) do
            []
          else
            Concept.Knowledge.Chat.my_conversations!(actor: socket.assigns.current_user)
          end

        socket
        |> assign(:initialized, true)
        |> assign_new(:hide_sidebar, fn -> false end)
        |> assign_new(:conversation, fn -> nil end)
        |> assign_new(:conversation_id, fn -> nil end)
        |> assign_new(:agent_responding, fn -> false end)
        |> assign_new(:tool_data_warning_shown?, fn -> false end)
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
    <div id={@id} class="flex bg-base-200 min-h-full max-h-full">
      <div :if={!@hide_sidebar} class="w-72 border-r bg-base-300 flex flex-col overflow-y-auto">
        <div class="py-4 px-6">
          <div class="text-lg mb-4">
            Conversations
          </div>
          <div class="mb-4">
            <button phx-click="new_chat" phx-target={@myself} class="btn btn-primary btn-lg mb-2">
              <div class="rounded-full bg-primary-content text-primary w-6 h-6 flex items-center justify-center">
                <.icon name="hero-plus" />
              </div>
              <span>New Chat</span>
            </button>
          </div>
          <ul class="flex flex-col-reverse" phx-update="stream" id={"#{@id}-conversations-list"}>
            <%= for {id, conversation} <- @streams.conversations do %>
              <li id={id}>
                <button
                  phx-click="select_conversation"
                  phx-target={@myself}
                  phx-value-id={conversation.id}
                  class={"block py-2 px-3 transition border-l-4 pl-2 mb-2 w-full text-left #{if @conversation && @conversation.id == conversation.id, do: "border-primary font-medium", else: "border-transparent"}"}
                >
                  {build_conversation_title_string(conversation.title)}
                </button>
              </li>
            <% end %>
          </ul>
        </div>
      </div>

      <div class="flex-1 flex flex-col">
        <.flash kind={:info} flash={@flash} />
        <.flash kind={:error} flash={@flash} />
        <div
          :if={Phoenix.Flash.get(@flash, :warning)}
          class="alert alert-warning m-4 mb-0 text-sm"
        >
          {Phoenix.Flash.get(@flash, :warning)}
        </div>
        <div class="navbar bg-base-300 w-full">
          <img
            src="https://github.com/ash-project/ash_ai/blob/main/logos/ash_ai.png?raw=true"
            alt="Logo"
            class="h-12"
            height="48"
          />
          <div class="mx-2 flex-1 px-2">
            <p :if={@conversation}>{build_conversation_title_string(@conversation.title)}</p>
            <p class="text-xs">AshAi</p>
          </div>
        </div>

        <div class="flex-1 flex flex-col overflow-y-scroll bg-base-200">
          <div
            id={"#{@id}-message-container"}
            phx-update="stream"
            class="flex-1 overflow-y-auto overflow-x-hidden px-4 py-2 flex flex-col-reverse"
          >
            <%= for {id, message} <- @streams.messages do %>
              <div
                id={id}
                class={[
                  "chat",
                  message.source == :user && "chat-end",
                  message.source == :agent && "chat-start"
                ]}
              >
                <div :if={message.source == :agent} class="chat-image avatar">
                  <div class="w-10 rounded-full bg-base-300 p-1">
                    <img
                      src="https://github.com/ash-project/ash_ai/blob/main/logos/ash_ai.png?raw=true"
                      alt="Logo"
                    />
                  </div>
                </div>
                <div :if={message.source == :user} class="chat-image avatar avatar-placeholder">
                  <div class="w-10 rounded-full bg-base-300">
                    <.icon name="hero-user-solid" class="block" />
                  </div>
                </div>
                <div
                  :if={message.source == :agent && tool_calls(message) != []}
                  class="mt-2 flex w-full max-w-[36rem] min-w-0 flex-wrap gap-1 text-[11px] opacity-80"
                >
                  <%= for tool_call <- tool_calls(message) do %>
                    <span class="badge badge-outline badge-info max-w-full min-w-0 justify-start overflow-hidden text-ellipsis whitespace-nowrap">
                      tool: {tool_call.name}
                      <span :if={tool_call.arguments != %{}}>
                        ({tool_call.arguments_preview})
                      </span>
                    </span>
                  <% end %>
                </div>
                <div
                  :if={message.source == :agent && tool_results(message) != []}
                  class="chat-footer mt-1 flex w-full max-w-[36rem] min-w-0 flex-col gap-1"
                >
                  <%= for tool_result <- tool_results(message) do %>
                    <div class={[
                      "rounded max-w-full overflow-hidden px-2 py-1 text-xs leading-relaxed break-words",
                      tool_result.is_error && "bg-error/20",
                      !tool_result.is_error && "bg-base-300"
                    ]}>
                      <span class="font-semibold">
                        {if tool_result.is_error, do: "tool_error", else: "tool_result"}
                      </span>
                      <span :if={tool_result.name}> ({tool_result.name})</span>
                      <span class="break-all">
                        : {tool_result.content_preview}
                      </span>
                    </div>
                  <% end %>
                </div>
                <div :if={String.trim(message.text || "") != ""} class="chat-bubble">
                  {to_markdown(message.text || "")}
                </div>
              </div>
            <% end %>
          </div>
        </div>
        <div :if={@agent_responding} class="px-4 py-2 text-xs opacity-80 flex items-center gap-2">
          <span class="loading loading-dots loading-sm" />
          <span>AshAi is responding...</span>
        </div>
        <div class="p-4 border-t">
          <.form
            :let={form}
            for={@message_form}
            phx-change="validate_message"
            phx-target={@myself}
            phx-debounce="blur"
            phx-submit="send_message"
            class="flex items-center gap-4"
          >
            <div class="flex-1">
              <input
                name={form[:text].name}
                value={form[:text].value}
                type="text"
                phx-mounted={JS.focus()}
                placeholder="Type your message..."
                class="input input-primary w-full mb-0"
                autocomplete="off"
              />
            </div>
            <button type="submit" class="btn btn-primary rounded-full">
              <.icon name="hero-paper-airplane" /> Send
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

  defp load_conversation(socket, conversation_id) do
    if true && is_nil(socket.assigns.current_user) do
      socket
      |> put_flash(:error, "You must sign in to access conversations")
      |> clear_conversation()
    else
      conversation =
        Concept.Knowledge.Chat.get_conversation!(conversation_id,
          actor: socket.assigns.current_user
        )

      messages = Concept.Knowledge.Chat.message_history!(conversation.id, stream?: true)

      ConceptWeb.Endpoint.subscribe("chat:messages:#{conversation.id}")

      socket
      |> maybe_warn_tool_data(messages)
      |> assign(:conversation, conversation)
      |> assign(:agent_responding, agent_response_pending?(messages))
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
    form =
      if socket.assigns.conversation do
        Concept.Knowledge.Chat.form_to_create_message(
          actor: socket.assigns.current_user,
          private_arguments: %{conversation_id: socket.assigns.conversation.id}
        )
        |> to_form()
      else
        Concept.Knowledge.Chat.form_to_create_message(actor: socket.assigns.current_user)
        |> to_form()
      end

    assign(
      socket,
      :message_form,
      form
    )
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
