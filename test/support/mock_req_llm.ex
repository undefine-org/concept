defmodule Concept.TestSupport.MockReqLLM do
  @moduledoc """
  Minimal in-memory `ReqLLM`-shaped mock for chat respond tests.

  Implements `stream_text/3` returning a `%ReqLLM.StreamResponse{}` with:

    * a synchronous `Stream` of chunks built from `Process`-dict-configured
      reply text plus a terminal `:meta` chunk;
    * a working `MetadataHandle` whose `await/2` resolves to a usage map.

  No Finch, no HTTP. Set per-test with:

      MockReqLLM.set_reply(text: "Hello", input_tokens: 12, output_tokens: 7)

  Plug into `AshAi.ToolLoop.stream(messages, req_llm: ConfiguredModule, ...)`
  via the application env override:

      Application.put_env(:concept, :req_llm_module, MockReqLLM)

  …then route through `Concept.LLM.ReqLLMTap` (which is what production wires up).
  """

  alias ReqLLM.{Context, StreamChunk, StreamResponse}
  alias ReqLLM.StreamResponse.MetadataHandle

  @reply_key {__MODULE__, :reply}
  @call_count_key {__MODULE__, :call_count}
  @pid_key {__MODULE__, :last_call_pid}

  @doc """
  Configure the canned reply for subsequent `stream_text/3` calls in the
  current process.

  Options:
    * `:text` (default `"OK"`) — assistant reply text
    * `:input_tokens` (default `12`)
    * `:output_tokens` (default `7`)
    * `:grounding_confidences` (default `nil`) — when set, the terminal
      `:meta` chunk carries a `provider_meta.google.grounding_metadata`
      payload mirroring Google's `groundingSupports[].confidenceScores`
      array shape. Either a flat list of floats or a list of lists
      (one inner list per support segment).
  """
  @spec set_reply(keyword()) :: :ok
  def set_reply(opts \\ []) do
    Process.put(@reply_key, %{
      text: Keyword.get(opts, :text, "OK"),
      input_tokens: Keyword.get(opts, :input_tokens, 12),
      output_tokens: Keyword.get(opts, :output_tokens, 7),
      grounding_confidences: Keyword.get(opts, :grounding_confidences)
    })

    :ok
  end

  @doc "Pid that last invoked `stream_text/3` (nil if never called)."
  @spec stream_text_pid() :: pid() | nil
  def stream_text_pid, do: Process.get(@pid_key)

  @doc "How many times `stream_text/3` was called in this process."
  @spec call_count() :: non_neg_integer()
  def call_count, do: Process.get(@call_count_key, 0)

  @doc "Reset call counter and reply config for this process."
  @spec reset() :: :ok
  def reset do
    Process.delete(@reply_key)
    Process.delete(@call_count_key)
    Process.delete(@pid_key)
    :ok
  end

  @doc "ReqLLM.stream_text/3-compatible adapter."
  @spec stream_text(any(), any(), keyword()) :: {:ok, StreamResponse.t()}
  def stream_text(model, _messages, _opts) do
    Process.put(@call_count_key, call_count() + 1)
    Process.put(@pid_key, self())

    reply =
      Process.get(@reply_key, %{
        text: "OK",
        input_tokens: 12,
        output_tokens: 7,
        grounding_confidences: nil
      })

    chunks =
      reply.text
      |> String.graphemes()
      |> Enum.chunk_every(4)
      |> Enum.map(&Enum.join/1)
      |> Enum.map(&StreamChunk.text/1)
      |> Kernel.++([StreamChunk.meta(terminal_meta(reply))])

    {:ok, handle} =
      MetadataHandle.start_link(fn ->
        %{
          usage: %{
            input_tokens: reply.input_tokens,
            output_tokens: reply.output_tokens,
            total_tokens: reply.input_tokens + reply.output_tokens
          },
          finish_reason: :stop
        }
      end)

    {:ok,
     %StreamResponse{
       stream: Stream.map(chunks, & &1),
       metadata_handle: handle,
       cancel: fn -> :ok end,
       model: model,
       context: Context.new([])
     }}
  end

  defp terminal_meta(reply) do
    base = %{
      finish_reason: :stop,
      terminal?: true,
      usage: %{
        input_tokens: reply.input_tokens,
        output_tokens: reply.output_tokens,
        total_tokens: reply.input_tokens + reply.output_tokens
      }
    }

    case reply.grounding_confidences do
      nil -> base
      confidences -> Map.put(base, :provider_meta, google_provider_meta(confidences))
    end
  end

  # Mirror the shape produced by `ReqLLM.Providers.Google.extract_grounding_metadata/1`.
  defp google_provider_meta(confidences) do
    %{
      "google" => %{
        "grounding_metadata" => %{
          "groundingSupports" =>
            Enum.map(normalize(confidences), fn scores ->
              %{"confidenceScores" => scores}
            end)
        },
        "sources" => []
      }
    }
  end

  defp normalize([h | _] = list) when is_number(h), do: [list]
  defp normalize(list) when is_list(list), do: list
end
