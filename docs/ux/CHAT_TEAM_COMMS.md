# Chat → Team Communications — Design

> Companion to `docs/messaging_design.md` (the canonical model) and
> `docs/ux/CHAT_DEEP_DIVE.md` (the host-seep correction). This doc answers one
> question: **what does Concept's chat need to be a complete team-comms surface
> (Slack/Linear-tier), and how does each feature fall out of a primitive that
> already exists?**

---

## 0. The thesis: the substrate is built; the projection is missing

`messaging_design.md` already designed the whole thing — Concept doesn't get "a
chat feature," it gets a **conversation substrate** where every team-comms
concept is a *view onto the host model*, not a bolt-on:

```
HOST › CONVERSATION › THREAD — the three levels (the Zulip grain, §2):

  Host          a conversable PLACE: a Page · the Workspace · (later) a User
                  └ one host → MANY conversations (for_host returns a list)
  Conversation  a TOPIC inside a host (auto-titled by generate_name)
                  └ the channel-item you click; the unit the panel shows
  Thread        a child Conversation seeded from a message (seed_message_id, §13)

Everything team-comms is a view onto that spine:
  Channel       = a Host + its conversation list (a page IS a channel)   §16
  DM            = a Conversation whose host is a User                    §15
  Notification  = an unread Message addressed to me                      §A
  Inbox         = conversations where my participant cursor lags         §39
  Mention       = @person notifies · @host links                        §21
  Crystallize   = reparent a Message's blocks onto its host Page         §27
  Decision      = a Conversation with a Workflow state                   §20
```

The **schema already carries** threads, participant unread-cursors
(`last_read_message_id` + `mark_read`), the inbox fan-out (`BroadcastInbox` →
`inbox:<user_id>`), `mentions`, and message-bodies-as-Blocks
(`Message.has_many :blocks`). What's missing is almost entirely **front-end
projection**. That is the opportunity and the discipline: *finish the views, do
not invent parallel data.*

### Completeness matrix (team-comms need → primitive → gap)

| Team-comms need | Concept primitive (status) | Gap to close |
|---|---|---|
| **Channels** | conversations sharing a host — emergent (§16) | sidebar is a flat `my_conversations`; no per-host grouping, no unread badges |
| **Threads** | child conversation: `seed_message_id`, `parent_conversation_id`, `for_seed`, `reply_to_message_id` (✓ schema) | **zero UI** — no "reply in thread", no thread panel, no reply-count chip |
| **Unread / read receipts** | `Participant.last_read_message_id` + `:mark_read` (✓ schema) | no "new messages" divider, no per-channel unread count, no "seen by" |
| **@mentions** | `Message.mentions` + composer (✓ both) | not surfaced: no mention highlight in-thread, no mention filter in inbox |
| **Notifications** | `inbox` read + `inbox:<id>` topic (✓ both) | inbox list has no unread/mention/thread typing; not real-time-badged in the sidebar |
| **Reactions** | — *(not modeled)* | the one honest net-new: a `Reaction` join (membership × message × emoji), mirrors `Participant` |
| **Human presence / typing** | `Phoenix.Presence` (✓ used in the editor) | only the host "is thinking"; humans have no typing/presence in chat |
| **Rich messages** | `Message.blocks` = the same Block unit as a page (§27, ✓ schema) | composer is a flat text `<input>`; no `/` slash menu, no block body |
| **Message actions** | append-only + `crystallize` + `Block.reparent` (✓) | no hover toolbar: react / reply-in-thread / crystallize-this / copy-link / pin |
| **DMs** | a Conversation hosted by a User (§15) | `User` is not yet `use Concept.Hostable` (one stanza) |
| **Decisions** | `Conversation` `use Hostable` + `Workflow` (§20) | no decided-state badge; threads can't be resolved |

---

## 1. What I'm inspired to build — the core (Tier 1)

Five features. **None adds a table.** Each is a projection of a primitive that
exists, dispatched through a registry the way block-types are. Together they
turn the panel into a place a team lives.

### 1.1 Adaptive channels rail — *host › conversation, grouped only when it pays*

