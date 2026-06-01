# Concept — Master Improvement Plan

> Every gap from the UX audit (`UX_GAP_AUDIT.md`) + chat deep-dive
> (`CHAT_DEEP_DIVE.md`), categorised, with structural implementation hints
> grounded in the codebase's **own** gold-standard pattern: the block-type
> system (`lib/concept/pages/block_types/AGENTS.md`).
>
> The thesis: the block-type/MCP/Ash stack already encodes the right code
> ethic — **declare once, project everywhere; dispatch on a trait, never a
> `case`**. Chat, records, and the design system don't yet follow it. Most
> "improvements" below are really *"apply the pattern you already have."*

## The code ethic (from block_types → generalise everywhere)

| Principle | Where it already lives | How you know it's right |
|---|---|---|
| **Registry is the single source of truth** | `config :concept, :block_types` · `:containables` · `:hostables` | Adding a kind = 1 config line; no dispatcher edit |
| **Dispatch on a derived trait, never the concrete type** | `BlockRender.block/1` has ONE `case` on `render_kind/0` (4 flavours), never on the 20 types | No `:paragraph`/`:heading` literals in the dispatcher; types self-describe |
| **Declare once → project everywhere** | `BlockType.Interactive` `ash_actions:` → LV `handle_event` + JS `data-events` + MCP specs | One decl, four surfaces wired by construction |
| **Parity by construction** | `AutoTools`: an action's `description` *is* its MCP tool | `mcp_parity_test.exs` enforces it |
| **Flavour mixins, compile-time contract** | `Static` / `Text` / `Interactive` / `Composite`; `@before_compile` raises if `render_body/1` missing | Forgetting wiring fails to compile, not at runtime |
| **The macro guarantees cross-cutting wiring** | Interactive always emits `phx-hook`/`phx-update`/`data-*` | "The user cannot forget any of them" |
| **One job, one level of abstraction** | type module owns its prop validation + slash item + render | No block logic leaks into `BlockRender` |

**Litmus test for any new surface:** *Can a contributor add a variant with one
registry line and one module, touching no dispatcher and no JS?* If no, the
structure is wrong.

> Note: a single `case` on a **derived trait** (`render_kind/0` → 4 flavours)
> is correct — it's closed and stable. The anti-pattern is branching on the
> **open-ended concrete kind** inline (`sender_kind(message) in [:agent,
> :host]` scattered across a template, as chat does today). Dispatch on the
> trait; let the kind module own its markup.

---

## Category A — Design system (root cause; unblocks ~60%)

`core_components.ex` is the unmodified Phoenix scaffold. Build the missing
primitives **once**, then every surface consumes them.

| ID | Improvement | Structural hint |
|---|---|---|
| A1 | Skeleton / shimmer loader | `core_components.ex` `skeleton/1` + `.ora-skeleton` keyframe in `app.css`; drive from LV `AsyncResult` |
| A2 | Spinner / pending button state | `button/1` gains `:loading` attr → disabled + inline spinner; one component, all forms |
| A3 | Modal dialog (focus-trap + esc) | `modal/1` + a `FocusTrap` JS hook in `assets/js/hooks/`; replaces ad-hoc `record_picker` overlay |
| A4 | Toast with auto-dismiss + `aria-live` | extend `flash/1`/`flash_group/1`; a `.ora-flash` timer hook |
| A5 | Empty-state component | `empty_state/1` (icon + copy + CTA slot); kill the bare-text empties (work/board/settings) |
| A6 | Inline field error + badge + tooltip | `field_error/1`, `badge/1`, `tooltip/1` — design-system, not per-surface |

> Ethic: these are **mixadable primitives** like `Text`/`Static` — the surface
> declares intent (`<.skeleton rows={6}/>`), the primitive guarantees the look.

---

## Category B — Chat: the conversation model (highest impact)

