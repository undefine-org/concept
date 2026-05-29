defmodule Concept.Knowledge.Tools do
  @moduledoc """
  MCP-compatible tool wrappers for Knowledge domain functions.
  Exposes search and Q&A as Ash actions for external agents.
  """
  use Ash.Resource, domain: Concept.Knowledge

  @doc """
  Synchronous, grounded Q&A for the `answer_question` MCP tool.

  Retrieves workspace context via `Concept.Knowledge.Search`, then asks the
  LLM in a single shot with an inline-citation prompt. Returns the answer
  plus its sources in the response body — unlike the deprecated
  `Concept.Knowledge.Ask`, which returned an async handle and broadcast the
  answer on a PubSub topic no MCP caller subscribes to.
  """
  @spec answer_question(String.t(), binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def answer_question(question, workspace_id, llm_opts \\ []) do
    case Concept.Knowledge.Search.search(question, workspace_id, mode: :hybrid, limit: 10) do
      {:ok, hits} ->
        prompt = Concept.Knowledge.Prompts.answer_prompt(to_chunks(hits), question)
        model = Concept.Knowledge.Profiles.route_model(Concept.Knowledge.Config.llm_model())

        # llm_opts carries req_http_options for Req.Test routing in tests (LLMStub).
        case ReqLLM.generate_text(model, [ReqLLM.Context.user(prompt)], llm_opts) do
          {:ok, response} ->
            {:ok, %{answer: ReqLLM.Response.text(response), sources: hits}}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Adapt Search hits to the chunk shape Prompts.answer_prompt/2 expects.
  defp to_chunks(hits) do
    Enum.map(hits, fn h ->
      %{text: h.snippet, metadata: %{"block_id" => h.block_id}}
    end)
  end

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
        Concept.Knowledge.Tools.answer_question(
          input.arguments.question,
          input.arguments.workspace_id
        )
      end
    end
  end
end