The left rail stops being a flat `my_conversations` list. It groups by **host**
(the channel) and lists **conversations** (the topics) under it — but
*adaptively*, so the common "one chat about a page" case stays flat and the
heavy grouping appears only when there's something to group.

```
+ New conversation ─────────────────────  ← global host-picker (see below)
WORKSPACE
  # General                       ● 3      ← :workspace host
PAGES
  ▾ Offline Sync                     +     ← host w/ ≥2 convos → COLLAPSIBLE CATEGORY
      conflict resolution?       ● 2          (hover-reveal + : new topic here)
      migration plan
      edge-case audit
  Q3 Roadmap kickoff             ●         ← host w/ EXACTLY 1 convo → INLINE
      in Q3 Roadmap (muted, on hover)          the page ref seeps in on hover
DIRECT MESSAGES                             ← :user hosts (DMs, §15)
  ◔ Maya Chen
  ○ Devin Park
```

**The adaptive rule (the part you caught):** `for_host` returns a *list* — a host
has MANY conversations. So:

- host has **≥ 2** conversations → render the host title as a **collapsible
  category separator**; conversations indent under it with a left guide line.
- host has **exactly 1** → render the conversation **inline** (don't burn two
  lines on a header), and reveal a **muted `in <Page>` ref on hover** so its
  subject is never lost.
- host has **0** → it isn't in the rail at all (nothing to show).

This keeps scannability when a page has a single thread, and only pays the
grouping cost when a page has accumulated several topics.

- A **page channel** is `conversations_for_host(:page, page_id)` — discussing a
  page *is* a channel about it (contextual conversation as a consequence, §Pillar 3).
- The unread dot is `participant.last_read_message_id < conversation.last_message`
  — the cursor that already powers the inbox, read per-conversation.
- Real-time: the `inbox:<user_id>` topic already fans every addressed message;
  the rail subscribes once and re-badges. **No new topic.**

#### The `+` — starting a conversation means *choosing a host*

Today `+` → `new_chat` → a blank composer addressing whatever host happens to be
current — **ambiguous** ("a new topic about *what*?"). Starting a conversation
*is* the `discuss` action = `create_message` with host addressing, so `+` must
make the host explicit. Two entry points, one resolution:

- **Per-category `+`** (hover-revealed on a host header, Slack-style): "new topic
  about *this page*" — host pre-bound, one click. The everyday path.
- **Global `+ New conversation`** (top of rail): a ⌘K-style **host-picker**
  popover — search across `WORKSPACE` · `PAGES` · `PEOPLE (DM)`, pick a host,
  optional topic name, Enter. This is `discuss`-from-anywhere.

Both call the same `create_message`/`discuss`; they differ only in whether the
host is pre-bound. The picker's sections are **`Hostable.types()`** — a new
Hostable (e.g. `:record`) adds a "TASKS" group with zero picker edits. See
`mockups/chat-host-picker.png`.

### 1.2 Threads — *make `seed_message_id` visible*

The schema is 100% there and the UI shows none of it. Add:

- a **"💬 N replies · last 2m ago"** chip under any message that seeded a thread
  (`Chat.conversation_for_seed(message_id)`);
- a **"Reply in thread"** hover action → `create_message(reply_to_message_id: m)`
  (the change already spawns the child conversation inheriting host + lineage);
- a **right-side thread panel**: parent message pinned as the seed at top, the
  child conversation's own messages below, its own composer ("Reply in
  thread…"). The host can seep *inside a thread* too — lineage RAG (§14) means a
  thread's host answer sees its ancestors' messages for free.

Reply-in-thread is the single highest-value team-comms affordance still dark.

### 1.3 Unread state — *the cursor, surfaced three ways*

`last_read_message_id` already exists; render it:

1. a **"New" divider** in the stream at the first unread message;
2. a **per-channel unread badge** in the rail (§1.1);
3. **"seen by"** — tiny stacked avatars under the latest message, from each
   participant's cursor (read receipts, the trust signal teams expect).

`:mark_read` advances on view (an `IntersectionObserver` hook firing
`mark_read` when the latest message scrolls into view). One existing action,
three projections.

### 1.4 Message hover toolbar — *every message is a unit of work*

