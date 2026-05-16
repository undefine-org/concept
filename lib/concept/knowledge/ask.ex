defmodule Concept.Knowledge.Ask do
  @moduledoc "Streaming Q&A via Arcana Pipeline with PubSub token broadcast."

  @deprecated "Use Concept.Knowledge.Chat (AshAI-generated) for streaming answers; this module remains only for backward compatibility until FEAT-039 lands."
  @doc """
  Starts an async streaming Q&A task.
  Returns immediately with {:ok, %{answer_id: uuid, topic: topic}}.
  Tokens are broadcast via Phoenix.PubSub as {:knowledge_token, answer_id, token}.
  Completion broadcast as {:knowledge_done, answer_id, payload}.
  Errors broadcast as {:knowledge_error, answer_id, reason}.
  """
  def ask(question, workspace_id, opts \\ []) do
    answer_id = Ash.UUID.generate()
    topic = "knowledge:answer:" <> answer_id

    Task.Supervisor.start_child(Concept.TaskSupervisor, fn ->
      run_pipeline(answer_id, topic, question, workspace_id, opts)
    end)

    {:ok, %{answer_id: answer_id, topic: topic}}
  end

  defp run_pipeline(answer_id, topic, question, workspace_id, opts) do
    name = Concept.Knowledge.Config.collection_for(workspace_id)

    :telemetry.span([:concept, :knowledge, :ask], %{answer_id: answer_id}, fn ->
      try do
        api_key = Concept.Knowledge.Config.api_key()
        llm_model = Concept.Knowledge.Config.llm_model()

        ctx =
          Arcana.Pipeline.new(question,
            repo: Concept.Repo,
            collections: [name]
          )
          |> maybe_filter_by_scope(opts)
          |> then(fn pipeline ->
            Arcana.Pipeline.rewrite(pipeline,
              prompt: &Concept.Knowledge.Prompts.rewrite_prompt/1
            )
          end)
          |> Arcana.Pipeline.search()
          |> Arcana.Pipeline.answer(
            stream: true,
            prompt: &Concept.Knowledge.Prompts.answer_prompt/2,
            llm: {llm_model, api_key: api_key}
          )

        if is_binary(ctx.answer) do
          sources =
            Map.get(ctx, :chunks, [])
            |> Enum.map(fn c ->
              meta = Map.get(c, :metadata) || Map.get(c, "metadata", %{})

              %{
                block_id: meta["block_id"],
                page_id: meta["page_id"],
                breadcrumbs: meta["breadcrumbs"],
                snippet: String.slice(Map.get(c, :text, "") || "", 0, 240),
                score: Map.get(c, :score) || 0.0
              }
            end)

          Phoenix.PubSub.broadcast(
            Concept.PubSub,
            topic,
            {:knowledge_done, answer_id, %{answer: ctx.answer, sources: sources, model: llm_model}}
          )

          {:ok, %{measurements: %{}}}
        else
          Phoenix.PubSub.broadcast(Concept.PubSub, topic, {:knowledge_error, answer_id, "Invalid answer format"})
          {{:error, "Invalid answer format"}, %{}}
        end
      rescue
        e ->
          Phoenix.PubSub.broadcast(
            Concept.PubSub,
            topic,
            {:knowledge_error, answer_id, Exception.message(e)}
          )

          reraise e, __STACKTRACE__
      end
    end)
  end

  defp maybe_filter_by_scope(pipeline, opts) do
    case Keyword.get(opts, :scope_filter) do
      %{page_ids: page_ids} when is_list(page_ids) ->
        Arcana.Pipeline.search(pipeline, filter: %{page_id: page_ids})

      _ ->
        pipeline
    end
  end
end
