defmodule Concept.Knowledge.GeminiEmbedder do
  @moduledoc """
  Arcana-compatible embedder using Google's `gemini-embedding-001` API via Req.
  Returns 768-dimensional vectors (truncated via Matryoshka MRL from the 3072 native size).
  FUP-012 will migrate to `gemini-embedding-2` for multimodal (image/audio/video) coverage;
  same 768d output via outputDimensionality keeps pgvector indexes stable across the migration.
  """
  @behaviour Arcana.Embedder

  defmodule Error do
    defexception [:status, :body]
    @impl true
    def message(%{status: s, body: b}),
      do: "Gemini embed failed (status=#{s}): #{inspect(b)}"
  end

  @base_url "https://generativelanguage.googleapis.com/v1beta"
  @model "models/gemini-embedding-001"
  @max_batch 100

  @impl Arcana.Embedder
  def dimensions(_opts), do: 768

  @impl Arcana.Embedder
  def embed(text, opts) when is_binary(text) do
    with {:ok, [vec]} <- embed_batch([text], opts), do: {:ok, vec}
  end

  @impl Arcana.Embedder
  def embed_batch(texts, opts) do
    intent = Keyword.get(opts, :intent, :document)

    texts
    |> Enum.chunk_every(@max_batch)
    |> Enum.reduce_while({:ok, []}, fn chunk, {:ok, acc} ->
      case do_request(chunk, intent) do
        {:ok, vecs} -> {:cont, {:ok, acc ++ vecs}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp do_request(texts, intent) do
    :telemetry.span([:concept, :knowledge, :embedder, :gemini], %{count: length(texts)}, fn ->
      url = "#{@base_url}/#{@model}:batchEmbedContents?key=#{Concept.Knowledge.Config.api_key()}"
      body = %{requests: Enum.map(texts, &request_for(&1, intent))}

      case Req.post(url,
             json: body,
             retry: :transient,
             max_retries: 3,
             retry_delay: fn n -> trunc(:math.pow(2, n) * 200) end
           ) do
        {:ok, %{status: 200, body: %{"embeddings" => embeds}}} ->
          vecs = Enum.map(embeds, fn %{"values" => v} -> v end)
          {{:ok, vecs}, %{result: :ok}}

        {:ok, %{status: status, body: body}} ->
          {{:error, %__MODULE__.Error{status: status, body: body}}, %{result: :error}}

        {:error, exception} ->
          {{:error, exception}, %{result: :error}}
      end
    end)
  end

  defp request_for(text, intent) do
    %{
      model: @model,
      content: %{parts: [%{text: text}]},
      outputDimensionality: 768
    }
    |> maybe_put_task_type(intent)
  end

  defp maybe_put_task_type(req, :document), do: Map.put(req, :taskType, "RETRIEVAL_DOCUMENT")
  defp maybe_put_task_type(req, :query), do: Map.put(req, :taskType, "RETRIEVAL_QUERY")
  defp maybe_put_task_type(req, :similarity), do: Map.put(req, :taskType, "SEMANTIC_SIMILARITY")
  defp maybe_put_task_type(req, _), do: req

  @doc false
  def __send_for_test__(text, intent), do: request_for(text, intent)
end