A floating toolbar on message hover, each button a projection:

| Action | Projects |
|---|---|
| 😀 **React** | a `Reaction` (Tier 2 §2.1) |
| 💬 **Reply in thread** | `create_message(reply_to_message_id:)` (§1.2) |
| ✨ **Crystallize this message** | reparent *this message's* blocks → host page (§27) — per-message, finer than the whole-conversation Crystallize |
| 🔗 **Copy link** | a message is already addressable (`message.id`) + citable |
| 📌 **Pin** | Tier 2 (a pinned-message marker) |

"Crystallize this message" is the quietly profound one: because a message's body
is **Blocks**, promoting one message to the page is `Block.reparent` on its
blocks — talk becomes document at the granularity of a single insight.

### 1.5 Human presence & typing — *reuse the editor's Presence*

The editor already tracks live collaborators via `Phoenix.Presence` (C-2). Point
the same mechanism at a conversation topic:

- avatar dots with online/idle state in the channel header & rail;
- **"Devin is typing…"** for *humans*, sitting beside the existing host
  "is thinking" seep — symmetric: people type, the host thinks.

### 1.6 Members — *the UI for `Participant.join`*

A conversation already has participants (`Participant` = a Membership joined into
a Conversation, with an unread cursor). "Add people" is simply the **UI for the
`:join` action that already exists** (`upsert?`, idempotent) — no new data.

- An **"Add people" modal** (`mockups/chat-add-people.png`): current participant
  chips (removable → `Participant.destroy`) + a searchable workspace-member list
  with checkboxes → `Participant.join` per selection. Reachable from the
  participant rail's `+` **and** offered inline when a conversation is created
  from the host-picker (§1.1) — one modal composes with both flows, so I keep the
  rails as drawn and add the modal rather than redoing them.
- The **host's grounded voice is a fixed, non-removable chip** (sparkle, blue,
  no ×) — it is a *voice, not a member* (§39). The modal renders it distinctly so
  the identity-vs-voice distinction is legible in the UI, not just the schema.
- **External agents** (`membership.role == :agent`) appear in the same list with
  a violet `agent` tag: adding an agent participant is the same `:join`. The
  team-comms member picker is, for free, the agent-collaboration picker.

> Parity: `join` / `Participant.destroy` / `mark_read` are described actions →
> free MCP tools. An agent can add a teammate to a thread exactly as a human can.

---

## 2. The frontier it opens (Tier 2 — small schema, same substrate)

Once the core lands, these are each a *single stanza or a tiny resource*,
exactly as the spec promised ("answers questions you never posed"):

- **2.1 Reactions** — the one genuinely new resource, and it mirrors
  `Participant` precisely: a `Reaction` is the join of a *membership* × a
  *message* × an emoji. Identity-keyed (so "who reacted" is real), parity-exposed
  as `react` / `unreact` described actions → free MCP tools (an agent can 👍).
  Real-time over the existing per-conversation topic.
- **2.2 Rich composer (blocks)** — give the composer the page's `/` slash menu;
  a message body becomes `Message.blocks` (§27). Crystallize then becomes
  *literally* reparent, ingestion of message content becomes free (§45), and a
  human composes with the full editor. Biggest payoff, most work — sequence last.
- **2.3 DMs** — `use Concept.Hostable` on `Accounts.User` (§15). One stanza →
  a User becomes conversable → DMs are conversations hosted by a person, with
  the **same** rail, composer, threads, reactions. No new surface.
- **2.4 Decisions** — `Conversation` `use Hostable` + a `Workflow` (§20). A
  thread gains a state (`open → decided`); a decided thread with a crystallized
  page is a first-class, searchable decision record. The task engine and the
  conversation engine are revealed to be the same engine (the A2A insight).

---

## 3. Mockups (this doc's deliverables)

Targets, not screenshots — the running app is ground truth and these guide the
build:

- `mockups/chat-team-adaptive-rail.png` — **the hero.** Two-pane: the adaptive
  rail (host › conversation; `Offline Sync` as a multi-topic collapsible category
  vs. `Q3 Roadmap kickoff` inline with its hover page-ref) + global `+ New
  conversation` · a page-hosted topic `conflict resolution?` with grouped human
  messages, a `@Devin` mention, reaction chips, a host **seep** fused under Maya's
  message (blue rail · "from this page" · `[1]`), a "3 new" divider, a thread
  chip "4 replies", "seen by" receipts, a hover toolbar, "Devin is typing…".
