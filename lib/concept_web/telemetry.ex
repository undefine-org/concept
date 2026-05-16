defmodule ConceptWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://hexdocs.pm/telemetry_metrics
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      sum("phoenix.socket_drain.count"),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # Database Metrics
      summary("concept.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "The sum of the other measurements"
      ),
      summary("concept.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "The time spent decoding the data received from the database"
      ),
      summary("concept.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "The time spent executing the query"
      ),
      summary("concept.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),
      summary("concept.repo.query.idle_time",
        unit: {:native, :millisecond},
        description:
          "The time the connection spent waiting before being checked out for the query"
      ),

      # Arcana / Knowledge Metrics
      summary("arcana.search.stop.duration", unit: {:native, :millisecond}),
      counter("arcana.search.stop.count"),
      summary("arcana.embedder.embed.stop.duration", unit: {:native, :millisecond}),
      counter("arcana.embedder.embed.stop.count"),
      summary("arcana.pipeline.answer.stop.duration", unit: {:native, :millisecond}),
      counter("arcana.pipeline.answer.stop.count"),
      summary("arcana.ingest.stop.duration", unit: {:native, :millisecond}),
      counter("arcana.ingest.stop.count"),
      summary("concept.knowledge.ask.stop.duration", unit: {:native, :millisecond}),
      counter("concept.knowledge.ask.stop.count"),
      summary("concept.knowledge.embedder.gemini.stop.duration", unit: {:native, :millisecond}),
      summary("concept.knowledge.search.stop.duration",
        unit: {:native, :millisecond},
        tags: [:workspace_id]
      ),
      last_value("concept.knowledge.ingestion_job.queue.depth"),
      counter("concept.knowledge.token_ledger.upsert.count"),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # This function must call :telemetry.execute/3 and a metric must be added above.
      # {ConceptWeb, :count_users, []}
      {Concept.Knowledge, :report_ingestion_queue_depth, []}
    ]
  end
end
