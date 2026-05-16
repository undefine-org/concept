defmodule Concept.TestSupport.LLMStub do
  @moduledoc """
  Test-time HTTP stub for LLM calls (Gemini via ReqLLM via AshAI).

  Blessed Elixir pattern: ReqLLM forwards `req_http_options:` to `Req.new/1`,
  which honors `plug: {Req.Test, stub_name}`. Tests register canned responses
  with `Req.Test.stub/2`, dispatch the AshAI/ReqLLM action, and assert.

      iex> Concept.TestSupport.LLMStub.stub_text("Hello, world!")
      :ok
      iex> Concept.TestSupport.LLMStub.req_http_options()
      [plug: {Req.Test, Concept.TestSupport.LLMStub}]

  Place the returned options under `req_llm_opts:` in AshAi.ToolLoop calls,
  or pass directly to `ReqLLM.generate_text/3` as `req_http_options:`.

  ## Stubs available
  - `stub_text/2`        — plain (non-streaming) text reply
  - `stub_stream/2`      — streaming SSE chunks for a single text response
  - `stub_tool_call/2`   — assistant invokes a single tool, then returns text
  - `stub_embedding/1`   — embedding response (Gemini batchEmbedContents shape)
  - `stub_error/2`       — return an HTTP error status

  All stubs are scoped to the current test process via `Req.Test`.
  Multi-process scenarios (LiveView, Oban worker) should call
  `Req.Test.allow/3` to extend the stub to the worker pid.
  """

  @doc "Pass under `req_llm_opts:` or `req_http_options:` to route requests through Req.Test."
  @spec req_http_options() :: keyword()
  def req_http_options, do: [plug: {Req.Test, __MODULE__}]

  @doc "Same, wrapped for AshAi.ToolLoop convenience."
  @spec ash_ai_opts() :: keyword()
  def ash_ai_opts, do: [req_llm_opts: req_http_options()]

  # ── Non-streaming text reply ──────────────────────────────────────────
  @doc "Return a plain text completion (Gemini chat shape)."
  def stub_text(text, opts \\ []) do
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, gemini_chat_body(text, opts))
    end)
  end

  # ── Streaming text reply (SSE) ────────────────────────────────────────
  @doc """
  Return a streaming text completion as Gemini SSE chunks.

  `text` is split into ~4-char pieces and streamed as `text/event-stream`,
  ending with `data: [DONE]`.
  """
  def stub_stream(text, opts \\ []) do
    Req.Test.stub(__MODULE__, fn conn ->
      sse_body =
        text
        |> chunks_of(Keyword.get(opts, :chunk_size, 4))
        |> Enum.map(&gemini_stream_chunk/1)
        |> Enum.join()
        |> Kernel.<>(gemini_stream_done())

      conn
      |> Plug.Conn.put_resp_content_type("text/event-stream")
      |> Plug.Conn.send_resp(200, sse_body)
    end)
  end

  # ── Tool call ─────────────────────────────────────────────────────────
  @doc """
  First call returns an assistant tool_call; on the *next* call, returns text.

  Wires the round-trip needed by `AshAi.ToolLoop.run/2`: model asks for a
  tool, runtime invokes it, runtime calls model again with the tool result,
  model returns final text.
  """
  def stub_tool_call(tool_name, args, opts \\ []) do
    final_text = Keyword.get(opts, :final_text, "Tool executed.")
    {:ok, agent} = Agent.start_link(fn -> :first end)

    Req.Test.stub(__MODULE__, fn conn ->
      case Agent.get_and_update(agent, fn s -> {s, :second} end) do
        :first  -> Req.Test.json(conn, gemini_tool_call_body(tool_name, args))
        :second -> Req.Test.json(conn, gemini_chat_body(final_text, []))
      end
    end)
  end

  # ── Embedding response ────────────────────────────────────────────────
  @doc "Return a batch embedding response with deterministic vectors per input."
  def stub_embedding(vectors_by_text \\ %{}) when is_map(vectors_by_text) do
    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      %{"requests" => reqs} = Jason.decode!(body)

      embeds =
        for %{"content" => %{"parts" => [%{"text" => text}]}} <- reqs do
          %{"values" => Map.get(vectors_by_text, text, default_vector(text))}
        end

      Req.Test.json(conn, %{"embeddings" => embeds})
    end)
  end

  # ── Error response ────────────────────────────────────────────────────
  @doc "Return an HTTP error (e.g. 429 rate limit, 500 server)."
  def stub_error(status, body \\ %{"error" => %{"message" => "stubbed error"}}) do
    Req.Test.stub(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_status(status)
      |> Req.Test.json(body)
    end)
  end

  # ── Internals ─────────────────────────────────────────────────────────

  defp gemini_chat_body(text, _opts) do
    %{
      "candidates" => [
        %{
          "content" => %{"role" => "model", "parts" => [%{"text" => text}]},
          "finishReason" => "STOP",
          "index" => 0
        }
      ],
      "usageMetadata" => %{
        "promptTokenCount" => 12,
        "candidatesTokenCount" => max(1, div(String.length(text), 4)),
        "totalTokenCount" => 12 + max(1, div(String.length(text), 4))
      }
    }
  end

  defp gemini_tool_call_body(tool_name, args) do
    %{
      "candidates" => [
        %{
          "content" => %{
            "role" => "model",
            "parts" => [%{"functionCall" => %{"name" => tool_name, "args" => args}}]
          },
          "finishReason" => "STOP",
          "index" => 0
        }
      ],
      "usageMetadata" => %{
        "promptTokenCount" => 12,
        "candidatesTokenCount" => 4,
        "totalTokenCount" => 16
      }
    }
  end

  defp gemini_stream_chunk(text) do
    payload =
      Jason.encode!(%{
        "candidates" => [
          %{"content" => %{"role" => "model", "parts" => [%{"text" => text}]}, "index" => 0}
        ]
      })

    "data: " <> payload <> "\n\n"
  end

  defp gemini_stream_done, do: "data: [DONE]\n\n"

  defp chunks_of("", _), do: [""]

  defp chunks_of(string, size) do
    string
    |> String.graphemes()
    |> Enum.chunk_every(size)
    |> Enum.map(&Enum.join/1)
  end

  defp default_vector(text) do
    Concept.Knowledge.MockEmbedder.embed_batch([text], [])
    |> case do
      {:ok, [v]} -> v
      _ -> List.duplicate(0.0, 384)
    end
  end
end
