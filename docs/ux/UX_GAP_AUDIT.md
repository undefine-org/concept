# Frontend UX Gap Audit — Concept

> Bar: Notion / Linear-tier. Method: 4 parallel read-only scouts covered all 13
> LiveViews + 16 components + JS hooks + `app.css` + `core_components.ex`. Every
> gap carries `file:line` evidence. Verified live against `localhost:4279` (see
> `docs/ux/live/`).

## Root cause (explains ~60% of gaps)

`lib/concept_web/components/core_components.ex` is the **unmodified Phoenix
scaffold** — `flash · button · input · header · table · list · icon`, nothing
more. **Absent primitives:** skeleton, spinner, modal (focus-trap + esc),
toast-with-autodismiss, badge, tooltip, dropdown, empty-state, inline
field-error. The Notion look (`.ora-*`, `app.css`, 294 lines) was hand-built
per-surface, so every screen reinvents and the *states between states*
(loading / empty / error / pending) never got primitives.

**∴ Fix the design system first; most downstream gaps collapse to "use the new
primitive."**

---

## Tier 1 — Systemic

| # | Gap | Evidence |
|---|---|---|
| G1 | No loading/skeleton states; sync fetch in `mount` → blank → pop-in | `page_editor_live.ex:54-68`, `object_board_live.ex`, `command_palette_live.ex` (assign_async, no UI), `workspace_graph_live.ex:80` |
| G2 | Errors are flash-only, no inline recovery/retry | `work_live.ex:48-58`, settings forms, `chat_component.ex:905` |
| G3 | No optimistic UI — reorder/insert/delete/claim/field-save all wait for round-trip | `page_editor_live.ex:184-298`, `work_live.ex:48-68` |
| G4 | Pending-action feedback missing — buttons stay enabled; autosave gives no "saving…" cue | `record_detail_component.ex:56-87`, `work_live.ex:215-223` |
| G5 | No mobile layout — fixed widths (sidebar 240, chat 384, canvas 720); breakpoints unwired; no hamburger | `app.css:46,150,158`, `sidebar.ex:2` |
| G6 | A11y floor breached — `outline:none` on contenteditable, color-only lock indicator, sparse `aria-*`, no focus-trap | `app.css:54-65`, `page_header.ex:48`, `record_picker.ex` |

## Tier 2 — High-leverage surface gaps

| # | Gap | Evidence |
|---|---|---|
| G7 | Chat: no streaming — one pulsing dot then full message; no token stream, ETA, or retry | `chat_component.ex:800-808,399-419` |
| G8 | Board drag is blind — no drop-zone highlight/ghost; guard-rejected moves spring back silently | `task_board.js:55-61`, `object_board_live.ex:211-270` |
| G9 | Editor presence dead — `presence_users` assigned but **unused**; no cursors/avatars/names despite locks | `page_editor_live.ex:395-410`, `presence_bar.ex` |
| G10 | Command palette: no match feedback — identical result styling, no term highlight, no async loading, no focus ring | `command_palette_live.ex:180-195,110-125` |
| G11 | Record detail: no inline title edit, no autosave status, no focus trap in slide-over | `record_detail_component.ex:56-87` |
| G12 | Citation rail: 1.5s debounce invisible — keystroke → silence → results, no skeleton | `workspace_live.ex:420-430` |

## Tier 3 — Polish & affordance

| # | Gap | Evidence |
|---|---|---|
| G13 | No onboarding — home is bare hero + links; no first-run wizard/tour | `home_live.ex:35-75` |
| G14 | Weak empty states — only graph designed; work/board/settings/types are bare text | `work_live.ex:131,185`, settings, type editor |
| G15 | Composite blocks can't resize — tables/columns render, no resize/width UI | `block_render.ex:130,150` |
| G16 | No transitions on structural change — block insert, tree expand/collapse, hover-actions snap | `page_editor_live.ex:208`, `page_tree.ex:70-85` |
| G17 | No keyboard shortcuts beyond ⌘K — no j/k nav, `e` rename, slash discoverability | global, `slash_menu.js:73` |
| G18 | Toasts don't auto-dismiss; no `prefers-reduced-motion` | `layouts.ex:60-85`, `app.css:150` |

---

## Recommended sequencing

1. **Design-system primitives** (unblocks G1, G4, G6, G14, G18): skeleton,
   spinner, modal (focus-trap+esc), toast-autodismiss, badge, tooltip,
   empty-state, inline field-error — added to `core_components.ex` + `.ora-*`.
