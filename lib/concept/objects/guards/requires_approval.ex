defmodule Concept.Objects.Guards.RequiresApproval do
  @moduledoc """
  Blocks a transition unless the acting actor is authorized to approve it.

  `config`:
    * `%{"by" => "creator"}` — only the record's `created_by` may approve
      (the default; the human-acceptance gate for agent-executed work).
    * `%{"by" => "anyone"}`  — any workspace member may approve.

  This is Symphony's "human accepts the proof of work", expressed as data on
  the `→ done` transition.
  """
  @behaviour Concept.Objects.Guard
  use Phoenix.Component

  @impl true
  def kind, do: :requires_approval

  @impl true
  def label, do: "Requires approval"

  @impl true
  def icon, do: "✓"

  @impl true
  def render_config_form(config, form) do
    assigns = %{form: form, by: Map.get(config, "by", "creator")}

    ~H"""
    <label class="text-xs text-notion-text-light">Approver</label>
    <select name={@form[:by].name} class="w-full rounded-md border border-notion-divider px-2 py-1 text-sm">
      <option value="creator" selected={@by == "creator"}>The creator</option>
      <option value="anyone" selected={@by == "anyone"}>Any member</option>
    </select>
    """
  end

  @impl true
  def check(record, config, ctx) do
    actor = ctx[:actor]
    by = Map.get(config, "by", "creator")

    cond do
      is_nil(actor) ->
        {:error, "approval required: no actor"}

      by == "anyone" ->
        :ok

      by == "creator" ->
        if actor_id(actor) == record.created_by_id,
          do: :ok,
          else: {:error, "only the creator may approve this transition"}

      true ->
        {:error, "unknown approval policy #{inspect(by)}"}
    end
  end

  @impl true
  def describe(config) do
    case Map.get(config, "by", "creator") do
      "anyone" -> "requires approval by any member"
      other -> "requires approval by the #{other}"
    end
  end

  defp actor_id(%{id: id}), do: id
  defp actor_id(_), do: nil
end
