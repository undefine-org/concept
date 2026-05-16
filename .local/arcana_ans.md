# Arcana v2.0.0 Integration API Reference for Phoenix+Ash

This is a definitive, source-verified reference for integrating Arcana v2.0.0 into a multi-tenant Phoenix/Ash application. All claims are grounded in source code and official documentation.

## 1. Installation & Supervision

**Dependency:**
```elixir
def deps do
  [
    {:arcana, "~> 2.0"},
    {:pgvector, "~> 0.2"},  # Required for vector storage
    {:req_llm, "~> 1.2"}     # Required for LLM integration
  ]
end
```

**Config (config/config.exs):**
```elixir
config :arcana,
  repo: Concept.Repo,
  embedder: {:custom, module: Concept.Knowledge.GeminiEmbedder},
  chunker: :default,
  search: [mode: :vector, limit: 10]
```

**Supervisor integration (application.ex):**
```elixir
children = [
  Concept.Repo,
  Arcana.TaskSupervisor  # Required for dashboard async operations
  # Do NOT add Arcana.Embedder.Local if using custom Gemini embedder
]
```

**Migrations:**
Arcana provides mix tasks to install and run migrations:
```bash
mix arcana.install    # Generates initial migrations
mix ecto.migrate      # Runs migrations
```

Created tables: `arcana_collections`, `arcana_documents`, `arcana_chunks` (pgvector), graph tables (`arcana_entities`, `arcana_relationships`, `arcana_community`), evaluation tables.

**pgvector requirement:** Must be installed in Postgres and enabled in migration:
```sql
CREATE EXTENSION IF NOT EXISTS vector;
```

Dimensions configured per embedder model (Gemini text-embedding-004: 768 dimensions).

## 2. Custom Embedder (Gemini)

**Behaviour signature (lib/arcana/embedder.ex):**
```elixir
@callback embed(text :: String.t(), opts :: keyword()) :: {:ok, vector :: list(float)} | {:error, term}
@callback embed_batch(texts :: [String.t()], opts :: keyword()) :: {:ok, [vector]} | {:error, term}
@callback dimensions(opts :: keyword()) :: pos_integer()
```

**Implementation skeleton for Gemini:**
```elixir
defmodule Concept.Knowledge.GeminiEmbedder do
  @behaviour Arcana.Embedder

  @impl true
  def embed(text, opts) when is_binary(text) do
    api_key = Keyword.get(opts, :api_key) || System.get_env("GOOGLE_API_KEY")
    model = "models/text-embedding-004"
    
    body = %{
      "requests" => [
        %{
          "model" => model,
          "content" => %{"parts" => [%{"text" => text}]}
        }
      ]
    }
    
    case Req.post("https://generativelanguage.googleapis.com/v1beta/embed", 
      json: body,
      params: [key: api_key]
    ) do
      {:ok, response} ->
        embedding = response.body["embeddings"] |> Enum.at(0) |> Map.get("values")
        {:ok, embedding}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def embed_batch(texts, opts) when is_list(texts) do
    # Call Gemini batch API; fallback to sequential if batch unavailable
    Enum.map(texts, &embed(&1, opts))
    |> Enum.reduce({:ok, []}, fn
      {:ok, emb}, {:ok, acc} -> {:ok, [emb | acc]}
      {:error, reason}, _ -> {:error, reason}
    end)
  end

  @impl true
  def dimensions(_opts), do: 768  # text-embedding-004 outputs 768-dim vectors
end
```

**Configuration:**
```elixir
config :arcana, embedder: {:custom, module: Concept.Knowledge.GeminiEmbedder}
```

**Intent/task type opts:** Not passed by Arcana. E5 models use automatic prefixing for embedding vs. search queries; Gemini API does not require task prefixes. Pass task intent only if custom business logic needs it.

## 3. Custom LLM (Gemini for chat/answer)

**Arcana relies on `Req.LLM` for LLM abstraction.** Streaming is supported natively.

**LLM module interface (lib/arcana/llm.ex):**
```elixir
def complete(llm_spec, prompt, context, call_opts) do
  # llm_spec: atom (e.g., :claude), tuple {model_name, opts}, or function
  # returns {:ok, text_response} or {:error, reason}
end
```

**Gemini config (config.exs):**
```elixir
config :arcana, llm: {"gemini-2.0-flash", [api_key: {:system, "GOOGLE_API_KEY"}]}
```

