defmodule ConceptWeb.Components.IndexingPill do
  @moduledoc """
  IndexingPill — live footer indicator for workspace ingestion state.

  Subscribes to `workspace:<id>:ingest` PubSub events in parent LiveView.
  Renders pill UI with 3 states:
  - `:idle` — no active jobs, shows last success time
  - `:indexing` — N jobs running
  - `:error` — last job failed

  Click → opens popover with last 10 IngestionJob rows.
  """
  use Phoenix.Component
  import ConceptWeb.CoreComponents, only: [icon: 1]

  attr :state, :atom, default: :idle, doc: ":idle | :indexing | :error"
  attr :count, :integer, default: 0
  attr :last_succeeded_at, :any, default: nil
  attr :jobs, :list, default: []
  attr :workspace, :map, required: true
  attr :current_user, :map, required: true
  attr :show_details, :boolean, default: false

  def indexing_pill(assigns) do
    ~H"""
    <div class="relative inline-block">
      <button
        type="button"
        phx-click="show_indexing_details"
        class={[
          "ora-pill",
          @state == :idle && "ora-pill-idle",
          @state == :indexing && "ora-pill-indexing",
          @state == :error && "ora-pill-error"
        ]}
      >
        <%= case @state do %>
          <% :idle -> %>
            <span>
              <%= if @last_succeeded_at do %>
                Indexed {time_ago(@last_succeeded_at)}
              <% else %>
                Idle
              <% end %>
            </span>
          <% :indexing -> %>
            <span>Indexing ({@count})</span>
          <% :error -> %>
            <span>Error</span>
        <% end %>
      </button>

      <div
        :if={@show_details}
        class="absolute bottom-full mb-2 right-0 w-96 bg-white border border-notion-divider rounded-lg shadow-lg p-4 z-50"
      >
        <div class="flex items-center justify-between mb-3">
          <h3 class="font-semibold text-sm text-notion-text">Indexing Jobs</h3>
          <button
            type="button"
            phx-click="hide_indexing_details"
            class="ora-btn ora-btn--ghost ora-btn--sm ora-btn--icon"
            aria-label="Close"
          >
            <.icon name="hero-x-mark-micro" class="size-4" />
          </button>
        </div>

        <%= if @jobs == [] do %>
          <p class="text-xs text-notion-text-light">No recent jobs</p>
        <% else %>
          <ul class="space-y-2">
            <%= for job <- @jobs do %>
              <li class={[
                "text-xs border-l-2 pl-2 py-1",
                job.state == :succeeded && "border-emerald-500",
                job.state == :running && "border-amber-500",
                job.state == :failed && "border-rose-500",
                job.state == :queued && "border-zinc-300"
              ]}>
                <div class="flex items-center justify-between">
                  <span class="font-medium">{format_state(job.state)}</span>
                  <span class="text-notion-text-light">
                    <%= if job.finished_at do %>
                      {time_ago(job.finished_at)}
                    <% else %>
                      {time_ago(job.started_at || job.scheduled_at || job.inserted_at)}
                    <% end %>
                  </span>
                </div>
                <%= if job.chunk_count do %>
                  <div class="text-notion-text-light">
                    {job.chunk_count} chunks, {job.embed_tokens || 0} tokens
                  </div>
                <% end %>
                <%= if job.error_message do %>
                  <div class="text-rose-600 truncate">{job.error_message}</div>
                <% end %>
              </li>
            <% end %>
          </ul>
        <% end %>
      </div>
    </div>
    """
  end

  defp time_ago(nil), do: "never"

  defp time_ago(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86400)}d ago"
    end
  end

  defp format_state(:queued), do: "Queued"
  defp format_state(:running), do: "Running"
  defp format_state(:succeeded), do: "Succeeded"
  defp format_state(:failed), do: "Failed"
  defp format_state(state), do: to_string(state)
end
