# Concept Messaging — Design Brainstorm

> Replacing Notion **and Slack** with one substrate. This is a brainstorm, not
> a final spec. It proposes *the* Concept-ual messaging model: one where
> humans, external agents, and the internal workspace AI all converse as
> **Participants** acting through the same described Ash actions — so every
> message is at once a human UI event, an MCP tool call, a searchable
> knowledge chunk, and a seed for a durable Page.

---

## 0. The thesis

Concept's soul is **MCP parity by construction**: every described Ash action
is *both* a human feature (LiveView) and a machine feature (MCP tool), on the
same data, with the same policies (`docs/mcp_parity.md`).

A Slack-style bolt-on chat would betray that soul. The Concept-ual move is to
realize that **messaging is not a new feature — it is the parity principle
applied to conversation.** The moment "send a message" is an Ash action with a
`description`, every agent on the `/mcp` surface can participate in it. No
special-casing. Humans drive it from LiveView; agents drive it from MCP; both
hit the same action, same tenancy, same PubSub, same policies.

```
        ┌──────────────────────── send_message (Ash action) ────────────────────────┐
        │           one described action = the whole messaging capability            │
        └────────────────────────────────────────────────────────────────────────────┘
              │ projects to            │ projects to                │ feeds
              ▼                        ▼                            ▼
        LiveView (humans)        MCP tool (agents/LLMs)      Ingestion → embeddings
        type @researcher…        Claude calls send_message    message becomes citable
                                  with workspace-bound key     knowledge in the graph
```

Three pillars follow.

---

## 1. Today: a 1:1 reflex

Current model (`lib/concept/knowledge/chat/`):

| Resource | Shape | Limit |
|---|---|---|
| `Conversation` | belongs to **one** `user`; `my_conversations` filters `user_id == actor` | private to a single human |
| `Message` | `source: :user \| :agent`, `belongs_to conversation`, `response_to` self-ref | a **binary** sender; no human↔human, no agent↔agent |
| `:respond` (Oban trigger) | fires on `needs_response = source==:user and not exists(response)` | a 1:1 *reflex*: every user message auto-summons the one AI |

What's already right (and reusable):
- Messages are **workspace-tenanted** + PubSub-broadcast (real-time for free).
- Responses **stream** via `upsert_response` (append-only, event-ish).
- The AI is **grounded**: `Respond` retrieves workspace context, emits
  citations, records a `search_trace` ("Why this answer?").
- `Membership.role` already enumerates `:owner | :member | :agent`.
- The MCP path already lets an external actor act in a workspace via a
  **workspace-bound `ApiKey`** + membership check.

The binary `source` and the single-user `Conversation` are the only real
blockers. Everything else is a foundation.

---

## 2. Threading model — what shape should conversation take?

Researched the field; tradeoffs w.r.t. what Concept *is* (an async,
knowledge-first tool — not a real-time water-cooler):

| Model | Unit | Strength | Weakness | Fit for Concept |
|---|---|---|---|---|
| **Slack** | channel + message-attached threads | immediate, intuitive | threads get lost; scrollback amnesia; hard to find decisions later | ✗ optimizes for the thing Concept *isn't* (spontaneity) |
| **Zulip** | stream + **topic** (email-subject per message) | async, searchable, decision-tracking, clean retrieval boundaries | small learning curve | ✓ matches Concept's async/knowledge grain |
| **Matrix** | room + event log (federated) | event-sourced, durable | federation/complexity we don't need | partial — borrow the *events-are-durable* idea |
| **A2A** (Google) | **task** (stateful) + messages w/ parts + artifacts | bounded multi-agent work, lifecycle states | a protocol, not a UX | ✓ borrow: agent turns are *bounded tasks*, not infinite chatter |

**Decision: Zulip topic-model as the base, Concept-ualized.** A channel holds
focused **threads** (≈ topics), each with a subject. Each thread is a coherent
**retrieval unit** — which is exactly what the RAG layer wants (today's chat
retrieves per-message; per-thread is better grounding and maps to a graph
community).

Full **event-sourcing/CQRS is rejected** as the storage model: it fights the
Ash/Postgres "CRUD-with-named-actions" grain and adds eventual-consistency tax.
But we keep its *good parts for free* — messages are already append-only +
PubSub, and Ash's notifiers/Oban/ingestion already give us the read-model
fan-out (search index, citations, inbox projections) that CQRS would hand-roll.

---

## 3. The three pillars

### Pillar 1 — Participants, not sources

Replace the binary `source: :user | :agent` with a polymorphic **Sender**. A
message's sender is a **Participant** in the thread, which is one of:

- a **human** `User` (member, role `:member`/`:owner`)
- an **external agent** — also a `User` with membership role `:agent`,
  authenticating over `/mcp` with a workspace-bound `ApiKey`
  (the actor persister already tags it `chat_agent?: true`)
- the **internal Concept AI** — a built-in per-workspace participant (the
  grounded RAG assistant we have today)

Why this is Concept-ual: **agents are already members.** `role: :agent`
exists; the MCP plug already resolves an agent's workspace from its API key.
So "agents talking to each other" is not new infrastructure — it is the
existing membership + MCP surface, with conversation as the medium.

```elixir
# Message.sender — replaces `source`
belongs_to :sender_membership, Concept.Accounts.Membership  # human OR agent
attribute  :sender_kind, :atom, constraints: [one_of: [:human, :agent, :concept_ai]]
# concept_ai needs no membership row; it's the workspace's built-in participant
```

An agent persona reuses the existing `Knowledge.Profile`
(`fast | thorough | outline | contradict | intent`) — an agent member *is* a
profile with a name and an avatar. No new persona system.

### Pillar 2 — Conversation is knowledge

Every message flows through the **same ingestion pipeline as blocks**: chunked,
embedded, indexed (pgvector + tsvector). Consequences:

- The AI can **cite a message** in a future answer, exactly as it cites a
  block today (`Citation` already polymorphic over block/page; extend to
  message).
- A decision reached in a thread becomes a **first-class citizen of the
  knowledge graph** — Slack's "where was that decided?" amnesia is *cured by
  Concept's existing machinery*, not a new feature.
- A thread maps naturally to a **graph community** (`Knowledge.Community`),
  giving topic-level summaries for free.

This is the Notion↔Slack membrane dissolving from the *data* side: talk and
docs share one searchable fabric.

### Pillar 3 — Conversation crystallizes into structure

The membrane also dissolves from the *workflow* side:

- A **thread → Page**: "Crystallize into Page" turns a concluded discussion
  into a durable doc (a Reactor wrapping `create_page` + block synthesis from
  the thread, optionally AI-summarized). Neither Notion (docs written cold) nor
  Slack (talk dies in scrollback) does this; Concept's fusion makes *talk
  become document*.
- A **channel ↔ Page/Record binding**: a channel (or thread) can be *about* a
  Page or an `Objects.Record`. "Discuss this task" lives **with** the task
  (see mockup 2). The conversation about a thing is attached to the thing —
  contextual conversation, the superpower neither tool has.

```
Slack:   talk ───dies──▶ scrollback
Notion:  doc  ◀──cold─── author
Concept: talk ──crystallize──▶ Page ──grows──▶ talk   (a loop, not a dead-end)
```

---

## 4. The addressing & response model (the heart)

Today's reflex (`needs_response`) is generalized to **addressed response**.
A message can address zero, one, or many participants via `@mention`:

