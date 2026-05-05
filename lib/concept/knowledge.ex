defmodule Concept.Knowledge do
  @moduledoc """
  RAG/GraphRAG over Concept's pages & blocks. Wraps Arcana with
  workspace tenancy + Ash policies.
  """
  use Ash.Domain, otp_app: :concept, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
  end
end