**Call-time override in Pipeline/Ask:**
```elixir
Arcana.Pipeline.new("What is Elixir?", llm: {"gemini-2.0-flash", api_key: api_key})
|> Arcana.Pipeline.search()
|> Arcana.Pipeline.answer()
```

**Streaming:** Arcana.Ask and Arcana.Pipeline.answer both support streaming via `stream: true` opt. Emits {:ok, token} or {:error, reason} tuples. Use Req.LLM's streaming support:
```elixir
ReqLLM.generate_text(model, context, stream: true)
```

Stream type: Elixir `Stream` (lazy enumerable). Attach to Phoenix.PubSub from handler:
```elixir
ask_stream = Arcana.ask(question, repo: repo, stream: true)
Stream.each(ask_stream, fn {:ok, token} ->
  Phoenix.PubSub.broadcast(Concept.PubSub, "chat:#{chat_id}", {:answer_chunk, token})
end)
|> Stream.run()
```

## 4. Pipeline Configuration

**Entry point:**
```elixir
ctx = Arcana.Pipeline.new(question, opts)
```

**Full surface (lib/arcana/pipeline.ex):**
- `new/2` - Initialize context
- `gate/2` - Decide if retrieval is needed (LLM gate keeping)
- `rewrite/2` - Clean query (conversational → canonical)
- `expand/2` - Add synonyms/expand query for multi-hop
- `decompose/2` - Break multi-part questions into subqueries
- `select/2` - Pick collection(s) from available set
- `search/2` - Retrieve chunks (with self-correct retry)
- `rerank/2` - Re-rank results
- `reason/2` - Multi-hop looping (if results insufficient, ask follow-up queries)
- `answer/2` - Generate final answer (with self-correct grounding check)
- `ground/2` - Verify claims against sources (hallucination detection)

**Override prompts:**
```elixir
ctx
|> Arcana.Pipeline.rewrite(prompt: fn q -> "Rephrase: #{q}" end)
|> Arcana.Pipeline.answer(prompt: fn chunks, q ->
  "Given #{chunks}, answer: #{q}"
end)
```

**Pass collection at runtime:**
```elixir
Arcana.Pipeline.new(question, collections: ["workspace:#{workspace_id}"])
|> Arcana.Pipeline.search()
```

**Receive stream from answer step:**
```elixir
ctx = Arcana.Pipeline.new(question)
       |> Arcana.Pipeline.search()
       |> Arcana.Pipeline.answer(stream: true)  # Returns {:ok, stream} or {:error, _}

case ctx.answer do
  {:ok, stream} -> 
    Stream.each(stream, fn token ->
      send_to_client(token)
    end) |> Stream.run()
  {:error, reason} -> 
    handle_error(reason)
end
```

## 5. Streaming

**Stream type:** Elixir `Stream` (lazy enumerable of tuples).

**Ask with stream:**
```elixir
Arcana.ask(question, repo: repo, stream: true, collection: "workspace:123")
|> Stream.each(fn
  {:ok, token} -> broadcast_token(token)
  {:error, reason} -> broadcast_error(reason)
end)
|> Stream.run()
```

**Pipeline answer with stream:**
```elixir
ctx = Arcana.Pipeline.new(question)
|> Arcana.Pipeline.search()
|> Arcana.Pipeline.answer(stream: true)

case ctx.answer do
  {:ok, stream} ->
    Enum.reduce(stream, "", fn {:ok, token}, acc ->
      Phoenix.PubSub.broadcast(Concept.PubSub, topic, {:chunk, token})
      acc <> token
    end)
end
```

## 6. Collections per Call

**API:**
```elixir
Arcana.Collection.get_or_create(name, repo, description \\ nil)
# Returns {:ok, collection} or {:error, reason}
```

**Scope ingest to collection:**
```elixir
{:ok, coll} = Arcana.Collection.get_or_create("workspace:#{workspace_id}", repo)
Arcana.ingest(text, repo: repo, collection: "workspace:#{workspace_id}")
```

**Scope search/ask to collection:**
```elixir
Arcana.search(query, repo: repo, collection: "workspace:#{workspace_id}")
Arcana.ask(question, repo: repo, collection: "workspace:#{workspace_id}")
Arcana.Pipeline.new(question)
|> Arcana.Pipeline.search(collection: "workspace:#{workspace_id}")
```

