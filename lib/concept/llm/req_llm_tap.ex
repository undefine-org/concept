defmodule Concept.LLM.ReqLLMTap do
  @moduledoc """
  A `req_llm`-shaped adapter that captures token-usage metadata which
  `AshAi.ToolLoop` (0.6.1) silently discards.

  `AshAi.ToolLoop.stream/2` consumes the underlying `ReqLLM.StreamResponse`'s
  chunk stream via `Enum.to_list/1` and forwards only `:content` chunks
  upward. `:meta` chunks — which carry `usage` (token counts) and
  `finish_reason` — are dropped, and the `metadata_handle` (the canonical way
  to retrieve final usage) is thrown away with the `StreamResponse`.

  This module is a thin proxy. It:

    1. Delegates `stream_text/3` to the configured backend
       (default `ReqLLM`; overridable in test via
       `Application.put_env(:concept, :req_llm_module, MockReqLLM)`).
    2. Stashes every returned `%ReqLLM.StreamResponse{}` in the **caller's**
       process dictionary so usage can be retrieved after the stream is
       fully consumed by `AshAi.ToolLoop`.

  Usage:

      iex> Concept.LLM.ReqLLMTap.register()
      iex> # ... pass `req_llm: Concept.LLM.ReqLLMTap` to AshAi.ToolLoop ...
      iex> Concept.LLM.ReqLLMTap.collected_usage()
      [%{input_tokens: 12, output_tokens: 7, total_tokens: 19}]
      iex> Concept.LLM.ReqLLMTap.reset()

  Stream consumption must complete before `collected_usage/0` is called —
  `ReqLLM.StreamResponse.usage/1` blocks on `MetadataHandle.await/2` until
  the underlying StreamServer has finalized.

  Process-scoped state means usage capture is naturally isolated per
  caller (and per Oban worker invocation).
  """

  @key {__MODULE__, :stream_responses}

  @typedoc "Token usage shape as returned by `ReqLLM.StreamResponse.usage/1`."
  @type usage :: %{optional(atom()) => non_neg_integer() | number()}

  @doc """
  Register the current process as the usage-collection target.

  Resets any previously stashed stream responses for this process. Idempotent.
  """
  @spec register() :: :ok
  def register do
    Process.put(@key, [])
    :ok
  end

  @doc """
  Drop any stashed stream responses without awaiting them.

  Safe to call in `after` blocks regardless of whether `register/0` was called.
  """
  @spec reset() :: :ok
  def reset do
    Process.delete(@key)
    :ok
  end

  @doc """
  Return the list of usage maps for every `stream_text/3` call that
  flowed through this tap in the current process, in invocation order.

  Returns `[]` if `register/0` was not called or no calls were made.

  Each entry is whatever the underlying provider's `usage` metadata
  resolves to (commonly `%{input_tokens: …, output_tokens: …, total_tokens: …}`).
  Failed/missing usage extractions are skipped silently.
  """
  @spec collected_usage() :: [usage()]
  def collected_usage do
    Process.get(@key, [])
    |> Enum.reverse()
    |> Enum.map(&safe_usage/1)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Sum a list of usage maps into a single aggregated map keyed by the
  fields `Concept.Knowledge.Chat.Message` cares about.

  Returns:
    * `:prompt_tokens` — sum of `:input_tokens` across calls (nil if all 0/missing).
    * `:completion_tokens` — sum of `:output_tokens` across calls (nil if all 0/missing).

  Keys are dropped (not set to nil) when no data was available, so the
  caller can `Map.merge/2` without overwriting existing values.
  """
  @spec aggregate([usage()]) :: %{optional(:prompt_tokens | :completion_tokens) => pos_integer()}
  def aggregate(usages) when is_list(usages) do
    %{}
    |> maybe_put_sum(:prompt_tokens, usages, :input_tokens)
    |> maybe_put_sum(:completion_tokens, usages, :output_tokens)
  end

  @doc """
  `ReqLLM.stream_text/3`-compatible adapter.

  Delegates to the configured backend module
  (`Application.get_env(:concept, :req_llm_module, ReqLLM)`) and, on success,
  stashes the returned `%ReqLLM.StreamResponse{}` for later
  `collected_usage/0`. Errors pass through unchanged.
  """
  @spec stream_text(any(), any(), keyword()) :: {:ok, struct()} | {:error, term()}
  def stream_text(model, messages, opts) do
    case delegate().stream_text(model, messages, opts) do
      {:ok, %ReqLLM.StreamResponse{} = sr} ->
        push_response(sr)
        {:ok, sr}

      {:ok, other} ->
        # Non-streaming or unexpected shape — pass through, can't tap.
        {:ok, other}

      {:error, _} = err ->
        err
    end
  end

  defp delegate, do: Application.get_env(:concept, :req_llm_module, ReqLLM)

  defp push_response(sr) do
    case Process.get(@key) do
      list when is_list(list) -> Process.put(@key, [sr | list])
      # Not registered — caller doesn't care about usage. No-op.
      nil -> :ok
    end
  end

  defp safe_usage(%ReqLLM.StreamResponse{} = sr) do
    ReqLLM.StreamResponse.usage(sr)
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  defp safe_usage(_), do: nil

  defp maybe_put_sum(acc, out_key, usages, source_key) do
    sum =
      usages
      |> Enum.map(&fetch_int(&1, source_key))
      |> Enum.sum()

    if sum > 0, do: Map.put(acc, out_key, sum), else: acc
  end

  defp fetch_int(map, key) when is_map(map) do
    case Map.get(map, key) do
      n when is_integer(n) and n >= 0 -> n
      _ -> 0
    end
  end

  defp fetch_int(_, _), do: 0
end
