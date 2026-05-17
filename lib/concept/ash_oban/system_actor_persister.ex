defmodule Concept.AshOban.SystemActorPersister do
  @moduledoc """
  `AshOban.ActorPersister` that hydrates a `Concept.Knowledge.SystemActor`
  for every scheduler and worker invocation.

  Cron-scheduled scheduler jobs carry no actor in their Oban args. Resource
  policies almost always require either a workspace member or the system
  bypass (`actor_attribute_equals(:system?, true)`); without an actor the
  trigger read fails authorization. Wiring this persister on a trigger
  resolves both the read (`:read`) and the action (`:run`, `:release_lock`,
  …) under the system bypass.

  Reuse across domains — `IngestionJob.:process`,
  `Block.:release_expired_locks`, etc. all share the same actor contract.

  ## Usage

      oban do
        triggers do
          trigger :process do
            ...
            actor_persister Concept.AshOban.SystemActorPersister
          end
        end
      end
  """

  use AshOban.ActorPersister

  alias Concept.Knowledge.SystemActor

  @impl true
  def store(_actor), do: %{"type" => "system"}

  @impl true
  def lookup(_), do: {:ok, %SystemActor{}}
end