- `mockups/chat-host-picker.png` — **the `+` answered.** The ⌘K-style host-picker
  popover: search across `WORKSPACE` · `PAGES` · `PEOPLE (DM)`, an optional topic
  name, `Start conversation`. Starting a conversation = choosing a host.
- `mockups/chat-message-actions-thread.png` — **every message is a unit + threads
  made visible.** Close-up of the hover toolbar + open emoji picker + reaction
  chips (own-reaction outlined) + per-message "Crystallize this message → page",
  beside the docked thread panel: the seed pinned at top, the child conversation
  below (a host seep inside it), its own "Reply in thread…" composer + breadcrumb.
- `mockups/chat-add-people.png` — **members = `Participant.join`.** The "Add people" modal: current participant chips
  (removable), the host's fixed non-removable AI-voice chip, a searchable
  workspace-member list with checkboxes (agents tagged violet), `Add to
  conversation`. Composes with both new- and existing-conversation flows.
- *(planned)* `mockups/chat-inbox-activity.png` — **the notification story.** The unified,
  recipient-keyed feed: mentions · thread replies · host answers · reactions in
  one list, filter chips (All / Mentions / Threads / Reactions), each entry
  host-contextual, unread grouped on top.

---

## 3b. Decisions locked (this review)

1. **3-level model** Host › Conversation › Thread — confirmed. `for_host` returns
   a list; a page is a channel that accumulates topics.
2. **Adaptive rail** — ≥2 conversations → collapsible host category; exactly 1 →
   inline conversation + muted `in <Page>` hover ref.
3. **`+` = host-picker** — global `+ New conversation` opens a ⌘K-style host
   picker; per-category `+` pre-binds the host. Both → `discuss`/`create_message`.
4. **Host-native glyphs, not `#`** — a channel is a *place*, not a chatroom:
   📄 page · ✦ workspace · avatar for a DM. Drop the Slack `#`. Reads honestly
   with the breadcrumb and the host model. *(The sent mockups still show `#`;
   the build uses host-native glyphs — the mockups are hypotheticals, the running
   app is ground truth.)*
5. **Members via modal** (§1.6) — keep the rails as drawn; "Add people" is a
   modal over `Participant.join`, composing with both flows.
6. **Sequencing** — **T1 first** (adaptive rail + host-picker `+`): biggest
   "feels like a real comms tool" jump, zero schema. Then T2 threads, T3
   presence/unread, then reactions/DMs/decisions.

---

## 4. Build sequence (waves) — projections first, schema last

| Wave | Items | Net-new schema |
|---|---|---|
| **T1** | §1.1 Adaptive rail + host-picker `+` · §1.6 "Add people" modal | **none** (`Participant.join`) |
| **T2** | §1.2 Threads (chip + panel + reply) · §1.4 hover toolbar (sans react) · §1.3 unread divider + badges | **none** |
| **T3** | §1.5 Presence/typing · §1.3 "seen by" receipts | **none** (Presence) |
| **T4** | §2.1 Reactions | 1 join resource (`Reaction`) |
| **T5** | §2.3 DMs (`User` Hostable) · §2.4 Decisions (Conversation workflow) | 1 stanza each |
| **T6** | §2.2 Rich block composer | `Block.message_id` path (already designed §27) |

Each wave ships behind the 5-layer gate (compile · component test · interaction
test · live puppeteer · `mix precommit`) with a per-item screenshot proof — the
same discipline as the A–E waves.

### Parity dividend

Because every action carries a `description`, each of these is **simultaneously
an MCP tool** the moment it ships: `react`, `reply_in_thread`
(`create_message` + `reply_to_message_id`), `mark_read`, `crystallize`. An agent
participates in a team thread — reacts, replies, resolves — through the exact
actions a human drives from the LiveView. The team-comms surface is, by
construction, also the agent-collaboration surface. That is the whole point.
