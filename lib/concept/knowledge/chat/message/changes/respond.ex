defmodule Concept.Knowledge.Chat.Message.Changes.Respond do
  use Ash.Resource.Change
  require Ash.Query

  alias ReqLLM.Context

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_transaction(changeset, fn changeset ->
      message = changeset.data

      messages =
        Concept.Knowledge.Chat.Message
        |> Ash.Query.filter(conversation_id == ^message.conversation_id)
        |> Ash.Query.filter(id != ^message.id)
        |> Ash.Query.select([:text, :source, :tool_calls, :tool_results])
        |> Ash.Query.sort(inserted_at: :asc)
        |> Ash.read!(scope: context)
        |> Enum.concat([%{source: :user, text: message.text}])

      prompt_messages =
        [
          Context.system("""
          You are a helpful chat bot.
          Your job is to use the tools at your disposal to assist the user.
          """)
        ] ++ message_chain(messages)

      new_message_id = Ash.UUIDv7.generate()

      profile_name = message.profile || :default
      profile = Concept.Knowledge.Profiles.get!(profile_name)

      model =
        (profile.answer[:model] || "google:gemini-2.5-flash")
        |> Concept.Knowledge.Profiles.route_model()

      # Track start time for latency
      start_time = System.monotonic_time(:millisecond)

      # Capture metadata during streaming
      metadata = %{
        prompt_tokens: nil,
        completion_tokens: nil,
        grounding_score: nil
      }

      final_state =
        prompt_messages
        |> AshAi.ToolLoop.stream(
          otp_app: :concept,
          tools: true,
          model: model,
          actor: context.actor,
          tenant: context.tenant,
          context: Map.new(Ash.Context.to_opts(context))
        )
        |> Enum.reduce(
          %{text: "", tool_calls: [], tool_results: [], stream_error: nil, metadata: metadata},
          fn
            {:content, content}, acc ->
              if content not in [nil, ""] do
                Concept.Knowledge.Chat.Message
                |> Ash.Changeset.for_create(
                  :upsert_response,
                  %{
                    id: new_message_id,
                    response_to_id: message.id,
                    conversation_id: message.conversation_id,
                    text: content
                  },
                  actor: %AshAi{}
                )
                |> Ash.create!()
              end

              %{acc | text: acc.text <> (content || "")}

            {:tool_call, tool_call}, acc ->
              %{acc | tool_calls: append_event(acc.tool_calls, tool_call)}

            {:tool_result, %{id: id, result: result}}, acc ->
              %{
                acc
                | tool_results: append_event(acc.tool_results, normalize_tool_result(id, result))
              }

            {:error, reason}, acc ->
              %{acc | stream_error: reason}

            {:done, done_metadata}, acc ->
              # Capture token usage and grounding if available
              usage_metadata = extract_usage_metadata(done_metadata)
              %{acc | metadata: Map.merge(acc.metadata, usage_metadata)}

            _, acc ->
              acc
          end
        )

      # Calculate latency
      latency_ms = System.monotonic_time(:millisecond) - start_time

      stream_error_text = stream_error_text(final_state.stream_error)

      final_text =
        cond do
          stream_error_text && String.trim(final_state.text || "") != "" ->
            final_state.text <> "\n\n" <> stream_error_text

          stream_error_text ->
            stream_error_text

          String.trim(final_state.text || "") == "" &&
              (final_state.tool_calls != [] || final_state.tool_results != []) ->
            "Completed tool call."

          true ->
            final_state.text
        end

      if final_state.stream_error ||
           final_state.tool_calls != [] ||
           final_state.tool_results != [] ||
           final_text != "" do
        Concept.Knowledge.Chat.Message
        |> Ash.Changeset.for_create(
          :upsert_response,
          Map.merge(
            %{
              id: new_message_id,
              response_to_id: message.id,
              conversation_id: message.conversation_id,
              complete: true,
              tool_calls: final_state.tool_calls,
              tool_results: final_state.tool_results,
              text: final_text
            },
            build_audit_attrs(final_state.metadata, latency_ms)
          ),
          actor: %AshAi{}
        )
        |> Ash.create!()
      end

      changeset
    end)
  end

  defp message_chain(messages) do
    Enum.map(messages, fn
      %{source: :agent, text: text} ->
        # Historical tool call replay can break provider request validation for prior call IDs.
        # Keep replay text-only; current turn tool usage is handled by AshAi.ToolLoop.
        Context.assistant(text || "")

      %{source: :user, text: text} ->
        Context.user(text || "")
    end)
  end

  defp append_event(items, value) when is_list(items), do: items ++ [value]
  defp append_event(_items, value), do: [value]

  defp normalize_tool_result(tool_call_id, {:ok, content, _raw}) do
    %{
      tool_call_id: tool_call_id,
      content: content,
      is_error: false
    }
  end

  defp normalize_tool_result(tool_call_id, {:error, content}) do
    %{
      tool_call_id: tool_call_id,
      content: content,
      is_error: true
    }
  end

  defp stream_error_text(nil), do: nil

  defp stream_error_text(:max_iterations_reached) do
    "I hit a response limit while generating this reply. Please try again."
  end

  defp stream_error_text(_reason) do
    "I hit an error while generating this response. Please try again."
  end

  defp extract_usage_metadata(metadata) when is_map(metadata) do
    %{
      prompt_tokens: get_in(metadata, [:usage, :prompt_tokens]),
      completion_tokens: get_in(metadata, [:usage, :completion_tokens]),
      grounding_score: get_in(metadata, [:grounding_metadata, :grounding_score])
    }
  end

  defp extract_usage_metadata(_), do: %{}

  defp build_audit_attrs(metadata, latency_ms) do
    %{
      prompt_tokens: metadata.prompt_tokens,
      completion_tokens: metadata.completion_tokens,
      latency_ms: latency_ms,
      grounding_score: metadata.grounding_score,
      # For now, search_trace is empty (TODO: integrate with retrieval)
      search_trace: [],
      # rewritten_prompt: captured during retrieval phase (not yet implemented)
      rewritten_prompt: nil
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