Today `chat_component.ex` branches inline on
`sender_kind(message) in [:agent, :host]` (`:242-296`) and dumps raw
`tool_calls`/`tool_results`. That is the **"edit the dispatcher / hardcode the
case"** anti-pattern the block AGENTS.md forbids — applied to messages.

**The structural fix: a message-kind registry that mirrors block-types.**
A message renders by dispatching on a derived *render mode*, not scattered
boolean checks.

```
Concept.Chat.MessageKind            # behaviour + registry (twin of BlockType)
  render_mode(message) :: :human_row | :host_seep | :agent_row | :system
  render/1                          # the row/seep markup for that mode
```

| ID | Improvement | Gap | Structural hint |
|---|---|---|---|
| B1 | **Resume conversation on panel open** | C1 | `WorkspaceLive` mount: load the active conversation for `{host_type, host_id}` via `Chat.conversation_for_host`; stream existing messages. Stop seeding blank. |
| B2 | **Keep panel open through send→answer** | C2 | Panel `@open` is reset on re-render after send (not the explicit `"close"` button → `:close_chat_panel` in `chat_panel.ex:44`). Make `@open` survive the message-stream update; panel state must be independent of the message lifecycle |
| B3 | **Host seep, not participant row** | C9 | Dispatch: `source: :host` + `response_to_id` → `:host_seep`, rendered as a continuation **fused under its parent message** (shared indent, blue rail, "from this workspace", citations) — no avatar row. `source: :user, addresses_host=false` → `:human_row` (Slack-like avatar+name+timestamp). See `mockups/chat-participant-vs-seep.png`. |
| B4 | **Tool calls / errors behind disclosure** | C3 | Move raw `tool_calls`/`tool_results` out of the stream into the existing `why_this_answer/1` expander; render failures as a humane `error_card/1` (Category A), never raw JSON |
| B5 | **Correct turn ordering + auto-scroll** | C4 | Stream sort by `inserted_at`; newest at bottom; a `ScrollToBottom` JS hook on new-message |
| B6 | **Token streaming + skeleton-then-caret** | C5 | Replace the single pulsing dot; stream partial `text` into the seep/row; `.ora-typing` caret + A1 skeleton on first token |
| B7 | **Real message-list layout** | C6 | Top-anchored history, sticky composer; conversation controls (Crystallize/chips) move to a header, not injected mid-stream |
| B8 | **One-click seed prompts + send-pending + retry** | C7,C8 | Seed button dispatches send directly; `button/1` `:loading` (A2); failed send → retry affordance |

> Ethic payoff: once `MessageKind` exists, **crystallize-into-page** is the
> same dispatch the other direction — a page is a thread whose host-seeps have
> settled into block bodies. One model, both directions.

---

## Category C — Editor & blocks

| ID | Improvement | Gap | Structural hint |
|---|---|---|---|
| C-1 | List / to-do render as real lists/checkboxes | G22 | `to_do.ex`/`bulleted_list_item.ex` `editor_class/0` + lexical node mapping — fix in the **type module**, never `block_render.ex` |
| C-2 | Live presence (cursors/avatars in editor) | G9 | `presence_users` is assigned but unused (`page_editor_live.ex:395`); render via a `PresenceCursors` hook keyed on the existing Presence topic |
| C-3 | Lock indicator: label + tooltip, not colour-only | G6 | extend the `.ora-block-row[data-locked-by]` rail with `tooltip/1` (A6) |
| C-4 | Optimistic block insert/reorder/delete | G3 | client-side echo in `block_list.js` before server confirm; reconcile on stream patch |
| C-5 | Skeleton on page load; focus rings | G1,G6 | A1 skeleton in `page_editor_live` render; drop `outline:none`, add `:focus-visible` ring |
| C-6 | Composite (table/columns) resize handles | G15 | a Composite-flavour concern — add to `BlockType.Composite`, inherited by all composites |

---

## Category D — Nav shell, board, records