| Addressee | Effect |
|---|---|
| `@human` | notification → that member's **inbox** (async; no AI reflex) |
| `@concept_ai` / `@<agent>` | enqueue an **async response job** (Oban) scoped to that participant's persona + thread context + workspace RAG |
| *(no mention, human↔human)* | just a message — **no AI reflex** (fixes today's "every message summons the AI") |
| agent message that `@mentions` another agent | **agent↔agent** (A2A-style), **metered** by a per-thread agent-turn budget to prevent runaway loops |

Mechanically this is a small evolution of the existing trigger:

```elixir
# was: where expr(needs_response)               # source==:user and no response
# now: fan out one :respond job per addressed AI/agent participant that
#      has no reply yet, AND turn-budget for this thread is not exhausted
calculate :pending_agent_addressees, {:array, :uuid},
  expr(/* mentions ∩ agent-participants − already-responded */)
```

A2A's lesson — **agent turns are bounded tasks, not infinite chatter** — is
encoded as a `thread.agent_turn_budget` (configurable; default small). Each
agent-triggered turn decrements it; humans replenish it by participating.

---

## 4b. A2A validation — the model is already A2A-shaped

Google's A2A v1.0.0 (the emerging standard for agent interop) is built on a
tiny data model. Concept already has a near-isomorphic counterpart for each —
strong evidence the design is on the right axis, and a free future
interop surface (`/mcp` could grow an A2A binding without schema changes):

| A2A concept | A2A meaning | Concept counterpart |
|---|---|---|
| **AgentCard** | identity + declared capabilities of an agent | `Membership(role: :agent)` + the workspace's `/mcp` tool surface (its "skills" = described actions) |
| **Message** (role user/agent, parts) | one conversational turn | `Chat.Message` (sender_kind, text/tool parts) |
| **Task** (stateful, lifecycle) | the bounded unit of agent work | `Objects.Record` on a `Workflow` — *Concept already has a state-machine task engine* |
| **Context** (groups related tasks/messages) | session/conversation grouping | `Chat.Thread` (+ `Channel`) |
| **Artifact** (task output) | a produced document/data | a crystallized **Page** or a created **Block/Record** |
| **Streaming** (status/artifact updates) | real-time progress | `upsert_response` + PubSub (already live) |
| **Push notifications** (async, disconnected) | long-running, human-in-the-loop | `AshOban` triggers + the @mention **inbox** |

A2A's guiding principles read like Concept's own: *async-first*, *human-in-the-
loop native*, *opaque execution* (agents collaborate via declared capabilities,
not shared internals — exactly what MCP tools + policies give us). The lesson
we import is conceptual, not protocol: **an agent's turn is a bounded Task with
a lifecycle, not infinite chatter** — which is why §4's turn-budget and the
existing `Workflow` engine matter.

---

## 5. Resource model (proposed)

```
Accounts.Membership                      (extend: role :agent already exists)
  └─ is the identity of a human OR agent participant

Knowledge.Chat.Channel        (NEW, workspace-tenanted)
  ├─ name, slug, visibility :public | :private | :dm
  ├─ optional binding: about_page_id | about_record_id   (contextual convo)
  └─ has_many :threads

Knowledge.Chat.Thread         (EVOLVES from Conversation)
  ├─ belongs_to :channel
  ├─ subject (Zulip topic)
  ├─ agent_turn_budget :integer
  ├─ has_many :participants (through messages / explicit join)
  ├─ crystallized_page_id (nullable — the Page it became)
  └─ has_many :messages

Knowledge.Chat.Message        (EVOLVES — drop binary :source)
  ├─ belongs_to :thread
  ├─ belongs_to :sender_membership (nullable for concept_ai)
  ├─ sender_kind :human | :agent | :concept_ai
  ├─ text, tool_calls, tool_results, complete   (kept)
  ├─ mentions {:array, :uuid}                   (addressed participants)
  ├─ grounding: search_trace, citations         (kept; now also msg→msg)
  └─ → ingested like a Block (chunk/embed/index)

Knowledge.Chat.Participant    (optional explicit join: thread × membership)
  └─ unread cursor, notification prefs, last_read_message_id
```

Migration path (subsumes today's 1:1 chat, no parallel implementation):
- `Conversation` → `Thread` (+ a default per-user DM `Channel` with Concept AI)
- `Message.source: :user` → `sender_kind: :human` + `sender_membership`;
  `:agent` → `sender_kind: :concept_ai`
- The current single-AI chat **becomes** "a thread in your DM channel with
  Concept AI" — same UX, now a special case of the general model.

---

## 6. Parity surface (what becomes MCP tools automatically)

Every action below carries a `description` → auto-projected as an MCP tool by
`Concept.AutoTools`. This is the payoff: **the messaging model is the agent
API, for free.**

| Ash action | Human (LiveView) | Machine (MCP tool) |
|---|---|---|
| `Channel.create` | "+ New channel" | `chat_channel_create` |
| `Thread.create` | start a topic | `chat_thread_create` |
| `Message.send` | composer + `@` | `chat_message_send` |
| `Thread.crystallize` | "Crystallize into Page" | `chat_thread_crystallize` |
| `Message.for_thread` (read) | scrollback | `chat_message_for_thread` |
| `Channel.bind_to_record` | "Discuss this task" | `chat_channel_bind_to_record` |

An external Claude agent, holding a workspace-bound API key + `:agent`
membership, calls `chat_message_send` and **is a participant** — indistinguishable
at the data layer from a human typing in LiveView. That is the whole design in
one sentence.

---

## 7. Reuse ledger (build on existing affordances, no parallel impls)

| Need | Existing affordance |
|---|---|
| real-time delivery | `Ash.Notifier.PubSub` + `ConceptWeb.Endpoint` (already on Message) |
| streaming AI replies | `upsert_response` atomic-append pattern |
| async agent turns | `AshOban` trigger (today's `:respond`) |
| agent identity/auth | `Membership.role :agent` + workspace-bound `ApiKey` + `AiAgentActorPersister` |
| agent persona | `Knowledge.Profile` (fast/thorough/outline/…) |
| grounding + citations | `Knowledge.Search` + `Citation` + `search_trace` |
| presence / typing | `ConceptWeb.Presence` (used for page collab; ephemeral, off the log) |
| message → knowledge | the block ingestion pipeline (chunk/embed/index) |
| crystallize → doc | a Reactor over `Pages.create_page` (rule 3: cross-resource = Reactor) |
| policies/tenancy | `multitenancy :attribute` + `Ash.Policy.Authorizer` (channel membership = read/write gate) |

Net new resources: `Channel`, `Participant` (join), evolved `Thread`/`Message`.
Net new infra: ~zero — it's composition of what Concept already has.

---

## 8. Open questions / tradeoffs to settle

1. **Channels-as-Pages?** Notion's real philosophy is "everything is a block."
   A message *could* be a `message` block type and a thread a stream-layout
   Page. Elegant, but real-time + sender + budget semantics differ enough that
   a dedicated resource is cleaner. Proposed: **dedicated resource, block
   *kinship*** — messages ingest like blocks and crystallize *into* blocks,
   without forcing one schema. (Revisit if the block model generalizes.)
2. **Agent-turn budget defaults** — what's the right cap before a human must
   re-engage? Needs product judgment + abuse testing.
3. **DM vs channel for the AI** — keep a per-user private channel with Concept
   AI (preserves today's UX) vs. surface AI only inside shared channels.
   Proposed: both — DM is the migration target for today's `Conversation`.
4. **Edit/delete semantics** — append-only (edit = new version event) vs.
   in-place. Append-only keeps the audit trail RAG/compliance wants; costs UI
   work. Lean append-only, surface "edited".
5. **Notification model** — an "inbox" projection (LangChain "agent inbox"
   pattern) for @mentions to humans AND for agent results. Likely its own
   read-model LiveView.

---

## 9. One-paragraph summary

Concept doesn't get a chat feature; it gets a **conversation substrate**.
Replace the binary `source` with **Participants** (humans, agents-as-members,
the built-in Concept AI) so the same `send_message` action serves LiveView and
MCP alike — agents become participants *for free*. Adopt **Zulip-style
channels+threads** (async, searchable, decision-tracking) over Slack's lossy
threads. Run every message through the **existing ingestion pipeline** so
conversation is searchable, citable knowledge — curing Slack's amnesia with
Concept's own machinery. Generalize the AI reflex into **mention-addressed,
budget-bounded responses** (borrowing A2A's "agent turns are bounded tasks").
And let threads **crystallize into Pages** and **bind to Records**, dissolving
the Notion↔Slack membrane so talk becomes durable structure and structure grows
new talk. Net new infrastructure: ≈ zero — it is the MCP-parity principle,
applied to conversation.


---

# Part II — The Host model (the conceptual core)

> This supersedes Part I's "Participants, not sources" (§3 Pillar 1). The
> participant idea was right but under-powered. The **Host** is the keystone:
> it unifies *what a conversation is about*, *who speaks in it*, and *what the
> AI knows* into one primitive — and it falls straight out of Ash/Spark.

## 10. Three participant kinds, one of which is the subject itself

```
:user    a human speaks                         (Membership)
:agent   an external agent speaks via /mcp       (Membership role :agent)
:host    the SUBJECT of the conversation speaks  (Concept AI, grounded in the host)
```

The move that makes everything click: the **host is both the subject and a
participant.**

- As **subject**: every conversation *is about something* — a Page, a Record
  ("entity"), or the Workspace as a whole. That something is the host. One host
  → many conversations.
- As **participant**: the host *speaks*. The "internal Concept AI" is not a
  global singleton — it is **the host's voice**, grounded in the host's own
  subgraph. Talk to a Page and the Page answers, grounded in itself. Talk to
  the Workspace and you get exactly today's chat.

```
Today:    Conversation ── 1:1 ──▶ one User ; the AI is a global singleton
Concept:  Conversation ── about ─▶ Host (Page|Record|Workspace)
                         the Host's VOICE is a participant (grounded AI)
                         + Users + Agents as the other participants
```

The current workspace chat is revealed as a **degenerate case**: a conversation
hosted by the Workspace. Nothing special — just the host whose subgraph is
"everything."

## 11. "Atom or something else?" — a registry-backed tagged reference

Neither a bare atom (loses the id) nor a `belongs_to` (can't be polymorphic).
The Concept-ual answer is the pattern this codebase *already uses everywhere* —
the **registry** (cf. `block_types`, `AutoTools`):

```elixir
# On Conversation
attribute :host_type, :atom, constraints: [one_of: Concept.Hostable.registered()]
attribute :host_id,   :uuid                       # nil only for :workspace host
# {host_type, host_id} = a polymorphic, registry-validated reference
```

A host is **any resource that opts in** via a Spark extension — the same
ergonomics as `use Concept.Pages.BlockType.Interactive`:

```elixir
defmodule Concept.Pages.Page do
  use Ash.Resource, ...
  use Concept.Hostable,
    persona: "this document",
    scope:   :subtree          # how this host contributes RAG context
end

defmodule Concept.Objects.Record do
  use Concept.Hostable,
    persona: "this task",
    scope:   {:self, follow: [:linked_records]}
end
```

What `use Concept.Hostable` does at compile time (one stanza, like block types):
1. registers the module in the `Hostable` registry → feeds `host_type`'s `one_of`;
2. adds `has_many :conversations` (filtered to `host_type == __MODULE__`);
3. implements a `subgraph_scope/1` callback → the host's RAG contribution;
4. exposes a described `discuss` action → **auto-projected as an MCP tool by
   `AutoTools`**. So "start a conversation about X" is, for free, a thing both
   humans (LiveView) and agents (MCP) can do, for every Hostable resource.

> This is parity-by-construction applied to *being talked about*: declaring a
> resource `Hostable` makes it conversable by humans and agents alike, on the
> same data, with the same policies — zero per-resource wiring.

## 12. The host-participant's agency = the host's MCP surface

The deepest unification. A host resource already exposes described actions
(Record: `transition`, `assign`; Page: `rename`, block edits). Those *are* its
MCP tools. So the host-participant's **available tools = the host's own
described actions.**

```
Q: "what can the Task's AI voice do inside its conversation?"
A: exactly the Task's described actions — transition itself, assign itself, …
   (the agent in mockup 2 moving the task IS the host acting on itself)
```

No separate "agent tools" config. The thing you talk to can act on itself,
bounded by its own policies. Contextual conversation (Part I, Pillar 3) stops
being a feature and becomes a *consequence* of the host model.

## 13. Threads = child conversations (a conversation tree)

A thread is **a new conversation spawned from a message**, inheriting:
- the **host** of its parent (still about the same subject), and
- a **lineage** pointer (`parent_conversation_id` + the seed `message_id`).

```
Conversation(host: Page X)
  ├─ msg "should we ship offline mode?"
  │     └─▶ Thread = Conversation(host: Page X, parent: ↑, seed: msg)
  │              "competitor comparison"        (a focused child)
  └─ msg …
```

Threads are not a second mechanism (no `Channel` vs `Thread` split from Part I
needed) — a thread is just a conversation with a parent. Zulip's topic-grain
emerges from the tree, not from a separate entity. **One resource,
self-referential.** This is strictly simpler than Part I §5 and more powerful.

## 14. GraphRAG over the conversation lineage (the payoff)

This is why the host model is *Concept*-ual and not just tidy. A conversation's
retrieval context is naturally a **graph**, assembled by union:

```
RAG(conversation) =  subgraph(host)                     # what it's about
                  ∪  messages(this conversation)         # the live thread
                  ∪  ⋃ messages(ancestor threads)        # inherited context
                  ∪  subgraph(host) of any extra hosts    # future internal agents
```

- A **Page**-hosted convo retrieves the page's community (`Knowledge.Community`)
  — today's `scope: :subtree`, but now the *default*, derived from the host.
- A **Record**-hosted convo retrieves the record + its linked records.
- A **child thread** inherits the parent's accumulated context by walking
  `parent_conversation_id` — the lineage *is* a path in the graph.
- Messages themselves ingest like blocks (Part I, Pillar 2), so a thread's own
  turns become retrievable for its children. The conversation tree is a
  **knowledge subgraph overlaid on the host graph** — they are the same fabric.

The existing `Message.scope/:scope_target_id` enum (`:workspace|:page|:subtree`
+ uuid) is exactly a proto-host. The migration is: **lift it up** from Message
to Conversation as `host_type/host_id`, generalize the enum to the Hostable
registry. A natural generalization of a field that already exists — not a new
concept grafted on.

## 15. Notifications & async human contact, for free

"A conversation as the informal channel for an agent to reach a human, and the
simplest notion of a notification." The host model gives this with no new type:

- A **notification to a human** = a message addressed (`@`) to that user in some
  host's conversation. Their **inbox** = `conversations where I'm a participant
  with unread messages`, ordered by recency — one read action, parity-exposed.
- An **agent informing a human** = the agent posts in the relevant host's
  conversation and `@`s them. The human reads it *in context of the subject*
  (the Page/Record it's about), not as a context-free ping. Slack's
  notification-without-context problem dissolves because every message has a
  host.
- A **DM** = a conversation hosted by a User. (A user is Hostable too: persona
  "this person's workspace view", scope = their accessible subgraph.)

## 16. Future internal agents need no new primitive

"Internal agents = one or many hosts smashed together; for now, achievable by a
Page that references other pages."

This falls out exactly:
- An internal agent is a **participant whose scope is a union of hosts**
  (§14's last union term). Today, model it as a **Page-host** that links to the
  pages it should "know" — its `subgraph(host)` already transitively includes
  them via the link graph. So an aggregating Page *is* a proto-internal-agent.
- When internal agents become real, they are a `Hostable` participant with
  `scope: {:union, [host_refs]}` — one new `scope` shape, no new resource.

## 17. Revised resource model (simpler than Part I)

```
Concept.Hostable                (NEW Spark extension — the keystone)
  └─ `use`d by Page, Record, Workspace, User, … (opt-in, registry-backed)
     contributes: conversations rel, subgraph_scope/1, `discuss` MCP tool

Concept.Knowledge.Chat.Conversation   (EVOLVES from today's Conversation)
  ├─ host_type :atom (one_of: Hostable.registered)
  ├─ host_id   :uuid (nil ⇔ :workspace)
  ├─ parent_conversation_id  (self-ref → threads)
  ├─ seed_message_id         (the message a thread was spawned from)
  ├─ title (fast-model generated — today's generate_name — or set by creator)
  └─ has_many :participants, :messages

Concept.Knowledge.Chat.Participant    (NEW — polymorphic speaker)
  ├─ belongs_to :conversation
  ├─ kind :user | :agent | :host
  ├─ membership_id (for :user/:agent ; nil for :host — host is the convo's own)
  └─ last_read_message_id, notify prefs   (powers the inbox)

Concept.Knowledge.Chat.Message        (EVOLVES — drop binary :source)
  ├─ belongs_to :conversation
  ├─ belongs_to :sender, Participant
  ├─ mentions {:array, :uuid}   (addressed participants)
  ├─ text, tool_calls, tool_results, complete, grounding…  (kept)
  └─ ingested like a Block
```

Gone from Part I: the separate `Channel` resource (a "channel" is just the set
of conversations sharing a host — e.g. all conversations about the Workspace, or
about `#eng`-the-Page). `Thread` is not a resource — it's a parented
Conversation. **Three resources + one extension**, and the extension is where
all the leverage lives.

## 18. What the host model buys (vs Part I)

| Concern | Part I | Host model |
|---|---|---|
| what a convo is about | implicit / channel binding | **first-class `host`** |
| the AI participant | global Concept AI singleton | **the host's grounded voice** (per-subject) |
| contextual conversation | a feature (bind channel to record) | **a consequence** of host |
| threads | Zulip topics as a field | **child conversations** (self-ref tree) |
| channels | dedicated resource | **emergent** (conversations sharing a host) |
| RAG scope | enum on Message | **derived from host** + lineage union |
| agent tools | separate config | **the host's own described actions** |
| "talk about X" for new X | per-resource wiring | `use Concept.Hostable` (one stanza) |
| internal agents | undefined | **union-scope participant** (Page today) |

The host model is fewer moving parts *and* strictly more expressive — the sign
of finding the right primitive. It is the MCP-parity principle pushed to its
conclusion: not just "every action is a tool," but "**every resource worth
talking about declares itself conversable, and its conversation is grounded in
what it is.**"



---

# Part III — Further: the consequences nobody asked for (but the model demands)

> A primitive is *right* when it generates answers to questions you hadn't
> posed. The host model does. Five frontiers it opens — each free.

## 19. The membrane fully dissolves: a Conversation IS a Page

Part I treated crystallization as talk→doc (a Reactor). The host model exposes
something stronger: **a conversation and a page are the same shape already.**

```
Page          = ordered Blocks, each authored, fractionally indexed
Conversation  = ordered Messages, each authored by a Participant
```

A message is a block whose author is a Participant and whose position is time.
So don't crystallize by *copying* talk into a doc — **let the conversation be a
live projection of a Page** whose blocks happen to be sent, not typed. Then:

- "Crystallize" = **freeze ordering + promote** the message-blocks into the
  host page's tree. Talk literally *becomes* the document it was about — not a
  summary beside it. Bidirectional: a Page-hosted conversation can append its
  conclusions back **into its own host**. Talk grows the page; the page seeds
  new talk. (Part I's loop, now at the data layer, not the workflow layer.)
- One editor, one renderer, one ingestion path for both. The Notion↔Slack
  membrane isn't bridged — it's **gone**. There was only ever one substrate:
  *ordered authored blocks under a host.*

> Open tension (Part I §8.1 revisited): if a Message is literally a Block kind,
> the dedicated-resource argument weakens. Resolution: **Message is a Block
> subtype** (a `block_type` of `:message` with sender/mention/streaming props),
> Conversation is a **Page subtype** hosted by another resource. Messaging
> collapses into the block model rather than sitting beside it. This is the
> boldest version; it costs real work on the block schema but yields true
> one-substrate purity. Worth prototyping to feel the friction.

## 20. Conversations are themselves Hostable — and have workflow

If `Hostable` is a clean extension, **a Conversation can `use` it too.** Two
consequences:

- **Meta-conversation**: talk *about* a thread (a side-channel critique, an
  agent's private scratch-thread reasoning about the main one) — host = the
  conversation itself. Recursion the model already supports.
- **Decisions become first-class**: give Conversation a `Workflow`
  (`:open → :decided → :archived`) — *reusing the `Objects` state-machine
  engine you already have.* A "decided" conversation with a crystallized page is
  the cure for "where was this decided?" — now a **queryable state**, not a
  search. `list conversations where state == :decided and host == this_page`.

The A2A insight lands here precisely: **a conversation-with-a-workflow IS an
A2A Task** (stateful, lifecycle, produces an artifact = the crystallized page).
Concept's task engine and its conversation engine turn out to be the same
engine viewed from two sides.

## 21. @mention = a graph edge (addressing unifies with linking)

Mentioning a host in a message (`@page:roadmap`, `@task:offline-sync`) is not
just addressing — it is **authoring a `Knowledge.Link`** from this conversation
to that host. So:

- conversations weave themselves into the knowledge graph *as they happen*;
- the GraphRAG union (§14) gets richer with every mention — retrieval context
  grows from use, not from manual linking;
- "what discussions touch this Record?" = inbound links — already a graph query
  you can answer (`graph_query.ex`).

Addressing a *person* notifies; addressing a *host* links. Same `@`, dispatched
by the registry. The conversation graph and the knowledge graph are one graph.

## 22. Delegation falls out: an agent spawns a sub-conversation

Because `discuss` is an MCP tool on every Hostable (§11), an agent participant
can **start a child conversation hosted by a different resource** and `@` another
agent into it. That is exactly A2A task delegation — with no delegation
protocol:

```
agent A in convo(host: Task X)
  └─▶ discuss(host: Page "Migration Spec", @agent_B, "draft this")
        = a delegated sub-task, lineage-linked back to Task X,
          budget-metered (§4), grounded in the Page's subgraph
```

The turn-budget (§4) becomes the **delegation depth/fan-out limiter** — one
mechanism guards both runaway chatter and runaway delegation.

## 23. The host's persona is generative, not configured

§11 shows `persona: "this task"` as a static string. Push further: the host's
voice should be **generated from the host's own content + community summary**
(`Knowledge.Community` already summarizes subgraphs). A Page about Postgres
tuning *speaks as* an expert on it because its persona is its own distilled
subgraph — not a hand-written prompt. Every Hostable gets a competent voice for
free, and it stays current as the host's content changes (re-summarized on
ingestion). The thing you talk to is grounded in being *what it is* — the
tightest possible reading of "truly Concept-ual."

## 24. The one-sentence theory

> **Concept has exactly one substrate — authored blocks under a host — and
> exactly one principle — every host is conversable and every action is a tool.
> Pages, tasks, chats, threads, notifications, decisions, and agent delegation
> are not seven features; they are seven projections of that one substrate seen
> through the host.**

Notion is the substrate at rest. Slack is the substrate in motion. Concept is
the substrate — and the host is what tells you which projection you're looking
at.



---

# Part IV — The membrane, resolved (and the line we don't cross)

> Earlier (§19) I floated "Message *is* a Block subtype, Conversation *is* a
> Page subtype." That's the extremist reading. Pressure-tested below against
> the real schema, it **fails on the container layer and succeeds on the
> content layer.** The right balance: **a Conversation is its own concept; a
> Message may *contain* Blocks.** Here is exactly why.

## 25. The evidence: the AI Answer block is the host model in embryo

Before theory — a fact. `Block.Changes.EvaluateAi` (the `ai_answer` block)
already, by hand:

1. **owns a conversation** — `block.props["conversation_id"]`, created on first
   eval, reused after (`get_or_create_conversation/3`);
2. **scopes RAG to itself** — `scope: :subtree, scope_target_id: block.id`;
3. **renders the conversation's result back into the block** (`finalize_completion`).

That is *exactly* a Hostable: a resource (the block) hosting a conversation
grounded in its own subgraph, projecting the result back into itself. The host
model is not a new idea to bolt on — it is the **generalization of a pattern the
codebase already grew organically**, lifted from one hardcoded block type to a
first-class capability any resource opts into. Strongest possible signal the
primitive is right: the code reached for it before we named it.

## 26. Container layer: Conversation ≠ Page. Keep them distinct.

Why the extremist "Conversation is a Page subtype" fails against the schema:

| Axis | `Page` / `Block` | `Conversation` / `Message` | Verdict |
|---|---|---|---|
| ordering | `position` (fractional index, *re-orderable*) | time (`inserted_at`, *immutable*) | different invariant |
| mutation | blocks are **edited in place**, lock-managed (`AshStateMachine` lock FSM) | messages are **append-only**, never locked | opposite lifecycle |
| authorship | `lock_holder` (one editor at a time) | `sender` Participant (many, concurrent) | opposite concurrency |
| addressing | none | `mentions`, `sender_kind`, streaming `complete` | messages carry comms semantics blocks lack |
| host | a Page belongs to a workspace tree | a Conversation is *about* a host (Page/Record/…) | Conversation needs `host_*`; Page doesn't |

Forcing Message into the Block FSM means giving every chat message a lock
state, a re-order action, and a parent-block pointer it never uses — **carrying
weight to buy nothing.** Forcing Conversation into Page means a "page" whose
blocks can't be reordered and whose author model is inverted. The container
invariants are genuinely opposite (mutable/ordered/single-writer vs.
append-only/temporal/multi-writer). *Two concepts.* This is the line we don't
cross.

## 27. Content layer: a Message CONTAINS Blocks. This is where the membrane dissolves.

The dissolution belongs one level down. Today `Message.text :string` — a flat
string. Replace it with **block content**:

```elixir
# today
attribute :text, :string

# proposed: a message's body is blocks, exactly like a page's body
has_many :blocks, Concept.Pages.Block, destination_attribute: :message_id
# (Block gains a nullable message_id; a block belongs to EITHER a page OR a message)
```

Now everything the editor can express, a message can hold — **for free, no new
renderer, no new ingestion path**:

- an agent replies with a real `table` block, a `code` block, an `ai_answer`
  block, a `bookmark` — not markdown-in-a-string;
- a human composes a message with the same `/` slash menu as a page;
- **crystallization becomes trivial**: a message's blocks **reparent** onto the
  host page (`Block.reparent` already exists) — talk *becomes* document by
  moving block rows, not by re-authoring. The Part I Reactor shrinks to a
  reparent loop.
- ingestion already chunks **blocks**; message-blocks ingest through the exact
  same pipeline — conversation becomes searchable knowledge with zero new code.

So the balance, precisely:

```
CONTAINER  Conversation / Message   = its own concept   (comms invariants)
CONTENT    Message.blocks           = Blocks            (one substrate)
```

The membrane dissolves where content lives (blocks are universal) and holds
where lifecycle lives (comms ≠ docs). **Maximum impact** (full block richness in
messages, free crystallization, free ingestion) for **minimum work** (one
nullable FK on Block; no FSM surgery, no renderer fork, no parallel resource).

## 28. The one schema change that unlocks it

`Block.page_id` becomes "belongs to a **container** that is a page or a
message." Two honest options:

- **A — nullable `message_id` beside `page_id`** (a block has exactly one of
  them). Smallest diff; a `CHECK (num_nonnulls(page_id, message_id) = 1)`.
  Recommended for v1 — ship the capability, defer the abstraction.
- **B — polymorphic `container_type/container_id`** (the Hostable pattern again,
  one level down). Cleaner long-term, more migration. Adopt when a *third*
  block container appears (it will: a Record's rich-text field).

Start at A; B is a mechanical promotion when the third container arrives. Don't
pre-abstract — the registry pattern (§11) is the same shape, so the upgrade path
is known and cheap. (Rule: refactors are cutover, not parallel — A→B is a
single migration, not a fork.)

## 29. Net: what's a concept, what's a projection

```
Concept (own resource, own invariants):
  • Page          mutable ordered block tree
  • Conversation  append-only temporal message stream, ABOUT a host
  • Message       a turn by a Participant
  • Block         the universal content unit
  • Hostable      the extension that makes a resource conversable

Projection (no new resource):
  • Thread        = Conversation with a parent
  • Channel       = Conversation set sharing a host
  • Notification  = unread Message addressed to me
  • DM            = Conversation hosted by a User
  • Crystallize   = reparent Message.blocks onto host Page
  • AI Answer     = a Block hosting a Conversation (today's special case)
```

Five concepts, six projections. The extremist version had three concepts and
lost the comms invariants; the timid version had a flat-string chat bolted
beside the editor. **This is the balance: blocks unify the content; the host
unifies the subject; conversations keep their own lifecycle.**



---

# Part V — `Concept.Hostable`: the sketch

> Grounded in the two extension idioms already in the repo: the **Spark DSL
> extension + transformer** (`Concept.AutoTools`) and the **`__using__` mixin
> with `defoverridable`** (`BlockType.Interactive`). Hostable uses both — a
> mixin for the per-resource ergonomics, a transformer for the parity wiring.

## 30. What `use Concept.Hostable` must achieve

```elixir
defmodule Concept.Pages.Page do
  use Ash.Resource, ...
  use Concept.Hostable,
    persona: :generative,          # :generative | "static string"
    scope:   :subtree              # RAG contribution (see §32)
end
```

Four outcomes, each mapped to an existing mechanism:

| # | Outcome | Mechanism (already in repo) |
|---|---|---|
| 1 | register module → feed `Conversation.host_type` `one_of` | a registry, like `:block_types` config / `AutoTools` exclude lists |
| 2 | `has_many :conversations` on the host | relationship added in the mixin's `quote` |
| 3 | a described `discuss` action → MCP tool | the action carries `description:` → `AutoTools` synthesizes it (§6) — **nothing Hostable-specific needed** |
| 4 | `subgraph_scope/1` callback → RAG context | a behaviour callback, `defoverridable`, like `BlockType`'s callbacks |

Key realization: **outcome 3 is already free.** Because `discuss` is a normal
described Ash action, `Concept.AutoTools` turns it into an MCP tool with no new
machinery. Hostable doesn't reimplement parity — it *rides* it. That's the whole
elegance: the keystone leans on the keystone.

## 31. The shape (two parts, mirroring the repo's idioms)

```elixir
defmodule Concept.Hostable do
  @moduledoc "Spark extension: declares an Ash resource conversable."

  # ---- behaviour: the one thing each host must answer ----
  @callback subgraph_scope(record :: struct()) ::
              {:source_id, String.t()} | {:union, [term()]} | :workspace

  # ---- the registry (mirrors AutoTools' config-driven lists) ----
  # Populated at compile time by each `use Concept.Hostable`; readable for the
  # `one_of` constraint on Conversation.host_type. Persisted term, like the
  # block_types registry.
  def registered, do: Application.get_env(:concept, __MODULE__, [])[:hosts] || []

  defmacro __using__(opts) do
    persona = Keyword.get(opts, :persona, :generative)
    scope   = Keyword.get(opts, :scope, :workspace)

    quote bind_quoted: [persona: persona, scope: scope] do
      @behaviour Concept.Hostable
      @hostable_persona persona
      @hostable_scope   scope

      # outcome 2: the host owns its conversations (filtered to this type)
      # (added via a small DSL patch / relationship transformer; shown logically)
      #   has_many :conversations, Concept.Knowledge.Chat.Conversation,
      #     destination_attribute: :host_id,
      #     filter: expr(host_type == ^__MODULE__)

      # outcome 4: default RAG scope from the declared `scope:`; overridable
      @impl Concept.Hostable
      def subgraph_scope(record), do: Concept.Hostable.resolve_scope(@hostable_scope, record)
      defoverridable subgraph_scope: 1

      def __hostable__, do: %{persona: @hostable_persona, scope: @hostable_scope}
    end
  end

  # default scope resolver — turns the declared `scope:` into a Search filter
  def resolve_scope(:subtree, %{id: id}),    do: {:source_id, "page:" <> id}
  def resolve_scope({:self, _}, %{id: id}),  do: {:source_id, "record:" <> id}
  def resolve_scope(:workspace, _),          do: :workspace
  def resolve_scope({:union, refs}, _),      do: {:union, refs}
end
```

NB: outcomes 1–3 (registry entry, `has_many`, the `discuss` action) are
mechanical DSL additions best done by a **Spark transformer** bundled with the
extension (exactly the `AutoTools` pattern: `use Spark.Dsl.Extension,
transformers: [...]`). The mixin above shows the *callback* half; a
`Concept.Hostable.Transformers.InstallConversations` does the *DSL-patch* half
(add relationship + synthesize the `discuss` action with its `description`).
This split is faithful to how the codebase already separates ergonomics
(`BlockType.Interactive` mixin) from wiring (`AutoTools` transformer).

## 32. `scope:` is the RAG contract — and it's the existing one, lifted

`subgraph_scope/1` returns exactly what `Knowledge.Search` already accepts
(`source_id: "page:<id>"`, see `Respond.scope_opts/2`). So the GraphRAG union
(§14) is assembled from host scopes with **no change to the search layer**:

```
RAG(convo) = Search.union([
  host.subgraph_scope(host_record),          # §30 outcome 4
  {:messages, convo.id},                      # this conversation's blocks
  {:messages, ancestor_conversation_ids},     # walked via parent_conversation_id
])
```

The only new search capability is **union of scopes** (today it's single
`source_id`). That's a focused, well-bounded extension to `Search.search/3` —
the one genuinely new piece of retrieval code, and it's small.

## 33. Migration: today → host model, as a cutover (no parallel impl)

| Step | Change | Risk |
|---|---|---|
| 1 | `Conversation` gains `host_type/host_id` (+ `parent_conversation_id`, `seed_message_id`); backfill existing rows to `host_type: :workspace` | low — additive |
| 2 | `use Concept.Hostable` on `Workspace`, `Page`, `Objects.Record` | low — opt-in |
| 3 | `Message`: add `Participant` sender; migrate `source: :user` → participant(kind: :user), `:agent` → participant(kind: :host) | medium — data migration |
| 4 | `Block` gains nullable `message_id` (§28 option A); `Message.text` kept as a fast-path, `Message.blocks` added | medium — schema + CHECK |
| 5 | retire `ai_answer`'s hand-rolled conversation plumbing → it becomes `Block` + `use Concept.Hostable` | low — deletes code (§25) |
| 6 | `discuss` replaces `evaluate_ai`'s bespoke `get_or_create_conversation` | low — consolidation |

Steps 5–6 are the proof of the design: adopting Hostable **removes** the
hand-written conversation code in `EvaluateAi` rather than adding beside it. The
refactor is a net deletion at the call sites — the surest sign the primitive was
latent in the code all along.

## 34. Smallest shippable slice (what to prototype first)

To feel the friction before committing the full migration:

1. `Concept.Hostable` extension (mixin + transformer) — registry + `discuss`.
2. `use` it on **`Page` only**.
3. `Conversation.host_type/host_id` + the `discuss` action.
4. Point the existing chat panel at a Page-hosted conversation; confirm RAG
   scopes to the page via the *existing* `source_id` path.
5. Defer: Participant table (keep binary source as a shim), Message.blocks,
   threads. Add once the host spine feels right.

This slice touches ~3 files + 1 migration, reuses the entire retrieval/PubSub/
Oban stack, and validates the keystone against reality. If `use Concept.Hostable`
on Page feels as clean as `use BlockType.Interactive` does today, the vision
holds — and the rest is mechanical generalization.

## 35. The refined vision, one breath

> A **Conversation** is its own concept — an append-only, temporal stream
> *about* a **Host**. A **Message** is a turn whose body is **Blocks**, so talk
> carries the editor's full expressiveness and *crystallizes* into a Page by
> moving block rows. A resource becomes conversable by declaring
> `use Concept.Hostable`, which — riding the same parity machinery as everything
> else — gives it a grounded voice, an MCP `discuss` tool, and a RAG scope that
> is simply *what it is*. Threads, channels, notifications, DMs, and delegation
> are projections of this, not features beside it. The AI Answer block was the
> first Hostable, written by hand; the design just gives the pattern its name.



---

# Part VI — Participant, pressure-tested (identity vs. voice)

> Earlier parts said "`:host` is a participant with `membership_id` nil." Tested
> against the real authz machinery, that phrasing is **wrong** and hides the
> actual question. The fix sharpens the whole model: **a Participant is an
> identity (a Membership); the host is not an identity — it is a *voice*.**

## 36. The two facts that constrain everything

1. `Message` and `Conversation` have **no authorizer** today — no policies, all
   calls pass `authorize?: false` (see `EvaluateAi`, `Respond`). So nothing in
   the host model *breaks* existing authz; but the model is the right moment to
   add real policies, and they must be coherent.
2. `WorkspaceMember` is a `FilterCheck`:
   `exists(workspace_memberships, user_id == ^actor(:id))`. It **structurally
   requires the actor to be a principal with a membership row.** A synthetic
   "host actor" with a random id would fail every member-gated read.
3. Today the AI turn (`upsert_response`, `source: :agent`) runs under the
   **asking user's** identity (`AiAgentActorPersister` resolves the User, tags
   `chat_agent?: true`) — *displayed* as agent, *authorized* as the human.

Fact 3 is the latent answer: **display identity ≠ authorization actor.** The
codebase already separates them. The host model just names that separation.

## 37. Identity vs. voice — the distinction that resolves `:host`

```
IDENTITY (authz actor)   who the turn runs AS — a principal, has policies
VOICE    (display + RAG) who the turn appears FROM + what grounds it
```

| participant kind | identity (authz actor) | voice (display / grounding) |
|---|---|---|
| `:user`  | the User (Membership role :owner/:member) | the human |
| `:agent` | the agent User (Membership role :agent, MCP+ApiKey) | the external agent |
| `:host`  | **borrowed from the addresser** (leak-safe) | the host resource (persona + subgraph) |

The host has a **voice but no identity of its own.** When the Page speaks, the
turn authorizes as *the participant who @addressed it*; only the persona, the
RAG scope, and the available tools come from the host. This is precisely what
`upsert_response` does today — generalized from "the one asker" to "the
addressing participant."

## 38. Why borrowed identity is the *correct* choice, not a shortcut

The tempting alternative — give the AI its own member identity — has a real
security hole the moment per-page ACLs exist (they will):

```
leak scenario (AI-as-own-identity):
  low-priv user asks Page "summarize the board deck"
  → host grounds RAG under the AI's identity (sees everything)
  → answer exfiltrates content the user can't read
```

Borrowed identity closes it by construction: **grounding scope = host.subgraph
∩ addresser's visibility.** Today the workspace ACL is binary (member sees all),
so the intersection is moot — but the principle must not be foreclosed. The host
speaks *within the asker's reach*, never beyond it. Least privilege falls out:
the host can do exactly what the human who invoked it could do, no more.

Same rule governs the host **acting on itself** (§12): a viewer who asks a Task
to transition itself gets refused — because the turn authorizes as the viewer,
and the viewer lacks `transition`. The host is a deputy, never a god. The audit
trail (paper-trail) records the human as actor; the message shows sender_kind
`:host` with a tool chip. Honest on both axes: human *authorized*, host
*executed*.

## 39. Corrected resource model: Participant = Membership × Conversation

The `:host` is **not a Participant row.** Participants are the join of
*memberships* into a conversation — they exist to carry per-principal
conversation state (unread cursor, notify prefs), i.e. the **inbox**. The host
needs none of that (it is reactive, never has unread). So:

```
Concept.Knowledge.Chat.Participant         (memberships only)
  ├─ belongs_to :conversation
  ├─ belongs_to :membership        ← THE identity (user or agent)
  ├─ last_read_message_id          ← powers the inbox
  └─ notify prefs
  — kind is DERIVED from membership.role, not stored (one source of truth)

Concept.Knowledge.Chat.Message
  ├─ belongs_to :sender_participant   (NULLABLE)
  │    • set  ⇒ a user/agent spoke; sender_kind from membership.role
  │    • nil  ⇒ the HOST spoke; sender_kind :host; grounding from Conversation.host
  └─ … (blocks, mentions, grounding — as Parts IV/II)
```

This subsumes today's binary `source` exactly: `:user` ⇒ `sender_participant_id`
set; `:agent` ⇒ `sender_participant_id` nil (the host). The 2-valued enum
becomes "is the sender a participant or the host?", which generalizes to N
participants with **zero redundant state.** sender_kind is a calculation, in
the codebase's existing calc style (`needs_response`, `needs_title`).

## 40. The autonomous-agent escape hatch (when borrowed identity isn't enough)

Borrowed identity is right for a *reactive* host. A *proactive* agent (a future
internal agent that acts unprompted, or an external one that should run
least-privilege rather than as its caller) needs its **own** identity — and that
is just a Membership (role :agent), already supported. So the spectrum is:

```
reactive host turn        authz = addresser           (no identity; a voice)
external agent turn       authz = agent's Membership   (its own identity)
future internal agent     authz = its own Membership    (role :agent, scope :union)
```

One mechanism (Membership) covers every case that needs an identity; the host
is the one case that deliberately *doesn't* have one. No god-actor, no
special-case policy clause — the existing `WorkspaceMember` check works
unchanged for all three, because in every case the authz actor is a real
member.

## 41. New policy surface (additive, bounded)

The host model is the moment to give Conversation/Message real policies
(currently none). Minimal and coherent with `WorkspaceTenanted`:

```elixir
# Conversation
policy action_type(:read) do
  # a participant, OR (today's binary ACL) any workspace member
  authorize_if expr(exists(participants, membership.user_id == ^actor(:id)))
  authorize_if Concept.Pages.Checks.WorkspaceMember
end
policy action_type(:create), do: authorize_if Concept.Pages.Checks.WorkspaceMemberCreate

# Message: send authorizes as the sender's identity; a member may post to a
# conversation they can read. Host turns run authorize?: false from the Oban
# respond worker (as today), bounded by the borrowed actor passed into RAG/tools.
```

Nothing here is novel machinery — it reuses the two checks that already guard
Page/Block. The `participants` `exists` clause is the only addition, and it
fuses into SQL exactly like `workspace_memberships` does.

## 42. What the pressure-test changed

| Claim (Parts II–V) | After pressure-test |
|---|---|
| `:host` is a Participant with `membership_id` nil | **`:host` is NOT a participant** — it's a voice; Participants are memberships only |
| three participant kinds, symmetric | **two identities (user, agent) + one voice (host)**; asymmetry is the point |
| host has its own actor | host **borrows the addresser's actor** (leak-safe deputy) |
| Participant.kind stored | **derived** from membership.role; sender_kind derived from sender_participant nullability |
| (unstated) AI sees workspace | grounding = host.subgraph **∩ addresser visibility** |

The model got *simpler* (one fewer participant row type, one fewer stored
field) and *safer* (least-privilege by construction) — and it maps onto exactly
what `upsert_response` + `AiAgentActorPersister` already do. Once more the
refinement is a generalization of latent behavior, not an addition.

## 43. Refined one-breath vision (v2)

> A **Conversation** is an append-only stream *about* a **Host**. Its speakers
> are **Participants** — memberships (humans, external agents) joined to the
> conversation, each carrying an unread cursor that *is* the inbox. The host
> itself has no identity: it is a **voice** that speaks only when addressed,
> authorized as the participant who addressed it (a deputy, never a god),
> grounded in its own subgraph intersected with that participant's visibility.
> A **Message** is a turn whose body is **Blocks**, crystallizing into a Page by
> reparenting. `use Concept.Hostable` makes a resource conversable, riding the
> existing parity + tenancy machinery. Identity is always a Membership; voice is
> always a Host; and the binary `source` field we started with was the whole
> design in two values, waiting to be generalized.



---

# Part VII — Three pressure-tests: inbox, turn-budget, `discuss`

> All three tested against the live mechanics: `pub_sub` topology, the
> `run_oban_trigger(:respond)` + `where expr(needs_response)` path, and the
> `create_message` → `CreateConversationIfNotProvided` change.

---

## A. The inbox & @mention fan-out

### A.1 The gap (found by reading the topics)

Today's PubSub topology:

```
Message.pub_sub      prefix "chat"  →  "chat:messages:<conversation_id>"
Conversation.pub_sub prefix "chat"  →  "chat:conversations:<user_id>"
```

The message feed is keyed **by conversation**; the conversation feed is keyed
**by the single owner `user_id`** (the 1:1 reflex, again hardcoded). Neither is
a **per-recipient feed**. "Notification = unread message addressed to me"
requires a topic keyed by *recipient*, which does not exist. So the inbox is the
one projection that needs genuinely new wiring — worth being honest about.

### A.2 The mechanism: a fan-out notifier, not a new store

Don't build a `Notification` table (that's a parallel store of truth that drifts
from the messages). The inbox is a **projection** — a query + a fan-out topic:

```
INBOX(me) = conversations where exists(participant p:
              p.membership.user_id == me
              and p.last_read_message_id < conversation.last_message_id)
```

The unread cursor on `Participant` (§39) *is* the inbox state. No new
table — the read model is derived from data that already has to exist.

For real-time push, add **one** topic keyed by recipient. A message addressed to
users fans out to their per-user topics:

```elixir
# Message.pub_sub — add a recipient fan-out alongside the existing per-convo one
publish :create, ["inbox", :mentioned_user_id]   # one publish per addressee
```

Ash `pub_sub` can broadcast to a computed list; the `mentions` array (§4) is the
fan-out key. A `LiveView` subscribes to `inbox:<my_user_id>` once and receives
every addressed message across all conversations — the Slack-style global unread
badge, but **every entry has a host** (§15), so the inbox is context-rich, not a
pile of context-free pings.

### A.3 Mentions of users vs. hosts (the dispatch)

§21 claimed `@person` notifies and `@host` links. Concretely, `mentions` is
resolved at send time by the registry:

```
mention target is a Membership   →  fan out to inbox:<user_id>   (notify)
mention target is a Hostable      →  author a Knowledge.Link       (link)
                                      AND, if it names the host-voice,
                                      enqueue a host response (§B)
```

One `@`, dispatched by what the target *is* — the same registry that backs
`host_type`. Addressing and linking unify because both are "point at a
registered thing."

### A.4 Agent results land in the same inbox

An agent finishing async work `@`s the human in the host's conversation → same
fan-out → same inbox. "Agent inbox" and "human inbox" are **one inbox**, because
an agent reaching a human is just a participant addressing a participant. The
LangChain "async agents need an inbox" pattern falls out with zero agent-specific
code.

---

## B. Turn-budget & agent↔agent loops

### B.1 The exact trigger to gate

```elixir
# Message resource, today
trigger :respond do
  where expr(needs_response)              # source == :user and not exists(response)
  action :respond
end
# and on :create — change run_oban_trigger(:respond)
```

Two fire paths: the **inline** `run_oban_trigger` on create, and the **cron-less
trigger** `where`. Both consult `needs_response`. To bound agent turns, the
budget must enter `needs_response` itself — so a single calc governs *whether a
response is owed*, and the host model never double-implements the gate.

### B.2 Generalized `needs_response` (mentions × budget)

```elixir
# today
calculate :needs_response, :boolean,
  expr(source == :user and not exists(response))

# host model: a response is owed iff the host-voice is addressed,
# it hasn't answered THIS message, and the thread's budget isn't spent
calculate :needs_host_response, :boolean,
  expr(
    host_addressed? and                       # mentions includes the host-voice
      not exists(response) and                 # no reply to this msg yet
      conversation.agent_turn_budget > 0       # budget remains
  )
```

The crucial shift: today **every** user message is owed a reply (the reflex).
Host model: a reply is owed **only when the host-voice is `@`-addressed** — which
is exactly the §4 fix (human↔human = no AI) re-expressed as the trigger
condition. The budget is the third conjunct, so an exhausted thread simply makes
`needs_host_response` false and the trigger never fires. **No new scheduler, no
loop-breaker process** — the existing `where expr(...)` mechanism does it.

### B.3 Where the budget lives and who moves it

```
Conversation.agent_turn_budget :integer   (default small, e.g. 5)

decrement:  the :respond action, atomically, as it starts a host turn
            (atomic_update, like upsert_response's atomic text append)
replenish:  a :user-sourced message from a HUMAN participant resets it
            (a human re-engaging refills the budget — human attention is
             the rate-limiter, exactly right for a collaboration tool)
```

Agent↔agent: agent A `@`s agent B → B's turn decrements the budget → B `@`s A →
decrements again → budget hits 0 → `needs_host_response` false → **loop halts,
awaiting a human.** The budget is simultaneously the chatter-limiter and (§22)
the delegation-depth limiter — one integer, two runaway-risks contained.

### B.4 Atomicity (the race that would break it)

Two agent messages arriving together could each read `budget > 0` and both fire.
The decrement must be **atomic in the same action** that the trigger gates on —
and Ash already gives this: `atomic_update(:agent_turn_budget, expr(budget - 1))`
with the `where` re-checked at execution (`upsert_response` shows the atomic
pattern). The budget check and decrement are one SQL statement; concurrent
turns serialize on the row. No advisory lock, no GenServer.

---

## C. The `discuss` action ergonomics

### C.1 The codebase already answered "one action or two?"

`create_message` (the `:create` action) runs
`CreateConversationIfNotProvided`: pass a `conversation_id` → post into it; omit
it → a conversation is created, then the message is posted. **One action already
serves both "start" and "post."** `discuss` is the host-aware generalization of
exactly this, not a new shape.

### C.2 `discuss` = `create_message` with a host instead of a bare workspace

```elixir
# Conceptual: the action Hostable synthesizes on each host resource.
# It is create_message, with the conversation resolved FROM THE HOST.
discuss(host_record, text, opts) :=
  conversation =
    opts[:conversation_id]                         # post into an explicit thread
    || opts[:reply_to_message_id] && spawn_thread  # §13: child convo from a msg
    || find_or_create_conversation(                # the host's default thread
         host_type: host_record.__struct__,
         host_id:   host_record.id)
  create_message(conversation, text, sender: actor_as_participant)
```

Three resolution arms, one action — mirroring `get_or_create_conversation/3` in
`EvaluateAi`, but lifted to *any* host. The AI-block's hand-rolled
`get_or_create_conversation` (keyed by `block.props["conversation_id"]`) becomes
the `find_or_create` arm, deleted from the block and owned by Hostable (§33
step 6).

### C.3 Why it's ONE action, decisively

- **Parity** (§6): one described action = one clean MCP tool. `discuss` reads
  naturally for an LLM — "discuss this task: '…'" — whereas a
  `create_conversation` + `post_message` pair forces the agent to sequence two
  calls and thread an id, doubling the tool surface and the error modes.
- **The conversation is an implementation detail of "talking about X."** Humans
  don't think "create a conversation, then post"; they think "discuss this."
  Collapsing creation into the post matches the mental model — and the existing
  `CreateConversationIfNotProvided` proves the team already chose this.
- **Threads reuse it** (§13): `discuss(host, text, reply_to_message_id: m)` spawns
  the child conversation inheriting host + lineage. Starting a thread is
  *discussing with a parent pointer* — not a separate verb.

### C.4 The shape of the synthesized action (Hostable transformer)

```elixir
# Injected by Concept.Hostable.Transformers.InstallConversations onto the host
update :discuss do
  description "Start or continue a conversation about this <host>, optionally as a thread reply."
  argument :text, :string, allow_nil?: false,
    description: "What to say. May contain @mentions of members or other hostable resources."
  argument :conversation_id, :uuid,
    description: "Existing conversation to post into. Omit to use/create this <host>'s default conversation."
  argument :reply_to_message_id, :uuid,
    description: "Spawn a thread (child conversation) seeded from this message."
  change Concept.Hostable.Changes.ResolveConversation   # the 3-arm resolver above
  change Concept.Hostable.Changes.PostMessage           # = create_message internals
end
```

It's an `update` on the host (the host gains a conversation; the host is the
subject), carrying its own per-argument descriptions → `AutoTools` emits
`page_discuss`, `record_discuss`, `workspace_discuss` for free (§30 outcome 3).
Every hostable resource gets a parity-correct "talk about me" tool from one
stanza. The mockup-2 agent that posted into a Task's discussion was calling
`record_discuss` — now we can name the tool it used.

### C.5 One wrinkle: `discuss` mutates two resources

`discuss` creates a `Message` (and maybe a `Conversation`) — cross-resource
write. Per `AGENTS.md` rule 3 ("cross-resource workflows live in Reactors,
wrapped as a single action"), the resolver+post should be a **Reactor** wrapped
as the `discuss` action when it spans create-conversation + create-message +
budget-touch. For the single-resource arm (post into existing convo) it's a
plain change. Start plain; promote to Reactor when the thread-spawn arm lands
(it's the one that provably writes two resources). The rule tells us exactly
when the line is crossed.

---

## D. What the three tests collectively prove

| Test | Verdict | New machinery |
|---|---|---|
| **Inbox** | projection (unread cursor) + **one** recipient-keyed topic | 1 pub_sub line + 1 read calc — the *only* genuinely new feed |
| **Turn-budget** | a third conjunct in `needs_host_response`; atomic decrement | 1 integer attr + calc edit — **reuses the trigger**, no scheduler |
| **`discuss`** | ONE action (creation is an impl detail of posting) | 0 new patterns — generalizes `CreateConversationIfNotProvided` |

The inbox is the single place the host model adds a feed that doesn't exist
today — and even it is a projection, not a store. Budget and `discuss` are pure
generalizations of code already in the repo. The vision keeps paying the same
dividend: **the hard parts were already solved for the 1:1 case; the host model
is the act of removing the "1".**



---

# Part VIII — Crystallization, pressure-tested (where it cracks, and the fix)

> Claim under test (§19, §27): "crystallize = reparent a message's blocks onto
> the host page; `Block.reparent` already exists; citations + ingestion survive
> for free." Tested against `reparent`, `AssignAfterLastSibling`,
> `KnowledgeReindex`, `IngestPage`, and `Citation`. **It mostly holds — but two
> page-keyed assumptions crack. Both are fixable, and finding them now is the
> point.**

## 44. What survives cleanly (the claim holds here)

- **Reparent exists and re-indexes both sides.** `Block.reparent` accepts
  `parent_block_id` + `position`; `KnowledgeReindex` already handles the
  cross-page case — it enqueues an ingest for *both* the new `page_id` and the
  old container when a block moves. The dual-ingest path we need is already
  written.
- **Fractional ordering composes.** `AssignAfterLastSibling` computes
  `position` from the *target* `(page_id, parent_block_id)` siblings via
  `FractionalIndex.after_/1`. A block promoted to the page tail gets a clean
  trailing index regardless of its order-in-message. Reparenting N message
  blocks = N `after_` appends. No collision.
- **Citations are block-addressed, not page-addressed in spirit.** `Citation`
  has `block_id` + `page_id` with `on_delete: :delete` per FK. A citation
  *grounding* a host answer points at source blocks (on real pages); promoting a
  *message's own* blocks doesn't touch those rows. Grounding citations survive
  untouched.

## 45. CRACK 1 — ingestion is page-keyed; a message-block has no page

The ingest pipeline is **`source_id: "page:<page_id>"`** end to end:
`KnowledgeReindex.enqueue(workspace_id, page_id, op)` → `IngestPage` reads
`list_for_page(page_id)` → `Arcana.ingest(source_id: "page:#{page_id}")`. A
block living under a **message** (`message_id` set, `page_id` null — §28) has
**no page to key on.** Two consequences:

1. `KnowledgeReindex`'s block clause reads `block.page_id` → nil → it would
   enqueue `page:` garbage or crash.
2. Even if guarded, message-block content would be **unindexed** — breaking
   Pillar 2 ("conversation is searchable knowledge") and the GraphRAG union
   (§14), which assumes message content is retrievable.

### Fix: generalize the ingest key from `page` to `container`

The pipeline must key on a **source ref**, not a page id — the same
`{type, id}` shape as `host` (§11) and `container` (§28). Concretely:

```
source_id  "page:<id>"   →   "page:<id>" | "message:<id>" | "conversation:<id>"
```

- `KnowledgeReindex` dispatches on the block's container: `page_id` →
  `enqueue(:page, id)`; `message_id` → `enqueue(:message, id)` (debounced to the
  **conversation**, the natural ingest grain — a conversation re-ingests like a
  page).
- `IngestPage` becomes `IngestSource` (or gains a sibling): for a message/
  conversation source it lists the conversation's message-blocks instead of
  `list_for_page`.
- `Search.scope_opts` already speaks `source_id: "page:<id>"`; it gains
  `"conversation:<id>"` — which is **exactly the union term the GraphRAG design
  already needed** (§32 "union of scopes"). The crack and the §32 feature are the
  same work: generalizing `source_id` from one shape to a registry of shapes.

This is real work, but it's **bounded and already implied** by the host model's
RAG union. It is not new scope — it's the scope we said we'd build, surfaced
earlier by the ingest path. Better found here than in production.

## 46. CRACK 2 — crystallize MOVES blocks; the message loses its body

Reparenting a message's blocks onto the page **removes them from the message**
(a block has one container, §28 option A's CHECK enforces exactly one). After
crystallizing, the message bubble is empty — its content now lives on the page.
Is that desired? Two readings:

- **Move semantics** (literal reparent): the message *becomes* a pointer to the
  promoted blocks. Honest — "this was said, and it now lives on the page" — but
  the conversation scrollback develops holes.
- **Copy semantics** (clone then link): the message keeps its blocks; crystallize
  *clones* them onto the page with a `provenance` link back. Scrollback stays
  intact; the page gets durable copies. The mockup's "from conversation"
  provenance chip implies **copy**.

### Resolution: copy, with provenance — and it's the *crystallize* Reactor's job

Crystallize is **not** a bare `reparent`. It's a small **Reactor** (rule 3,
cross-resource):

```
crystallize(conversation, message_ids, target_page) :=
  for each selected message, for each block in message.blocks:
    clone block onto target_page (AssignAfterLastSibling → trailing index)
    author a Knowledge.Link  promoted_from: message_block → page_block  (provenance)
  (optionally) mark the conversation :crystallized → page (§20 workflow)
```


So §19's "reparent" was too literal. The right primitive is **clone + provenance
link**, reusing: block-clone (the schema supports it; `symbolClone` exists
conceptually as a create-from), `AssignAfterLastSibling` for ordering, `Link`
for provenance (which also feeds the knowledge graph — §21), and the Conversation
workflow (§20) to mark the decision durable. The mockup's green "just added" +
provenance chip is exactly this Reactor's output.

## 47. CRACK 3 (latent) — ingestion debounce key collisions

`KnowledgeReindex` dedups jobs by `unique: [fields: [:args], keys: [:page_id,
:op]]`. Conversation-sourced ingests keyed by `page_id: nil` would **collapse
into one job** (all nil keys collide). The fix rides Crack 1's: the dedup key
becomes `[:source_type, :source_id, :op]`, so `message:<id>` /
`conversation:<id>` ingests dedupe per-source like pages do. One change, same
place.

## 48. Verdict: the claim was 80% right; the 20% is bounded and shared

| Sub-claim | Status |
|---|---|
| `Block.reparent` exists + dual-side reindex | ✓ holds (already written) |
| fractional ordering composes on promote | ✓ holds (`AssignAfterLastSibling`) |
| grounding citations survive | ✓ holds (block-addressed, untouched) |
| message-block content is ingested | ✗ **page-keyed pipeline; needs container-keyed source** |
| crystallize = literal reparent | ✗ **should be clone+provenance (copy), via a Reactor** |
| debounce handles non-page sources | ✗ **dedup key must include source_type** |

The three cracks are **one piece of work**: generalize the ingest/scope key from
`page:<id>` to a `{source_type, id}` ref — which is the **same registry shape**
as `host_type` (§11) and `container` (§28), and the **same union** the GraphRAG
design already required (§32). The crystallization test didn't find three
unrelated bugs; it found that **`source_id` generalization is load-bearing for
three features at once** (message ingestion, conversation-scoped RAG,
crystallize provenance). That convergence is the signal to build it deliberately
and early — it is the spine of "conversation is knowledge," not an edge case.

## 49. Updated reuse ledger delta

| Need | Existing | Gap (this part) |
|---|---|---|
| promote blocks to page | `reparent` / clone + `AssignAfterLastSibling` | clone-with-provenance Reactor |
| dual re-index on move | `KnowledgeReindex` cross-page path | extend to container-keyed source |
| message content searchable | `IngestPage` + `BlockChunker` | `IngestSource` over message/conversation |
| conversation-scoped retrieval | `Search.scope_opts page:<id>` | add `conversation:<id>` (≡ §32 union) |
| provenance / decision trail | `Link` + Conversation workflow (§20) | wire promote→Link, convo→:crystallized |

Net: the host model's "conversation is knowledge" pillar has a concrete,
bounded build cost — the `source_id` generalization — and it pays off three
distinct features. Everything else in crystallization is reuse.

