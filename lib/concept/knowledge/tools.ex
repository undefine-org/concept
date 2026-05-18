defmodule Concept.Knowledge.Tools do
  @moduledoc """
  MCP-compatible tool wrappers for Knowledge domain functions.
  Exposes search and Q&A as Ash actions for external agents.
  """
  use Ash.Resource, domain: Concept.Knowledge

  actions do
    action :search_workspace, {:array, :map} do
      description "Hybrid vector+graph search over the workspace's pages and blocks."

      argument :query, :string,
        allow_nil?: false,
        description: "Natural-language query to retrieve relevant blocks for."

      argument :workspace_id, :uuid,
        allow_nil?: false,
        description: "Workspace to search within."

      argument :mode, :atom,
        default: :hybrid,
        allow_nil?: true,
        description: "Retrieval mode. One of :hybrid (default), :vector, :keyword."

      argument :limit, :integer,
        default: 10,
        allow_nil?: true,
        description: "Maximum number of results to return."

      run fn input, _context ->
        opts = [
          mode: input.arguments.mode,
          limit: input.arguments.limit
        ]

        case Concept.Knowledge.Search.search(
               input.arguments.query,
               input.arguments.workspace_id,
               opts
             ) do
          {:ok, results} -> {:ok, results}
          {:error, reason} -> {:error, reason}
        end
      end
    end

    action :answer_question, :map do
      description "Answer a question using workspace content with citations."

      argument :question, :string,
        allow_nil?: false,
        description: "Question to answer using workspace content as context."

      argument :workspace_id, :uuid,
        allow_nil?: false,
        description: "Workspace to draw context from."

      run fn input, _context ->
        case Concept.Knowledge.Ask.ask(
               input.arguments.question,
               input.arguments.workspace_id
             ) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:error, reason}
        end
      end
    end
  end
end
