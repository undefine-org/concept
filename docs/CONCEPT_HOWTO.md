# Concept — The Full Tour

Concept is a **Notion-style editor** backed by an **Arcana awareness substrate**.
Every paragraph, heading, and to-do you write is automatically indexed into a
searchable knowledge graph. AshAI gives the workspace a conversational memory,
so you can ask questions and get cited, grounded answers.

Run the demo to see everything in one workspace:

```bash
mix concept.demo
```

Then sign in at the printed URL with `demo@concept.local`.

---

## The 8 Awareness Surfaces

| Surface | How to open | What it does |
|---|---|---|
| **Editor** | Click any page | Notion-style blocks: paragraphs, headings, to-dos, callouts, tables, AI answers. Type `/` for the slash menu. |
| **Command Palette** | `⌘K` (or `Ctrl+K`) | Semantic search across page titles and block content. Finds ideas even when wording differs. |
| **Chat Panel** | `⌘J` (or `Ctrl+J`) | Conversational interface to AshAI. Ask questions about your workspace; answers include inline citations. |
| **Slash Menu** | `/` in editor | Insert blocks. `✨ AI Answer` is the magic one — it embeds a RAG-powered answer inside the page. |
| **Knowledge Graph** | `/w/<slug>/graph` | Visual graph of blocks (nodes) and links (edges). Pan, zoom, and explore relationships. |
| **Ash Admin** | `/admin` | CRUD for all resources: Pages, Blocks, Citations, Links, TokenLedger, Conversations, Messages. |
| **MCP Endpoint** | `/mcp` | Model Context Protocol server. Mint an API key in `/admin/accounts/api-keys` to connect external tools. |
| **Ingestion Queue** | `/admin` → IngestionJob | Tracks embedding/indexing jobs. Fire-and-forget; no manual enqueue needed. |

---

## Editor Shortcuts

| Shortcut | Action |
|---|---|
| `/` | Open slash menu |
| `⌘K` / `Ctrl+K` | Command palette (semantic search) |
| `⌘J` / `Ctrl+J` | Toggle chat panel |
| `⌘Enter` | Toggle to-do checkbox |
| `Enter` | Split block / create new block |
| `Backspace` (at start) | Merge with previous block |

---

## Knowledge Spine

The awareness layer is built on four resources:

```
Page / Block
    │
    ▼
IngestionJob ──► vector + graph index
    │
    ▼
Chat Message ──► Citation ──► Block
    │
    ▼
Link (relates_to / cites / contradicts / see_also)
    │
    ▼
TokenLedger (daily usage)
```

1. **IngestionJob** — Every block creation/update auto-enqueues a job that
   embeds the page into Arcana's vector store and graph.
2. **Citation** — When AshAI answers a question, it records which blocks were
   retrieved and in what order. Citations power the "stale" indicator on AI
   answer blocks.
3. **Link** — User-authored edges between blocks. Each Link mirrors into
   `Arcana.Graph.Relationship` for graph visualization.
4. **TokenLedger** — Daily aggregates of prompt, completion, and embedding token
   usage per workspace.

---

## AI Answer Block — 4 States

Insert one with `/` → `✨ AI Answer`.

| State | Visual | Meaning |
|---|---|---|
| **Empty** | Placeholder prompt | No question asked yet. Type a prompt and hit the sparkle button. |
| **Streaming** | Animated dots + partial text | AshAI is generating a response. Citations are collected in real time. |
| **Answered** | Full text + citation chips | The answer is complete. A **stale** badge appears if any cited block has been edited since generation. |
| **Failed** | Error message | The pipeline errored (model unavailable, rate limit, etc.). Retry with the refresh button. |

---

## Minting an MCP Key

1. Go to `/admin/accounts/api-keys`.
2. Click **Create**.
3. Name it (e.g., `cursor-local`).
4. Copy the key — it is shown only once.
5. Use it with any MCP client pointing at `http://localhost:4000/mcp`.

---

## Quick Start Checklist

- [ ] Run `mix concept.demo`
- [ ] Open the printed URL and sign in
- [ ] Create a new page with `⌘K` → type a title → `Enter`
- [ ] Type `/ai` in the editor and insert an AI Answer block
- [ ] Ask a question in the chat panel (`⌘J`)
- [ ] Visit `/w/<slug>/graph` and pan around
- [ ] Open `/admin` and browse the Knowledge resources
- [ ] Mint an MCP key and connect your favourite editor

---

## Common Questions

**Q: Do I need a Gemini API key?**
A: Only for live AI answers and ingestion. The demo seeds a pre-baked
conversation so you can see citations and the chat UI without one.

**Q: Where is my data stored?**
A: Postgres for structured data (pages, blocks, messages). Arcana handles
vectors and the graph index.

**Q: Can I reset the demo?**
A: Run `mix concept.demo` again — it is idempotent. Existing pages are skipped;
new conversations and citations are additive.

**Q: How do I add custom block types?**
A: Implement `Concept.Pages.BlockType` behaviour and register the type in
`Concept.Pages.BlockTypes`. The editor will pick it up automatically.

---

## Next Steps

- Read the Ash admin at `/admin` to explore the full schema.
- Check `lib/concept/knowledge.ex` for the domain API.
- Look at `lib/concept/pages/block_types/ai_answer.ex` for how blocks declare
  their default props and validation.
- File a FUP (Follow-Up) in the org tracker for anything that feels missing.