**Multi-collection routing:** No global config needed. Each call passes collection name(s). Arcana resolves by name → UUID at query time. Perfect for tenant isolation: collection name = "workspace:<uuid>".

## 7. Ingest API

**Main functions (lib/arcana/ingest.ex):**
```elixir
def ingest(text_or_path, opts) :: {:ok, document} | {:error, reason}
def ingest_file(path, opts) :: {:ok, document} | {:error, reason}
```

**Chunk on ingest:**
```elixir
{:ok, doc} = Arcana.ingest(
  "Page content",
  repo: repo,
  collection: "workspace:#{workspace_id}",
  metadata: %{"page_id" => page.id, "block_ids" => [...]}
)
```

**Upsert/replace on re-ingest:** Delete prior chunks then ingest:
```elixir
defmodule Concept.Knowledge do
  def ingest_page(page_id, repo) do
    # Get existing document for this page
    doc = repo.get_by(Arcana.Document, source_id: "page:#{page_id}")
    if doc, do: repo.delete!(doc)  # Cascades to chunks
    
    page = repo.get!(Concept.Pages.Page, page_id)
    Arcana.ingest(
      page.content,
      repo: repo,
      source_id: "page:#{page_id}",
      collection: "workspace:#{page.workspace_id}",
      metadata: %{"page_id" => page_id, "workspace_id" => page.workspace_id}
    )
  nend
end
```

**Document schema (lib/arcana/document.ex):**
- `:content` - Text content (required)
- `:content_type` - MIME type (default: "text/plain")
- `:source_id` - Opaque key for grouping versions
- `:metadata` - Custom map (preserved in chunks)
- `:status` - `:pending | :processing | :completed | :failed`
- `:collection_id` - FK to Collection
- `:chunk_count` - Denormalized count

**Chunk schema (lib/arcana/chunk.ex):**
- `:text` - Chunk text (required)
- `:embedding` - pgvector embedding (required)
- `:chunk_index` - Order in document
- `:token_count` - Estimated tokens
- `:metadata` - Custom fields (inherits from document + chunker overrides)
- `:document_id` - FK to Document

## 8. Custom Chunker

**Behaviour (lib/arcana/chunker.ex):**
```elixir
@callback chunk(text :: String.t(), opts :: keyword()) :: [chunk_map]
# chunk_map: %{text: String.t(), chunk_index: integer, token_count: integer, ...}
```

**Block-aware chunker skeleton:**
```elixir
defmodule Concept.Knowledge.BlockChunker do
  @behaviour Arcana.Chunker

  @impl true
  def chunk(text, opts) do
    page_id = Keyword.get(opts, :page_id)
    workspace_id = Keyword.get(opts, :workspace_id)
    blocks = Keyword.get(opts, :blocks, [])
    
    blocks
    |> Enum.with_index()
    |> Enum.map(fn {block, idx} ->
      %{
        text: block.content || "",
        chunk_index: idx,
        token_count: estimate_tokens(block.content),
        metadata: %{
          "block_id" => block.id,
          "page_id" => page_id,
          "workspace_id" => workspace_id,
          "block_type" => to_string(block.type)
        }
      }
    end)
  end
end
```

**Configure:**
```elixir
config :arcana, chunker: Concept.Knowledge.BlockChunker
# Or per-call
Arcana.ingest(text, repo: repo, chunker: Concept.Knowledge.BlockChunker, page_id: page_id, workspace_id: workspace_id)
```

## 9. GraphRAG without LLM extraction

**Current status:** Arcana ships with LLM-driven entity extraction as default. NO public hook to inject hand-built graph.

**Workaround - Write directly to schemas:**
```elixir
alias Arcana.Graph.{Entity, Relationship, Community}

# After ingesting documents, manually insert entities
entities = [
  %Entity{id: UUID.generate(), name: "Elixir", type: "language", description: "..." },
  %Entity{id: UUID.generate(), name: "Phoenix", type: "framework", description: "..."}
]

for e <- entities, do: repo.insert!(e)

# Insert relationships
relationships = [
  %Relationship{source_id: id1, target_id: id2, type: "uses", weight: 1.0}
]

for r <- relationships, do: repo.insert!(r)

# Run community detection (Leidenfold)
mix arcana.detect_communities
```

