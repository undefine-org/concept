defmodule Concept.Knowledge.Workers.AggregateTokens do
  @moduledoc """
  Daily cron worker that flushes in-memory token accumulator ETS table
  into TokenLedger rows. Runs at 01:00 UTC, aggregating previous day's usage.
  """
  use Oban.Worker, queue: :knowledge_maintenance, max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    entries = Concept.Knowledge.TokenAccumulator.flush()

    Enum.each(entries, fn {{workspace_id, day_iso}, prompt, completion, embed, count} ->
      case Date.from_iso8601(day_iso) do
        {:ok, day} ->
          Concept.Knowledge.TokenLedger
          |> Ash.Changeset.for_create(:upsert, %{
            workspace_id: workspace_id,
            day: day,
            prompt_tokens: prompt,
            completion_tokens: completion,
            embed_tokens: embed,
            request_count: count
          })
          |> Ash.create!(actor: %Concept.Knowledge.SystemActor{}, tenant: workspace_id)

        {:error, reason} ->
          Logger.error("Invalid day_iso #{day_iso} in accumulator: #{inspect(reason)}")
      end
    end)

    # Clear ETS after successful flush
    Concept.Knowledge.TokenAccumulator.clear()
    Logger.info("TokenLedger aggregation complete: #{length(entries)} entries flushed")

    :ok
  end
end
