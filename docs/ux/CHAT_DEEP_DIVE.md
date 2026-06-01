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

## Mockups (targets)

- `mockups/chat-streaming.png` — earlier target: streaming answer, shimmer,
  inline citations, "searching N pages" status, Stop button.
- `mockups/chat-thread-resumed.png` — **C1/C2/C4/C6 fix**: a full resumed
  thread (multiple turns, newest at bottom, auto-scrolled), sticky composer,
  panel that stays open.
- `mockups/chat-tool-and-error.png` — **C3 fix**: a quiet "Searching pages…"
  status chip + collapsed "Why this answer?" expander hiding tool/JSON, and a
  humane retryable error card replacing the red JSON blob.
