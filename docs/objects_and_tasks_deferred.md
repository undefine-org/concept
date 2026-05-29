# Objects & Tasks — deferred scope ledger

> Companion to [`objects_and_tasks.md`](objects_and_tasks.md). This is the
> living list of everything deferred from the original vision (§14 waves),
> graded for the human-facing thread (2): **board / record-detail UX
> excellence + the seam picker + the structural folding of the editors**.
>
> Status legend: ☐ not started · ◐ partial · ✓ done. Revisit after thread (2)
> lands; thread (1) (full type/workflow editor UI) is tracked here too so it
> is not lost.

Last audited: 2026-05-29 (post Wave 6, post reviewer waves R1–R6 retroactive;
thread (2) W1–W5 shipped + reviewer wave + cast-fix; `mix precommit` green,
512 tests / 0 failures).

**Thread (2) COMPLETE (W1–W5, 2026-05-29):**
- ✓ W1 FieldType render contract + `FieldTypeComponent` dispatcher.
- ✓ W2 Board v2: columns-from-states, generic card fields, assignee avatars,
  preloaded graph (N+1 killed), guard-requirement tooltips.
- ✓ W3 DnD: SortableJS shared-group; cross-column drop reuses the `move` event
  + guard engine; spring-back on rejection.
- ✓ W4 RecordDetail slide-over (Linear-style): generic per-field autosave,
  assignee combobox, guarded moves — closes the proof→review→done loop in-UI;
  record_ref now actor-scoped (C authorize bypass folded).
- ✓ W5 Guard render contract (icon + render_config_form across 4 guards) +
  Tasks nav entry (H folded).
- 511 tests / 0 failures; browser-verified end to end.
- **Remaining (tracked below, NOT in thread 2):** D agent pull-model UI,
  F seeder atomicity, G trade-offs, the record_ref *picker* in the page editor,
  and the full Type/Workflow editor LiveViews (thread 1 — now trivial: compose
  the W1/W5 config-form components).

---

<!-- thread (2) verified complete: see completion stamp above -->

## A. The editors (vision §14 I6) — database-builder thesis

The vision's defining promise: teams customize **schema and rules**. Today a
human cannot create a type, add a field, draw a workflow, or attach a guard
anywhere in the UI. Domain + MCP surface is **complete** (see
`lib/concept/objects.ex` code interface); only the LiveView projections are
missing.

| Item | Status | Note |
|---|---|---|
| ObjectType editor (create/rename, icon/color) | ☐ | `create_object_type`, `rename_object_type` exist |
| FieldDef editor (add/reorder/configure fields) | ☐ | `create_field_def`, `update_field_def`, `reorder_field_def` exist |
| Workflow editor (states + drag transitions + guard palette) | ☐ | full action surface exists incl. `set_transition_guards` |
| Scenario S4 (custom object+workflow) reachable by humans | ☐ | only via MCP / raw Ash today |
| Scenario S5 (custom validation) reachable by humans | ☐ | only via MCP / raw Ash today |

**Structural fold into (2):** the editors are *generic projectors over the
FieldType / Guard registries* (see design doc §"UI as registry projection").
Build the registry-driven field/guard UI seam in (2); the editor LiveViews
then compose those same components. Do not hand-roll per-type widgets.

---

## B. Board UX — below "visual/UX excellence"

| Item | Status | Note |
|---|---|---|
| Assignee shown on cards + assign control | ✓ | W2 avatar + W4 assign combobox |
| Field rendering on cards (priority pill, blocked badge) | ◐ | W2 priority pill via dispatcher; blocked badge still TODO |
| Drag-and-drop moves (not text buttons) | ✓ | W3: SortableJS shared-group; same move action + guard engine |
| Record detail view (open card → edit fields) | ✓ | W4: slide-over; pr_url editable → satisfies requires_proof in-UI |
| Guard-aware move affordance (why a move is blocked) | ✓ | W2/W4: requirements shown inline before the click |
| Empty / loading / error states polish | ◐ | bare empty columns; plain `board_error` sentence; no skeleton |
| `my_records` / `ready_records` views (pull model) | ☐ | actions exist; no UI consumes them |
| Filtering / grouping / sorting | ☐ | board is single fixed grouping (category) |
| `available_moves` N+1 per card per render | ✓ | W2: preloaded graph; `moves_for/2` pure |
| Canceled column always rendered, equal width | ✓ | W2: columns are workflow states, lane layout |

---

## C. The seam (`record_ref`) — half-built (vision §8)

| Item | Status | Note |
|---|---|---|
| record_ref **picker** (set record_id from page editor) | ☐ | structural seam ready (relation render_input); page-editor wiring is a FUP |
| Inline edit (transition/assignee from inside the doc) | ☐ | RecordDetail is the reusable surface; doc-embed is a FUP |
| Assignee shown in the badge | ☐ | badge shows state + title; FUP |
| `load_record` bypasses policy (`authorize?: false`) | ✓ | W4.2: actor-scoped read when current_user present |

---

## D. Agent collaboration (vision §6) — data present, behavior thin

| Item | Status | Note |
|---|---|---|
| Pull-model UI (agent "ready work" surface) | ☐ | `ready_records` exists; nothing consumes it |
| Mark a member as `:agent` in UI | ☐ | role enum has `:agent`; no UI |
| Human vs agent assignee distinction on board | ☐ | — |
| Agent→agent acceptor gap (no human creator) | ☐ | documented §6 trade-off; `requires_approval{by:creator}` can't pass |

---

## E. MCP / discovery (vision §7)

| Item | Status | Note |
|---|---|---|
| Schema-introspection resource (types→fields/states/transitions+guard desc) | ◐ | verify it surfaces `Guard.describe/1` + full transition graph |
| `list_<type>` rich filtering (by field/state/assignee) | ◐ | `object_type_id` pin fixed; filtering breadth unverified |

---

## F. Robustness debts (from reviewer waves R1–R6)

| Item | Status | Note |
|---|---|---|
| Seeder non-atomic (partial half-seed on failure) | ☐ | P3; multi-txn after onboarding; idempotent but no repair |
| `available_moves` / `FilterReady` N+1 | ☐ | P3 |
| No optimistic UI / client keepalive for moves | ☐ | full `load_board` round-trip per action |

---

## G. Vision trade-offs (conscious, re-confirm)

1. Categories fixed forever (6) — value invisible without workflow editor (A).
2. JSONB+GIN not EAV — no cross-field relational queries at scale.
3. "Project = Page" — `Record.page_id` exists; no project→records view.

---

## H. Process / reachability

| Item | Status | Note |
|---|---|---|
| **No nav entry to `/tasks`** | ✓ | W5: Tasks link in workspace sidebar |
| Reviewer waves were retroactive, not interleaved | n/a | §13 contract violated this build; note for future waves |
| Committed with failing tests mid-build | ✓ fixed | now 471/0 |
