defmodule Concept.Knowledge.TokenAccumulator do
  @moduledoc """
  In-memory ETS accumulator for knowledge pipeline token usage.
  Attaches telemetry handlers for search, embedding, and reactor events,
  aggregating by workspace_id + day. Flushed daily by AggregateTokens worker.
  """
  use GenServer
  require Logger

  @table :knowledge_token_accumulator

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set])

    :telemetry.attach_many(
      "knowledge-token-acc",
      [
        [:concept, :knowledge, :search, :stop],
        [:concept, :knowledge, :embedder, :gemini, :stop],
        [:concept, :knowledge, :reactor, :ingest, :step, :stop]
      ],
      &__MODULE__.handle_event/4,
      nil
    )

    Logger.info("TokenAccumulator started, telemetry handlers attached")
    {:ok, %{}}
  end

  @impl true
  def terminate(_reason, _state) do
    :telemetry.detach("knowledge-token-acc")
  end

  @doc """
  Telemetry event handler. Extracts workspace_id and token measurements,
  updates ETS counters.
  """
  def handle_event(_event, measurements, metadata, _config) do
    workspace_id = metadata[:workspace_id]

    if workspace_id do
      day = Date.utc_today() |> Date.to_iso8601()
      key = {workspace_id, day}

      prompt = measurements[:prompt_tokens] || 0
      completion = measurements[:completion_tokens] || 0
      embed = measurements[:embed_tokens] || 0

      # Update counters: {key, prompt, completion, embed, request_count}
      # Position: 2=prompt, 3=completion, 4=embed, 5=request_count
      :ets.update_counter(
        @table,
        key,
        [{2, prompt}, {3, completion}, {4, embed}, {5, 1}],
        {key, 0, 0, 0, 0}
      )
    end

    :ok
  end

  @doc """
  Returns all accumulated entries as a list: `[{{workspace_id, day_iso}, prompt, completion, embed, count}, ...]`
  """
  def flush do
    :ets.tab2list(@table)
  end

  @doc """
  Clears all ETS entries. Called after successful flush by AggregateTokens worker.
  """
  def clear do
    :ets.delete_all_objects(@table)
  end
end