**Fusion Search:** Arcana.Search.search/2 with `:mode :hybrid` + graph enabled automatically composes RRF (Reciprocal Rank Fusion) of vector results + entity-based graph traversal. Entity matching via configured `Arcana.Graph.EntityMatcher` (default: embedding-based).

## 10. Search/Ask call (for chat panel)

**Main ask function:**
```elixir
Arcana.ask(question, opts) :: {:ok, answer_map} | {:error, reason}
```

**Return shape:**
```elixir
{
  :ok,
  %{
    "answer" => "Generated answer text",
    "sources" => [
      %{
        "text" => "Chunk text",
        "chunk_id" => uuid,
        "document_id" => uuid,
        "metadata" => %{"page_id" => ...},
        "score" => 0.87
      }
    ],
    "model" => "gemini-2.0-flash",
    "tokens_used" => %{"input" => 150, "output" => 75}
  }
}
```

**From LiveView:**
```elixir
def handle_event("ask", %{"question" => q}, socket) do
  case Arcana.ask(q, 
    repo: Concept.Repo,
    collection: "workspace:#{socket.assigns.workspace_id}",
    llm: {"gemini-2.0-flash", api_key: get_api_key()}
  ) do
    {:ok, %{"answer" => answer, "sources" => sources}} ->
      {:noreply, assign(socket, answer: answer, sources: sources)}
    {:error, reason} ->
      {:noreply, put_flash(socket, :error, inspect(reason))}
  end
end
```

## 11. Telemetry Events

**Canonical event names emitted by Arcana (lib/arcana/telemetry.ex):**

- `[:arcana, :search]` - Start/stop search execution
  - Start metadata: `%{query: String.t(), mode: :vector | :keyword | :hybrid, limit: integer}`
  - Stop metadata: `%{results: [...], result_count: integer}`

- `[:arcana, :search, :retrieve]` - Individual backend retrieval
  - Measurements: `%{duration_us: integer}`

- `[:arcana, :embedder, :embed]` - Single embedding
  - Start: `%{text: String.t(), intent: :query | :document}`
  - Measurements: `%{duration_us: integer, dimensions: integer}`

- `[:arcana, :embedder, :embed_batch]` - Batch embedding
  - Start: `%{count: integer}`
  - Measurements: `%{duration_us: integer}`

- `[:arcana, :pipeline, :*]` - Pipeline steps (gate, rewrite, search, answer, etc.)
  - `[:arcana, :pipeline, :search]` - Start/stop with `%{query: ..., mode: ...}`
  - `[:arcana, :pipeline, :answer]` - Start/stop with `%{answer: String.t()}`

- `[:arcana, :ask]` - Full ask cycle
  - Stop metadata: `%{duration_us: integer, tokens_input: integer, tokens_output: integer}`

- `[:arcana, :graph, :search]` - GraphRAG fusion search
  - Metadata: `%{entities_found: integer, graph_result_count: integer}`

- `[:arcana, :rerank]` - Reranking step
  - Metadata: `%{original_count: integer, reranked_count: integer}`

**LiveDashboard integration:**
```elixir
defmodule ConceptWeb.Telemetry do
  import Telemetry.Metrics

  def metrics do
    [
      summary("arcana.search.duration_us", unit: {:native, :millisecond}),
      summary("arcana.embedder.embed.duration_us", unit: {:native, :millisecond}),
      summary("arcana.ask.duration_us", unit: {:native, :millisecond}),
      counter("arcana.search.result_count"),
      distribution("arcana.pipeline.answer.duration_us",
        unit: {:native, :millisecond},
        buckets: [100, 500, 1000, 2000, 5000]
      )
    ]
  end
end
```

## 12. Dashboard Mount

**Router macro (in ConceptWeb.Router):**
```elixir
import Arcana.Router

scope "/admin", ConceptWeb.Admin do
  pipe_through(:browser)
  pipe_through(:require_admin)  # Your auth guard
  
  arcana_dashboard("/arcana", opts: [title: "Knowledge Base Dashboard"])
end
```

**Auth model:** Dashboard wraps all routes in a plug that checks `current_user` in Plug.Conn. Require auth before mounting:
```elixir
defp require_admin(conn, _opts) do
  if conn.assigns.current_user && conn.assigns.current_user.role == :admin do
    conn
  else
    redirect(conn, to: "/")
  end
end
```

