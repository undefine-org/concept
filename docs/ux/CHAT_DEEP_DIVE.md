# Chat Experience — Deep Dive vs. World-Class

> Driven live against `localhost:4279` with a seeded workspace. The chat
> backend **works** — grounded answers persist (DB: 1 conversation, 4 messages,
> incl. a correct "The Container primitive is a fundamental concept…" reply).
> **The UI actively hides its own working output.** Every issue below is a
> front-end shell problem, not a model problem.
> Screenshots: `live/04`–`live/10`.

## What world-class chat (Notion AI / Linear / ChatGPT / Claude) does

1. **Persistent thread** — reopening the panel resumes the live conversation,
   scrolled to the latest turn. History is the default, blank is the exception.
2. **Panel stays open** through send → stream → answer → follow-up. The user
   stays in flow; the panel is a workspace, not a one-shot modal.
3. **Token streaming** — the answer materializes word-by-word with a caret, so
   multi-second calls feel alive. A skeleton/shimmer precedes first token.
4. **Tool calls are progressive disclosure** — "Searching 12 pages…" as a
   quiet status chip; the raw tool name + JSON args live behind a "Why this
   answer?" expander, never inline by default.
5. **Errors are humane** — "I couldn't search the workspace just now. Retry?"
   with a button. Never a red `{"code":"invalid","status":"400"}` blob.
6. **Newest turn anchored to the bottom**, auto-scrolled; composer pinned; send
   shows a pending state and disables re-send.
7. **Citations are first-class** — inline chips `[1]` linking to source blocks,
   a sources list under the answer.

## What Concept does today (live-verified)

| # | Gap | Evidence | Severity |
|---|---|---|---|
| **C1** | **Conversation is discarded on reopen.** Both Q&A pairs persisted to the same DB conversation, but reopening the panel shows only the blank seed-prompt state. | `live/06` & `live/08` & `live/10`; DB shows 4 messages | **Critical** — looks like total data loss |
| **C2** | **Panel auto-closes after every send.** Answer arrives → panel ejects the user. Happens on every message. | `live/07`, `live/10` (panel gone post-settle) | **Critical** — breaks the core loop |
| **C3** | **Raw tool-call JSON + red error blobs render inline** in the message stream: `tools_search_workspace({"input":{"query":…}})` and `error (tools_search_workspace): [{"code":"invalid",…,"status":"400"}]`. | `live/09` | **High** — exposes plumbing; reads as broken |
| **C4** | **Message order is scrambled** — a prior answer renders above the newly-sent question; "responding" indicator placement is inconsistent. | `live/09` (old answer top, new question below) | High |
| **C5** | **No streaming.** Answer appears all-at-once after a multi-second wait; the only progress cue is one tiny grey "● AshAi is responding…" line. | `live/06`, `live/09` | High |
| **C6** | **Empty-void layout.** A single message bubble pins to the bottom of a tall blank panel; conversation controls (Crystallize / chips) inject between the responding line and composer, shoving the composer around. | `live/06`, `live/09` | High |
| **C7** | **Seed prompt fills composer but does not send** — two steps where one is expected. | `live/05` | Medium |
| **C8** | **No send-pending / disabled state**; no retry on failed send. | `live/07`, `live/09` | Medium |
| **C9** | **Host rendered as a participant, not a seep.** Host replies render as their own avatar-style `--agent` rows in the timeline instead of as a continuation fused to the message they answer (`response_to_id`). Breaks the "voice, not a person" model and the inter-team-comms framing. | `chat_component.ex:242-296,334`; see contrast mockup | **High** — wrong conversation model |

## Backend note (out of UI scope)
Grounded queries intermittently fail with a tool 400 (`tools_search_workspace`
"invalid"). The retry produced a correct answer, so it's flaky, not dead —
flagged for the knowledge/agent owners. The **UI bug** is that it renders the
raw failure instead of a humane fallback (C3).

## Priority fix order (front-end only)

1. **C1 + C2** — load the active conversation on panel open; stop closing the
   panel on send/settle. These two alone transform "feels broken" → "works."
2. **C3 + C4** — suppress raw tool/error nodes (move behind "Why this answer?");
   fix turn ordering (newest at bottom, auto-scroll).
3. **C5 + C6** — real message-list layout (top-anchored history, sticky
   composer) + streaming text with a skeleton-then-caret first-token cue.
4. **C7 + C8** — one-click seed prompts; send-pending + retry affordance.

## The conversation model (corrected)

The earlier mockups got the frame wrong — they treated this as 1:1 "me vs a
bot." It is not. The schema is the source of truth:

- A conversation is anchored to a **host** (`host_type`/`host_id` — a page or
  the `:workspace`). The host is **not a participant**.
- `message.source ∈ {user, agent, host}`; `addresses_host` ("false for
  human-to-human messages"); `sender_participant_id`; `mentions`;
  `response_to_id`.
- Participants are humans (`kind` derived from membership role); the host has a
  **grounded voice**, explicitly "a voice, not a person"
  (`chat_component.ex:334`).

**∴ Two render modes, not one:**

1. **Inter-team comms (Slack-like).** `source: :user`, `addresses_host: false`
   → left-aligned rows: avatar + semibold name + timestamp, `@mentions`,
   typing indicators. Multiple humans talking to each other.
2. **Host seep (continuation).** `source: :host` with `response_to_id` → the
   grounded answer is rendered as a **continuation fused to the exact message
   it answers** — shared indent, a thin blue accent rail, a "from this
   workspace" sparkle label, inline citations — **no avatar, no name row.** The
   host *seeps* out of a message; it does not take a turn in the timeline.

> Today's code renders host replies as their own `ora-chat-message--agent`
> rows (`chat_component.ex:242-296`) — the participant model. The fix is to
> bind a host reply to its `response_to_id` parent and render it as an inset
> continuation. This is also what makes crystallize-into-page coherent: a page
> is a thread where the host's seeps have settled into the body.

## Mockups (targets)

- `mockups/chat-team-thread-host-seep.png` — **the model**: a Slack-like
  multi-human thread (Maya/Devin/Sara, avatars, names, timestamps, `@Maya`
  mention, typing indicator) where the host's grounded answer is **fused
  beneath Maya's message** (blue rail + "from this workspace" + `[1]`), not a
  separate avatar row. Sticky composer with `@`-mention.
- `mockups/chat-participant-vs-seep.png` — **the principle**, side-by-side:
  ✗ host as a "Concept AI" avatar row in the timeline (wrong) vs ✓ host fused
  as a grounded continuation of the message it answers (right). Title: "Host
  should annotate a message, not enter the timeline."
