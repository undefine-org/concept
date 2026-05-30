defmodule Concept.Pages.BlockTypes.RecordRef do
  @moduledoc """
  The **seam** between the document layer (Blocks) and the entity layer
  (Records). A `record_ref` block holds only a `record_id` in its props and
  renders the referenced record's *live* title, workflow state (colored by
  category), and assignee.

  This is the projection that lets any page mention a task/record without
  copying it: the record lives once as a queryable entity; documents hold
  references. Editing the record anywhere updates every `record_ref` that
  points at it. See `docs/objects_and_tasks.md` §2.
  """
  use Concept.Pages.BlockType.Static

  @category_colors %{
    backlog: "bg-notion-gray text-notion-text-light",
    todo: "bg-blue-100 text-blue-800",
    doing: "bg-yellow-100 text-yellow-800",
    review: "bg-purple-100 text-purple-800",
    done: "bg-green-100 text-green-800",
    canceled: "bg-notion-gray text-notion-text-light line-through"
  }

  @impl Concept.Pages.BlockType
  def type, do: :record_ref

  @impl Concept.Pages.BlockType
  def default_props, do: %{"record_id" => nil}

  @impl Concept.Pages.BlockType
  def validate_props(%{"record_id" => nil}), do: :ok
  def validate_props(%{"record_id" => id}) when is_binary(id), do: :ok
  def validate_props(_), do: {:error, "record_id must be a uuid string or nil"}

  @impl Concept.Pages.BlockType
  def lexical_node, do: "record-ref"

  @impl Concept.Pages.BlockType
  def slash_menu,
    do: %{
      label: "Task / record",
      icon: "🔗",
      keywords: ~w(task record link reference ref),
      group: :media
    }

  def render(assigns) do
    record = load_record(assigns.block, assigns[:current_user])
    assigns = assign(assigns, :record, record)

    ~H"""
    <div class="my-1">
      <%= if @record do %>
        <span class="group inline-flex items-center gap-2 rounded-md border border-notion-divider px-2 py-1 text-sm">
          <span class={["rounded px-1.5 py-0.5 text-xs font-medium", state_class(@record)]}>
            {state_label(@record)}
          </span>
          <span class="font-medium text-notion-text">{title(@record)}</span>
          <button
            type="button"
            phx-click="open_record_picker"
            phx-value-block={@block.id}
            class="opacity-0 group-hover:opacity-100 text-xs text-notion-text-light hover:text-notion-text"
            title="Change linked record"
          >
            change
          </button>
        </span>
      <% else %>
        <button
          type="button"
          phx-click="open_record_picker"
          phx-value-block={@block.id}
          class="inline-flex items-center gap-1.5 rounded-md border border-dashed border-notion-divider px-2 py-1 text-sm text-notion-text-light italic hover:border-notion-text hover:text-notion-text"
        >
          🔗 Link a record…
        </button>
      <% end %>
    </div>
    """
  end

  # ── helpers ──────────────────────────────────────────────────────────

  # Load the referenced record scoped to the viewing actor when present (the
  # block renders inside an authenticated LiveView, which threads
  # `current_user`). Falls back to a tenant-pinned system read only when no
  # actor is available (e.g. server-side rendering without a user); the
  # tenant pin keeps it within the block's workspace either way.
  defp load_record(block, actor) do
    {actor, authorize?} =
      case actor do
        %{__struct__: _} = user -> {user, true}
        _ -> {%{system?: true}, false}
      end

    with id when is_binary(id) <- get_in(block.props, ["record_id"]),
         {:ok, record} <-
           Ash.get(Concept.Objects.Record, id,
             tenant: block.workspace_id,
             actor: actor,
             authorize?: authorize?,
             load: [:state]
           ) do
      record
    else
      _ -> nil
    end
  end

  defp title(%{title: t}) when is_binary(t) and t != "", do: t
  defp title(_), do: "Untitled"

  defp state_label(%{state: %{name: name}}) when is_binary(name), do: name
  defp state_label(_), do: "—"

  defp state_class(%{state: %{category: cat}}),
    do: Map.get(@category_colors, cat, "bg-notion-gray text-notion-text-light")

  defp state_class(_), do: "bg-notion-gray text-notion-text-light"
end