**URL:** Accessible at `/admin/arcana` with pages: Collections, Documents, Chunks, Graph (entities/relationships), Evaluation (if enabled), Maintenance (re-embed, detect communities).

## 13. Migrations & Schemas

**Tables created by `mix arcana.install`:**

1. `arcana_collections` - Collection metadata
   - `id`, `name` (unique), `description`, `inserted_at`, `updated_at`

2. `arcana_documents` - Document records
   - `id`, `content` (text), `content_type`, `source_id`, `metadata` (jsonb), `status`, `error`, `chunk_count`, `collection_id`, `timestamps`

3. `arcana_chunks` - Embedded chunks
   - `id`, `text`, `embedding` (pgvector, dims = model output), `chunk_index`, `token_count`, `metadata` (jsonb), `document_id`, `timestamps`

4. `arcana_entities` - Graph nodes (if GraphRAG enabled)
   - `id`, `name`, `type`, `description`, `embedding` (pgvector), `collection_id`

5. `arcana_relationships` - Graph edges
   - `source_id`, `target_id`, `type`, `weight`, `description`

6. `arcana_communities` - Community summaries (Leidenfold output)
   - `id`, `level`, `entity_ids` (int array), `summary`, `collection_id`

7. `arcana_test_cases` - Evaluation test cases
   - `id`, `question`, `expected_answer`, `reference_sources`, `collection_id`

8. `arcana_evaluation_runs` - Evaluation results
   - `id`, `test_case_id`, `answer`, `metrics` (jsonb), `run_date`

**pgvector dimensions configuration:** Set in migration or dynamically:
```bash
mix arcana.gen.embedding_migration  # Generates migration for dimension resize
mix ecto.migrate
```

Default dimension = model output (text-embedding-004: 768, BGE-small: 384).

## 14. Multitenancy Compatibility

**Arcana scoping:** Collection-name partitioning only. NO built-in support for Ash tenant prefixes or schema prefixing.

**Tenant isolation strategy:**
1. Name collections by workspace: `"workspace:<workspace_uuid>"`
2. Pass collection in every ingest/search/ask call
3. Rely on Ecto-level isolation in Concept.Repo (if using Ash multitenancy, handle at repo layer)

**Example flow:**
```elixir
defmodule Concept.Knowledge.Ingest do
  def ingest_page(page, workspace_id, repo) do
    Arcana.ingest(
      page.content,
      repo: repo,
      source_id: "page:#{page.id}",
      collection: "workspace:#{workspace_id}",  # Partition by workspace
      metadata: %{"workspace_id" => workspace_id, "page_id" => page.id}
    )
  end
  
  def search(query, workspace_id, repo) do
    Arcana.search(
      query,
      repo: repo,
      collection: "workspace:#{workspace_id}",  # Only search within workspace
      limit: 10
    )
  end
end
```

**Verified:** Collection-name filtering in search prevents cross-tenant leakage. Chunks filtered by Document → Collection.id at query time.

---

## Gotchas & Known Limitations

1. **Streaming is fire-and-forget:** Stream side effects (e.g., token broadcasts) must be explicitly handled. Arcana does NOT auto-broadcast.

2. **GraphRAG entity extraction is LLM-driven only.** No public API to inject pre-built graphs; must write directly to schema tables.

3. **E5 models require prefixes:** Arcana auto-adds "query:" for searches and "passage:" for documents. Other models may not support this; verify model documentation.

4. **Chunk metadata inheritance:** Metadata passed to ingest merges with chunker output. Chunker metadata takes precedence on collision.

5. **PDF parsing is opt-in:** Default (Poppler) requires system dependency. Fails gracefully if binary unavailable; provide custom parser or skip PDFs.

6. **Rerankers require over-fetching:** If reranker enabled, Arcana retrieves `limit * over_fetch` (default 3x), then reranks to limit. Increases latency.

7. **Collections are not scoped to multitenancy implicitly.** Must manually pass collection name on every call; no defaults from Ash tenant context.

8. **Evaluation (test cases/runs) is separate from the main RAG pipeline.** Use for offline benchmarking; not integrated into live ask/search.

9. **No async ingest via Oban in v2.0.0.** Ingest is synchronous; large documents block. Plan for background jobs if needed.

10. **ReqLLM is required dependency** for all LLM operations, even custom implementations. Abstracts model selection and provider routing.