| ID | Improvement | Gap | Structural hint |
|---|---|---|---|
| D-1 | **Board/records inside the workspace shell** | G19 | `ObjectBoardLive` renders `Layouts.app` (marketing). Route it through the same shell as `WorkspaceLive` (sidebar). Consider a single `Layouts.workspace/1` all authed surfaces use |
| D-2 | **Remove Phoenix flame from product chrome** | G20 | `layouts.ex:39` `logo.svg` — replace with the workspace identity used elsewhere |
| D-3 | Board horizontal scroll affordance | G21 | column container: scroll-snap + edge fade; or responsive column collapse |
| D-4 | Board drag feedback + guard-reject reason | G8 | `task_board.js`: drop-zone highlight, ghost; on server reject, an `error_card`/toast (A4) explaining the guard |
| D-5 | Record slide-over: autosave status, focus-trap, inline title | G11 | autosave "saving…/saved" badge (A2); reuse the A3 focus-trap; inline-editable title field |
| D-6 | Record picker: focus, arrow-nav, esc | G6 | rebuild on the A3 modal primitive (gets focus-trap + esc free) |

---

## Category E — Cross-cutting (a11y, mobile, onboarding, polish)

| ID | Improvement | Gap | Structural hint |
|---|---|---|---|
| E-1 | Mobile layout | G5 | wire the declared breakpoints; sidebar → hamburger; chat/board responsive widths. Do it in `Layouts.workspace/1` once (D-1) |
| E-2 | Onboarding first-run | G13 | a `WorkspaceLive` first-run state (no pages/records) → guided empty-state (A5) with CTAs |
| E-3 | Keyboard shortcuts beyond ⌘K | G17 | extend `global_keys.js` + a shortcut registry; surface hints in command palette |
| E-4 | Empty states everywhere | G14 | apply A5 to work/board/settings/types |
| E-5 | Transitions on structural change | G16 | `JS.transition` on block insert + tree expand; `prefers-reduced-motion` guard (G18) |
| E-6 | Command-palette match feedback | G10 | highlight matched terms; reflect `assign_async` loading via A1 skeleton |

---

## Recommended build order (dependency-aware)

1. **A (design system)** — everything else consumes it. Start: skeleton,
   button-loading, modal+focus-trap, empty-state, error-card, toast.
2. **B1+B2** — resume conversation + keep panel open. *Smallest change, biggest
   "feels broken → works" jump.* Pure `WorkspaceLive`/`chat_component` shell.
3. **B3 (`MessageKind` registry) + B4** — the structural heart; host seep +
   tool-disclosure. Sets up crystallize coherence.
4. **D-1/D-2** — unify the shell (`Layouts.workspace/1`), kill Phoenix branding.
   Unblocks E-1 (mobile) for free.
5. **B5–B8**, then **C / D / E** as polish waves, each consuming Category A.

## What to extract (structural debt this surfaces)

- **`Concept.Chat.MessageKind`** — message render-mode registry; twin of
  `BlockType`. Kills the inline `sender_kind in [...]` branching.
- **`Layouts.workspace/1`** — one authed shell; kills the `Layouts.app`
  divergence (D-1) and is the single place to add mobile nav (E-1).
- **`core_components` state primitives** (A) — the missing half of the design
  system; the reason loading/empty/error states were never built.
- **A `FocusTrap` + `ScrollToBottom` hook pair** — reused by modal, slide-over,
  record-picker, chat. Build once.

---

## E-1 mobile layout — shipped & verified

Delivered intrinsically as part of `Layouts.workspace/1` (commit `f57f89a`): a
sticky hamburger bar < md, a slide-in drawer wrapping the shared sidebar, and a
scrim that closes on tap (pure client JS, `prefers-reduced-motion` guarded).
Tested in `test/concept_web/components/workspace_shell_test.exs` (mobile
affordances present in the DOM, drawer closed by default). Live-verified at 390px:
`docs/ux/live/SHELL-mobile-closed.png` (drawer off-canvas, hamburger + title bar)
and `docs/ux/live/SHELL-mobile-open.png` (drawer over a dimmed scrim).
