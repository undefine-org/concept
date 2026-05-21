defmodule Concept.Knowledge.Chat.Message.Changes.Respond do
  @moduledoc """
  Streams an LLM response for a user message and persists agent reply rows.

  Flow:

    1. Idempotency guard — if a response message already exists for this
       user message, either no-op (it's already `complete: true`) or
       finalize the partial (mark `complete: true` with an "interrupted"
       suffix). See `existing_response_decision/1`.
    2. Build prompt from prior conversation messages.
    3. Stream via `AshAi.ToolLoop` through the configured `req_llm` adapter
       (`Concept.LLM.ReqLLMTap` by default — captures usage that ash_ai
       discards).
    4. On each `{:content, chunk}` event, upsert the partial reply so the
       UI streams in real time.
    5. On `{:done, …}` (regardless of struct vs map shape), pull aggregated
       usage from the tap and persist the final reply with audit columns.

  ## Bug history

  * BUG-045 — guarded against `Access` calls on `%AshAi.ToolLoop.Result{}`.
  * BUG-046 — added `Concept.LLM.ReqLLMTap` since ash_ai 0.6.1's
    `Result` struct exposes neither usage nor `metadata_handle`.
  * FUP-028 — added idempotency guard against Oban retry double-streaming.
  """

  use Ash.Resource.Change
  require Ash.Query

  alias Concept.LLM.ReqLLMTap
  alias ReqLLM.Context

  @interrupted_suffix "\n\n[response interrupted]"

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_transaction(changeset, fn changeset ->
      message = changeset.data

      case existing_response_decision(message) do
        :stream ->
          do_stream(message, context)
          changeset

        {:finalize, response} ->
          finalize_partial!(response)
          changeset

        :noop ->
          changeset
      end
    end)
  end

  # ──────────────────────────────────────────────────────────────────────
  # Public helpers (kept public for unit testing)
  # ──────────────────────────────────────────────────────────────────────

  @doc """
  Extract per-call usage/grounding metadata from whatever shape the
  `{:done, _}` event carries.

  `AshAi.ToolLoop.stream/2` (>= 0.6.x) emits `{:done, %AshAi.ToolLoop.Result{}}`.
  The `Result` struct does **not** implement the `Access` behaviour, so
  treating it as a plain map and calling `get_in/2` raises
  `UndefinedFunctionError` (BUG-045).

  Older / alternative call paths may pass a plain map with `:usage` and
  `:grounding_metadata` keys; we still honor that.

  Always returns a plain map (never raises).
  """
  @spec extract_done_metadata(any()) :: %{
          optional(:prompt_tokens | :completion_tokens | :grounding_score) =>
            integer() | float() | nil
        }
  def extract_done_metadata(%_{} = _struct), do: %{}

  def extract_done_metadata(metadata) when is_map(metadata) do
    %{
      prompt_tokens: get_in(metadata, [:usage, :prompt_tokens]),
      completion_tokens: get_in(metadata, [:usage, :completion_tokens]),
      grounding_score: get_in(metadata, [:grounding_metadata, :grounding_score])
    }
  end

  def extract_done_metadata(_), do: %{}

  @doc """
  Idempotency decision for the `:respond` action.

    * `:stream` — no prior response exists; stream a new one.
    * `{:finalize, response}` — partial response exists (`complete: false`);
      finalize it with an interrupted suffix instead of re-streaming.
    * `:noop` — a completed response exists; do nothing.

  Public for unit testability.
  """
  @spec existing_response_decision(map()) :: :stream | :noop | {:finalize, map()}
  def existing_response_decision(%{id: message_id}) do
    response =
      Concept.Knowledge.Chat.Message
      |> Ash.Query.filter(response_to_id == ^message_id)
      |> Ash.Query.limit(1)
      |> Ash.read_one(authorize?: false)

    case response do
      {:ok, nil} -> :stream
      {:ok, %{complete: true}} -> :noop
      {:ok, %{complete: false} = partial} -> {:finalize, partial}
      {:error, _} -> :stream
    end
  end

  @doc """
  Append the interrupted suffix to an existing response unless it's
  already present. Idempotent: callable repeatedly without piling suffixes.
  """
  @spec interrupted_text(String.t() | nil) :: String.t()
  def interrupted_text(nil), do: String.trim(@interrupted_suffix)

  def interrupted_text(text) when is_binary(text) do
    if String.contains?(text, @interrupted_suffix), do: text, else: text <> @interrupted_suffix
  end

  # ──────────────────────────────────────────────────────────────────────
  # Streaming pipeline
  # ──────────────────────────────────────────────────────────────────────

  defp do_stream(message, context) do
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

    start_time = System.monotonic_time(:millisecond)

    # Register the usage tap for the duration of this stream. The tap stashes
    # every StreamResponse so we can pull usage after ash_ai's reducer is done.
    :ok = ReqLLMTap.register()

    try do
      final_state =
        prompt_messages
        |> AshAi.ToolLoop.stream(
          otp_app: :concept,
          tools: true,
          model: model,
          req_llm: ReqLLMTap,
          actor: context.actor,
          tenant: context.tenant,
          context: Map.new(Ash.Context.to_opts(context))
        )
        |> Enum.reduce(initial_state(), &reduce_event(&1, &2, message, new_message_id))

      latency_ms = System.monotonic_time(:millisecond) - start_time

      tap_usage = ReqLLMTap.aggregate(ReqLLMTap.collected_usage())

      tap_extras =
        case ReqLLMTap.collected_grounding_score() do
          nil -> %{}
          score -> %{grounding_score: score}
        end

      merged_metadata =
        final_state.metadata
        |> Map.merge(tap_usage)
        |> Map.merge(tap_extras)

      maybe_persist_final(
        final_state,
        message,
        new_message_id,
        merged_metadata,
        latency_ms
      )
    after
      ReqLLMTap.reset()
    end
  end

  defp initial_state do
    %{
      text: "",
      tool_calls: [],
      tool_results: [],
      stream_error: nil,
      metadata: %{}
    }
  end

  defp reduce_event({:content, content}, acc, message, new_message_id) do
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
  end

  defp reduce_event({:tool_call, tool_call}, acc, _message, _id) do
    %{acc | tool_calls: append_event(acc.tool_calls, tool_call)}
  end

  defp reduce_event({:tool_result, %{id: id, result: result}}, acc, _message, _id_arg) do
    %{acc | tool_results: append_event(acc.tool_results, normalize_tool_result(id, result))}
  end

  defp reduce_event({:error, reason}, acc, _message, _id) do
    %{acc | stream_error: reason}
  end

  defp reduce_event({:done, done_metadata}, acc, _message, _id) do
    %{acc | metadata: Map.merge(acc.metadata, extract_done_metadata(done_metadata))}
  end

  defp reduce_event(_, acc, _, _), do: acc

  defp maybe_persist_final(final_state, message, new_message_id, metadata, latency_ms) do
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
        %{
          id: new_message_id,
          response_to_id: message.id,
          conversation_id: message.conversation_id,
          complete: true,
          tool_calls: final_state.tool_calls,
          tool_results: final_state.tool_results,
          text: final_text
        },
        actor: %AshAi{}
      )
      |> force_audit_attributes(metadata, latency_ms)
      |> Ash.create!()
    end
  end

  # The audit columns (`prompt_tokens`, `completion_tokens`, `latency_ms`,
  # `grounding_score`, `search_trace`, `rewritten_prompt`) are `public?: false`,
  # so they cannot be passed through the action's input map.
  defp force_audit_attributes(changeset, metadata, latency_ms) do
    metadata
    |> build_audit_attrs(latency_ms)
    |> Enum.reduce(changeset, fn {k, v}, cs ->
      Ash.Changeset.force_change_attribute(cs, k, v)
    end)
  end

  defp finalize_partial!(%{} = partial) do
    Concept.Knowledge.Chat.Message
    |> Ash.Changeset.for_create(
      :upsert_response,
      %{
        id: partial.id,
        response_to_id: partial.response_to_id,
        conversation_id: partial.conversation_id,
        complete: true,
        text: interrupted_text(partial.text)
      },
      actor: %AshAi{}
    )
    |> Ash.create!()
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

  defp build_audit_attrs(metadata, latency_ms) do
    %{
      prompt_tokens: metadata[:prompt_tokens],
      completion_tokens: metadata[:completion_tokens],
      latency_ms: latency_ms,
      grounding_score: metadata[:grounding_score],
      # For now, search_trace is empty (TODO: integrate with retrieval)
      search_trace: [],
      # rewritten_prompt: captured during retrieval phase (not yet implemented)
      rewritten_prompt: nil
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