2. **Chat streaming** (G7) — highest single-surface impact; token stream +
   "searching N pages" status + Stop + retry.
3. **Board drag feedback** (G8) + **editor live presence** (G9) — the two
   collaboration surfaces that currently under-deliver on a real-time promise.
4. **Optimistic UI pass** (G3) across block ops + claim/transition.
5. **Mobile** (G5) — wire the declared breakpoints + hamburger sidebar.
6. **Onboarding** (G13) — first-run wizard.

## Proposed visuals

- `mockups/editor-live-presence.png` — G9: multiplayer cursors, name-flags,
  lock bar, avatar stack with online dots.
- `mockups/chat-streaming.png` — G7: streaming answer with shimmer last-line,
  blinking caret, inline citations, "searching 12 pages" status, Stop.
- `live/` — real screenshots of the current app at `localhost:4279` for
  before/after comparison.

> Mockups are aspirational targets; `live/` captures are ground truth.

---

## Tier 0 — Live-verified blockers (caught driving the real app)

These were found by signing into `localhost:4279` and exercising the surfaces
with a browser (screenshots in `live/`). They outrank the tiers above because
they are broken behaviour, not missing polish.

| # | Gap | Evidence | Severity |
|---|---|---|---|
| **B1** | **Chat conversation does not reload on reopen.** Sending a message persists it (DB: 1 conversation + 2 messages confirmed) but closing/reopening the panel resets to the blank seed-prompt state — the live conversation vanishes from view. | `live/06-chat-sent.png` ("Untitled conversation" + reply) vs `live/08-chat-reopened.png` (empty again); DB query confirms rows exist | **Critical** — looks like total data loss to the user |
| **B2** | **Chat panel auto-closes after send / on navigation**, dumping the user out of the conversation mid-flight. | `live/07-chat-answer.png` (panel gone after Send) | High |
| **B3** | **Empty void layout in chat.** A single user bubble pins to the bottom of a tall blank panel; "AshAi is responding…" is one tiny grey line with one dot — reads as frozen on multi-second calls. Conversation controls (Crystallize / chips) inject between indicator and composer, shoving the composer. | `live/06-chat-sent.png` | High (this is the "chat feels like crap" core) |
| **B4** | **Seed prompt click only fills the composer, doesn't send.** Two-step where one is expected. | `live/05-chat-responding.png` | Medium |
| **G19** | **Nav shell is inconsistent.** `ObjectBoardLive` (`/o/:type_id`, `/tasks`) renders via `Layouts.app` (marketing shell) instead of the workspace shell — **no sidebar**, only a breadcrumb back. | `live/02-task-board.png`; `object_board_live.ex:174` uses `<Layouts.app>` | High |
| **G20** | **Phoenix framework branding leaks into product chrome** — the flame `logo.svg` shows in the board top bar. Scaffold residue. | `live/02-task-board.png`; `layouts.ex:39` | Medium |
| **G21** | **Board overflows at 1440 with no scroll affordance** — the DONE column is clipped (`DC…`, `No ta…`). | `live/02-task-board.png` | Medium |
| **G22** | **List / to-do blocks render as plain paragraphs** — no bullet markers, no checkbox in the editor. | `live/01-page-editor.png` (bulleted/to_do blocks look identical to paragraphs) | Medium |

### Backend note (out of UX scope, but observed)
The grounded-AI reply was a refusal ("I cannot fulfill this request — the
available tools…") — a tool/grounding misconfiguration, not a UI gap. Flagged
for the knowledge/agent owners; does not change the UX findings.

## Live screenshots (ground truth)

| File | Surface |
|---|---|
| `live/01-page-editor.png` | Page editor (seeded "Q3 Product Strategy") |
| `live/02-task-board.png` | Task board (no sidebar; Phoenix logo; clipped column) |
| `live/03-command-palette.png` | Command palette (semantic matches) |
| `live/04-chat-empty.png` | Chat panel empty state |
| `live/05-chat-responding.png` | Seed prompt filled composer (didn't send) |
| `live/06-chat-sent.png` | After send — empty-void layout + tiny responding line |
| `live/07-chat-answer.png` | Panel auto-closed after send |
| `live/08-chat-reopened.png` | Reopened — conversation gone, back to seed prompts |
