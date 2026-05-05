defmodule ConceptWeb.Presence do
  @moduledoc "Phoenix Presence tracker for workspace/page collaborative sessions."
  use Phoenix.Presence, otp_app: :concept, pubsub_server: Concept.PubSub
end
