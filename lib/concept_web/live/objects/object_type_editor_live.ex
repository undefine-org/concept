defmodule ConceptWeb.ObjectTypeEditorLive do
  @moduledoc """
  The database-builder editor: create object types, configure their fields,
  and (via the embedded workflow editor) draw their lifecycle.

  This is the human projection of the Objects domain — the same surface MCP
  tools drive. Two live actions:

    * `:index` — list/create/rename types at `/w/:slug/types`
    * `:edit`  — a single type's fields + workflow at `/w/:slug/types/:type_id`

  LiveView purity (EX9001): all data access goes through `Concept.Objects` /
  `Concept.Accounts` code-interface fns — no `Ash.Query`/`Ash.Changeset` here.
  Field config UIs are generic projections over the `FieldTypes` registry via
  `ConceptWeb.Objects.FieldTypeComponent` (no per-type branching).
  """
  use ConceptWeb, :live_view

  alias Concept.Accounts
  alias Concept.Objects
  alias Concept.Objects.FieldTypes
  alias Concept.Pages.FractionalIndex

  @impl true
  def mount(%{"workspace_slug" => slug} = params, _session, socket) do
    user = socket.assigns.current_user

    case Accounts.Workspace.by_slug(slug, actor: user) do
      {:ok, ws} ->
        {:ok,
         socket
         |> assign(:workspace, ws)
         |> assign(:new_type_name, "")
         |> assign(:new_field_name, "")
         |> assign(:new_field_type, "text")
         |> apply_action(socket.assigns.live_action, params)}

      _ ->
        {:ok, socket |> put_flash(:error, "Workspace not found") |> push_navigate(to: ~p"/w")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Object types")
    |> assign(:type, nil)
    |> load_types()
  end

  defp apply_action(socket, :edit, %{"type_id" => type_id}) do
    %{workspace: ws} = socket.assigns
    user = socket.assigns.current_user

    case Objects.get_object_type(type_id, actor: user, tenant: ws.id) do
      {:ok, type} ->
        socket
        |> assign(:page_title, "Edit #{type.name}")
        |> assign(:type, type)
        |> load_fields()

      _ ->
        socket
        |> put_flash(:error, "Type not found")
        |> push_navigate(to: ~p"/w/#{ws.slug}/types")
    end
  end

  # ── events: types ────────────────────────────────────────────────────

  @impl true
  def handle_event("create_type", %{"name" => name}, socket) do
    name = String.trim(name)
    %{workspace: ws} = socket.assigns
    user = socket.assigns.current_user

    if name == "" do
      {:noreply, socket}
    else
      case Objects.create_object_type(name, actor: user, tenant: ws.id) do
        {:ok, _type} -> {:noreply, socket |> assign(:new_type_name, "") |> load_types()}
        {:error, _} -> {:noreply, put_flash(socket, :error, "Could not create type")}
      end
    end
  end

  def handle_event("rename_type", %{"type_id" => id, "name" => name}, socket) do
    name = String.trim(name)
    %{workspace: ws} = socket.assigns
    user = socket.assigns.current_user

    with false <- name == "",
         {:ok, type} <- Objects.get_object_type(id, actor: user, tenant: ws.id),
         {:ok, _} <- Objects.rename_object_type(type, name, actor: user, tenant: ws.id) do
      {:noreply, refresh(socket)}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not rename")}
    end
  end

  # ── events: fields ───────────────────────────────────────────────────

  def handle_event("add_field", %{"name" => name, "field_type" => ft}, %{assigns: %{type: type}} = socket)
      when not is_nil(type) do
    name = String.trim(name)
    %{workspace: ws} = socket.assigns
    user = socket.assigns.current_user

    # Resolve the client-supplied field_type via the registry's safe resolver
    # (never String.to_existing_atom on raw input — a crafted websocket event
    # would raise ArgumentError and crash the LiveView).
    with false <- name == "",
         {:ok, ft_atom} <- FieldTypes.resolve(ft),
         {:ok, _} <-
           Objects.create_field_def(type.id, name, ft_atom, actor: user, tenant: ws.id) do
      {:noreply,
       socket |> assign(:new_field_name, "") |> assign(:new_field_type, "text") |> load_fields()}
    else
      true -> {:noreply, socket}
      {:error, :unknown_type} -> {:noreply, put_flash(socket, :error, "Unknown field type")}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not add field")}
    end
  end

  def handle_event("update_field", %{"field_id" => id} = params, %{assigns: %{fields: fields}} = socket)
      when is_list(fields) do
    %{workspace: ws} = socket.assigns
    user = socket.assigns.current_user
    fd = Enum.find(fields, &(&1.id == id))

    if fd do
      attrs = field_update_attrs(fd, params)

      case Objects.update_field_def(fd, attrs.name, attrs.required?, attrs.config,
             actor: user,
             tenant: ws.id
           ) do
        {:ok, _} -> {:noreply, load_fields(socket)}
        {:error, _} -> {:noreply, put_flash(socket, :error, "Could not update field")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("reorder_field", %{"id" => id, "dir" => dir}, %{assigns: %{fields: fields}} = socket)
      when is_list(fields) do
    %{workspace: ws} = socket.assigns
    user = socket.assigns.current_user
    i = Enum.find_index(fields, &(&1.id == id))

    # Single atomic write: compute one fractional position between the new
    # neighbours (LexoRank via FractionalIndex) and move the field there. One
    # write = no partial-failure corruption (the prior swap could leave two
    # fields sharing a position if the second write failed; the position index
    # is non-unique so that would silently corrupt order).
    with fd when not is_nil(fd) <- (is_integer(i) && Enum.at(fields, i)) || nil,
         pos when is_binary(pos) <- target_position(fields, i, dir),
         {:ok, _} <- Objects.reorder_field_def(fd, pos, actor: user, tenant: ws.id) do
      {:noreply, load_fields(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  # Catch-all: any unhandled event (field events pushed on :index with no type
  # loaded, or component-scoped events like guard edits that arrive at the
  # page level via a crafted client message) is ignored rather than crashing
  # the LiveView process.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # ── data loading (code-interface only) ───────────────────────────────

  defp load_types(socket) do
    %{workspace: ws} = socket.assigns
    user = socket.assigns.current_user

    case Objects.list_object_types(actor: user, tenant: ws.id) do
      {:ok, types} -> assign(socket, :types, types)
      _ -> assign(socket, :types, [])
    end
  end

  defp load_fields(socket) do
    %{workspace: ws, type: type} = socket.assigns
    user = socket.assigns.current_user

    case Objects.list_field_defs(type.id, actor: user, tenant: ws.id) do
      {:ok, fields} -> assign(socket, :fields, fields)
      _ -> assign(socket, :fields, [])
    end
  end

  defp refresh(%{assigns: %{live_action: :index}} = socket), do: load_types(socket)

  defp refresh(%{assigns: %{type: type}} = socket) when not is_nil(type) do
    %{workspace: ws} = socket.assigns
    user = socket.assigns.current_user

    case Objects.get_object_type(type.id, actor: user, tenant: ws.id) do
      {:ok, t} -> socket |> assign(:type, t) |> load_fields()
      _ -> socket
    end
  end

  defp refresh(socket), do: socket

  # ── helpers ──────────────────────────────────────────────────────────

  defp field_update_attrs(fd, params) do
    %{
      name: params["name"] |> blank_to(fd.name),
      required?: parse_bool(params["required"], fd.required?),
      config: parse_config(fd.field_type, params, fd.config)
    }
  end

  defp blank_to(nil, default), do: default
  defp blank_to("", default), do: default
  defp blank_to(v, _), do: String.trim(v)

  defp parse_bool(nil, default), do: default
  defp parse_bool("true", _), do: true
  defp parse_bool("on", _), do: true
  defp parse_bool("false", _), do: false
  defp parse_bool(_, default), do: default

  # Select options come from the config form's textarea (one per line).
  defp parse_config(:select, %{"options" => opts}, _prev) when is_binary(opts) do
    options =
      opts
      |> String.split(["\n", ","], trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    %{"options" => options}
  end

  defp parse_config(_ft, _params, prev), do: prev || %{}

  # Position the field between its new neighbours after a one-step move.
  # "up": it lands above the field currently at i-1, i.e. between i-2 and i-1.
  # "down": below the field at i+1, i.e. between i+1 and i+2. nil neighbour at
  # an edge → before_/after_. Returns nil (no-op) when already at the boundary.
  defp target_position(_fields, nil, _dir), do: nil

  defp target_position(fields, i, "up") when i > 0 do
    above = Enum.at(fields, i - 1)
    above_above = if i - 2 >= 0, do: Enum.at(fields, i - 2)

    if above_above,
      do: FractionalIndex.between(above_above.position, above.position),
      else: FractionalIndex.before_(above.position)
  end

  defp target_position(fields, i, "down") when i + 1 < length(fields) do
    below = Enum.at(fields, i + 1)
    below_below = if i + 2 < length(fields), do: Enum.at(fields, i + 2)

    if below_below,
      do: FractionalIndex.between(below.position, below_below.position),
      else: FractionalIndex.after_(below.position)
  end

  defp target_position(_fields, _i, _dir), do: nil

  defp type_options do
    Enum.map(FieldTypes.all(), fn mod ->
      icon = if function_exported?(mod, :icon, 0), do: mod.icon(), else: ""
      {to_string(mod.key()), "#{icon} #{mod.label()}"}
    end)
  end

  # ── render ───────────────────────────────────────────────────────────

  @impl true
  def render(%{live_action: :index} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="types-root" class="mx-auto max-w-3xl p-6">
        <div class="mb-6 flex items-center justify-between">
          <h1 class="text-2xl font-bold text-notion-text">Object types</h1>
          <.link
            navigate={~p"/w/#{@workspace.slug}"}
            class="text-sm text-notion-text-light hover:text-notion-text"
          >
            ← Workspace
          </.link>
        </div>

        <form phx-submit="create_type" id="new-type-form" class="mb-6 flex gap-2">
          <input
            type="text"
            name="name"
            value={@new_type_name}
            placeholder="New type name (e.g. Customer)…"
            autocomplete="off"
            class="flex-1 rounded-md border border-notion-divider px-3 py-1.5 text-sm focus:border-notion-text focus:outline-none"
          />
          <button
            type="submit"
            class="rounded-md bg-notion-text px-3 py-1.5 text-sm font-medium text-white transition hover:opacity-80"
          >
            Create
          </button>
        </form>

        <ul class="divide-y divide-notion-divider rounded-lg border border-notion-divider">
          <li
            :for={type <- @types}
            id={"type-#{type.id}"}
            class="flex items-center justify-between px-4 py-3"
          >
            <span class="inline-flex items-center gap-2">
              <span class="text-lg">{type.icon}</span>
              <span class="text-sm font-medium text-notion-text">{type.name}</span>
              <span :if={type.is_system?} class="rounded bg-notion-gray px-1.5 py-0.5 text-xs text-notion-text-light">
                system
              </span>
            </span>
            <.link
              navigate={~p"/w/#{@workspace.slug}/types/#{type.id}"}
              class="text-sm text-blue-600 hover:text-blue-800"
            >
              Edit →
            </.link>
          </li>
          <li :if={@types == []} class="px-4 py-6 text-center text-sm text-notion-text-light">
            No types yet. Create one above.
          </li>
        </ul>
      </div>
    </Layouts.app>
    """
  end

  def render(%{live_action: :edit} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="type-editor-root" class="mx-auto max-w-3xl p-6">
        <div class="mb-6 flex items-center justify-between">
          <span class="inline-flex items-center gap-2">
            <span class="text-2xl">{@type.icon}</span>
            <h1 class="text-2xl font-bold text-notion-text">{@type.name}</h1>
            <span :if={@type.is_system?} class="rounded bg-notion-gray px-1.5 py-0.5 text-xs text-notion-text-light">
              system
            </span>
          </span>
          <.link
            navigate={~p"/w/#{@workspace.slug}/types"}
            class="text-sm text-notion-text-light hover:text-notion-text"
          >
            ← All types
          </.link>
        </div>

        <%!-- rename --%>
        <form phx-submit="rename_type" id="rename-type-form" class="mb-6 flex gap-2">
          <input type="hidden" name="type_id" value={@type.id} />
          <input
            type="text"
            name="name"
            value={@type.name}
            class="flex-1 rounded-md border border-notion-divider px-3 py-1.5 text-sm"
          />
          <button type="submit" class="rounded-md border border-notion-divider px-3 py-1.5 text-sm">
            Rename
          </button>
        </form>

        <%!-- fields --%>
        <section class="mb-8">
          <h2 class="mb-3 text-sm font-semibold uppercase tracking-wide text-notion-text-light">
            Fields
          </h2>

          <div class="space-y-3">
            <div
              :for={fd <- @fields}
              id={"field-#{fd.id}"}
              class="rounded-md border border-notion-divider p-3"
            >
              <div class="flex items-center gap-2">
                <span class="text-sm">{field_icon(fd)}</span>
                <span class="flex-1 text-sm font-medium text-notion-text">{fd.name}</span>
                <span class="rounded bg-notion-gray px-1.5 py-0.5 text-xs text-notion-text-light">
                  {fd.field_type}
                </span>
                <span :if={fd.is_title?} class="rounded bg-blue-100 px-1.5 py-0.5 text-xs text-blue-800">
                  title
                </span>
                <button
                  type="button"
                  phx-click="reorder_field"
                  phx-value-id={fd.id}
                  phx-value-dir="up"
                  class="px-1 text-notion-text-light hover:text-notion-text"
                  aria-label="Move up"
                >
                  ↑
                </button>
                <button
                  type="button"
                  phx-click="reorder_field"
                  phx-value-id={fd.id}
                  phx-value-dir="down"
                  class="px-1 text-notion-text-light hover:text-notion-text"
                  aria-label="Move down"
                >
                  ↓
                </button>
              </div>

              <form phx-change="update_field" class="mt-2 space-y-2">
                <input type="hidden" name="field_id" value={fd.id} />
                <div class="flex items-center gap-2">
                  <input
                    type="text"
                    name="name"
                    value={fd.name}
                    class="flex-1 rounded border border-notion-divider px-2 py-1 text-sm"
                  />
                  <label class="flex items-center gap-1 text-xs text-notion-text-light">
                    <%!-- hidden fallback so unchecking submits "false" (an
                    unchecked checkbox sends no param) --%>
                    <input type="hidden" name="required" value="false" />
                    <input type="checkbox" name="required" value="true" checked={fd.required?} /> required
                  </label>
                </div>
                <div class="pl-6">
                  <ConceptWeb.Objects.FieldTypeComponent.config_form
                    field_def={fd}
                    form={to_form(%{})}
                  />
                </div>
              </form>
            </div>
          </div>

          <form phx-submit="add_field" id="add-field-form" class="mt-3 flex gap-2">
            <input
              type="text"
              name="name"
              value={@new_field_name}
              placeholder="New field name…"
              autocomplete="off"
              class="flex-1 rounded-md border border-notion-divider px-3 py-1.5 text-sm"
            />
            <select
              name="field_type"
              class="rounded-md border border-notion-divider px-2 py-1.5 text-sm"
            >
              <option :for={{val, label} <- type_options()} value={val} selected={val == @new_field_type}>
                {label}
              </option>
            </select>
            <button
              type="submit"
              class="rounded-md bg-notion-text px-3 py-1.5 text-sm font-medium text-white transition hover:opacity-80"
            >
              Add field
            </button>
          </form>
        </section>

        <.live_component
          module={ConceptWeb.Objects.WorkflowEditorComponent}
          id="workflow-editor"
          type={@type}
          workspace={@workspace}
          current_user={@current_user}
        />
      </div>
    </Layouts.app>
    """
  end

  defp field_icon(%{field_type: ft}) do
    case FieldTypes.lookup_safe(ft) do
      {:ok, mod} -> if function_exported?(mod, :icon, 0), do: mod.icon(), else: ""
      _ -> ""
    end
  end
end
