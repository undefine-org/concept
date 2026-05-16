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
    # resource Concept.Knowledge.Citation do
    #   define :create_citation, action: :create
    #   define :citations_for_message, action: :for_message, args: [:message_id]
    #   define :citations_for_block, action: :for_block, args: [:block_id]
    # end

    resource Concept.Knowledge.Link do
      define :create_link, action: :create
      define :destroy_link, action: :destroy
    end
  end
end
