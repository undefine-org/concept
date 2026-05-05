defmodule Concept.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ConceptWeb.Telemetry,
      Concept.Repo,
      {DNSCluster, query: Application.get_env(:concept, :dns_cluster_query) || :ignore},
      {Oban,
       AshOban.config(
         Application.fetch_env!(:concept, :ash_domains),
         Application.fetch_env!(:concept, Oban)
       )},
      {Phoenix.PubSub, name: Concept.PubSub},
      ConceptWeb.Presence,
      # Start a worker by calling: Concept.Worker.start_link(arg)
      # {Concept.Worker, arg},
      # Start to serve requests, typically the last entry
      ConceptWeb.Endpoint,
      {AshAuthentication.Supervisor, [otp_app: :concept]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Concept.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ConceptWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
