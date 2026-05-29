# Objects & Tasks — UX layer, structurally

> Thread (2): board / record-detail / seam UX excellence. Companion to
> [`objects_and_tasks.md`](objects_and_tasks.md) (the model) and
> [`objects_and_tasks_deferred.md`](objects_and_tasks_deferred.md) (the ledger).
>
> **Thesis.** The UX layer must be a *projection of the registries*, exactly
> as `ConceptWeb.BlockRender` is a projection of the `BlockType` registry and
> the `BlockType.Interactive` macro colocates a block's data + validation +
> render + MCP tools in one module. We do **not** hand-roll per-type widgets,
> per-guard forms, or a bespoke board. We extend `FieldType` and `Guard` into
> full vertical slices, then every human surface (card, detail, type editor,
> workflow editor) and the DnD interaction fall out as generic projectors over
> those registries. One new field type or guard → its UI appears everywhere,
> for free, by construction. This is the same win as `ADDING_A_BLOCK.md`.

---

## 0. The structural diagnosis

Today the object layer mirrors the block layer's *data* discipline but not
its *UI* discipline:

```
  BlockType   = data + validate + RENDER + slash-menu + MCP  → one module, all surfaces
  FieldType   = data + validate + cast + json_schema          → HEADLESS (no UI)
  Guard       = check + describe + label                      → HEADLESS (no UI)
```

So a board/detail/editor built now would hand-write a `case field_type do`
ladder in HEEx — the exact anti-pattern `block_render.ex` forbids ("never
edit the dispatcher to add a type"). The fix is to give `FieldType` and
`Guard` a **render contract**, then build dispatchers that route on it.

This single move folds in **A** (editors), most of **B** (card/detail
fields, guard-aware affordances), **C** (seam inline edit), and **E**
(discovery) — because all four are the *same* registry projection viewed
through different frames.

---

## 1. FieldType becomes a vertical slice (render contract)

Add presentation + input callbacks to `Concept.Objects.FieldType`, mirroring
how `BlockType` owns `render/1` and `slash_menu/0`:

```elixir
# new @callbacks on Concept.Objects.FieldType
@callback render_value(value :: term, config :: map, assigns :: map) :: Phoenix.LiveView.Rendered.t()
@callback render_input(field_def :: map, value :: term, form_field :: Phoenix.HTML.FormField.t()) :: Phoenix.LiveView.Rendered.t()
@callback render_config_form(config :: map, form :: Phoenix.HTML.Form.t()) :: Phoenix.LiveView.Rendered.t()
@callback icon() :: String.t()
# render_config_form optional — most types have no config (text, date, url)
```

- `render_value/3` — read-only display (card pill, detail row, record_ref
  badge). `:select` renders a colored chip; `:user` renders avatar+name;
  `:relation` renders linked record chips; `:checklist` a progress bar.
- `render_input/3` — the edit control (detail view, create form). `:select`
  → `<select>` from `config["options"]`; `:user` → member combobox;
  `:date` → date input; `:relation` → record picker (same component the
  `record_ref` seam uses — see §4).
- `render_config_form/2` — the field's **own** settings UI in the type
  editor (e.g. `:select` edits its option list). This is what makes the
  **ObjectType/FieldDef editor generic** (folds **A**): the editor renders
  `field_type.render_config_form/2` and never branches on the type.

A new `FieldTypeComponent` function component is the single dispatcher:

```elixir
# ConceptWeb.Objects.FieldTypeComponent  (mirrors BlockRender)
def value(assigns), do: registry(assigns.field_def.field_type).render_value(...)
def input(assigns), do: registry(assigns.field_def.field_type).render_input(...)
def config_form(assigns), do: registry(assigns.field_def.field_type).render_config_form(...)
```

> Wiring guarantee (same as blocks): adding a field type = one module + one
> registry line; its display, its input, and its type-editor config UI all
> appear automatically. No edit to any LiveView.

---

## 2. Guard becomes a vertical slice (palette + affordance)

Add to `Concept.Objects.Guard`:

```elixir
@callback render_config_form(config :: map, form :: Phoenix.HTML.Form.t()) :: Phoenix.LiveView.Rendered.t()
@callback icon() :: String.t()
# label/0 + describe/1 already exist
```

- `render_config_form/2` makes the **workflow-editor guard palette generic**
  (folds **A**): the editor lists `Guards.all()`, renders each one's config
  form, and writes `%{kind, config}` rows via `set_transition_guards`. Zero
  per-guard branching.
- `describe/1` (exists) is reused three ways: workflow editor labels, MCP
  tool descriptions (exists), **and the board's guard-aware move affordance**
  (folds **B**): a move button shows *why* it's gated *before* the click, via
  a `requirements/2` projection (see §3).

---

## 3. The board + DnD — one structural interaction

### 3.1 DnD is the blessed SortableJS-shared-group pattern

Repo precedent already exists: `assets/js/hooks/block_list.js` uses
SortableJS for in-list reorder. A board is the **cross-list** variant —
SortableJS's documented `group` option lets items drag *between* columns:

```js
// assets/js/hooks/task_board.js  (new; mirrors block_list.js structure)
new Sortable(columnEl, {
  group: "task-board",            // shared → drag across columns
  handle: ".task-card",
  animation: 150,
  ghostClass: "task-drag-ghost",
  onEnd: (evt) => {
    const recordId   = evt.item.dataset.recordId;
    const toStateId  = evt.to.dataset.stateId;     // target column carries its state id
    const fromStateId= evt.from.dataset.stateId;
    if (toStateId === fromStateId) return;          // intra-column = no-op (no reorder semantics yet)
    this.pushEvent("move", { record: recordId, to: toStateId });
  }
});
```

**The decisive structural point:** the drop handler pushes the **same
`"move"` event the existing buttons push** → same `Objects.transition_record`
→ **same guard engine**. DnD adds *zero* new server authority; it is a second
input device for the one transition action. Guard rejection → the card
**springs back** (LiveView re-renders authoritative state; Sortable's DOM
move is overwritten by the diff) + flash. No optimistic-state divergence
because the server is the single source of truth.

> This is why we keep buttons too: DnD is the rich affordance, buttons are
> the accessible + keyboard + agent-legible fallback. Both invoke one action.

### 3.2 The board renders columns from `WorkflowState`, not the fixed category list

Today `tasks_live.ex` hardcodes `@columns [:backlog,…]`. Structural fix: the
board's columns **are the workflow's states** (ordered), each tagged with its
category for color/agent-legibility. This folds the "Canceled always shown"
noise (**B**) and makes the board correct for *any* workflow — the same board
renders a `Customer` Lead→Trial→Active board with no code change. Each column
`<div data-state-id={state.id}>` so DnD knows the target.

### 3.3 Cards render fields generically

Card = title + `FieldTypeComponent.value` for each FieldDef flagged
`show_on_card?` (new optional FieldDef attribute; defaults: title + select +
user) + assignee avatar (folds **B** assignee gap) + a blocked badge derived
from `blocked_by` RecordLinks. No per-type HEEx.

### 3.4 `available_moves` N+1 fixed (folds **F**)

Compute the transition graph **once per board load** (one
`list_transitions(workflow_id)`), then map in-memory per card. `task_board/1`
returns `%{type, states, columns, transitions}`; `available_moves` becomes a
pure function over that preloaded graph. Add `requirements(transition)` =
`Enum.map(guards, &Guard.describe/1)` for the guard-aware affordance (§3.2 B).

---

## 4. Record detail + the seam picker — one component (folds C)

A `RecordDetail` LiveComponent renders, generically:

- every FieldDef via `FieldTypeComponent.input` (edit) / `.value` (read),
  saving through `update_record_fields`;
- assignee combobox → `assign_record`;
- state + `available_moves` (with guard requirements shown) → `transition_record`;
- this is the surface where a human **fills `pr_url`** to satisfy a
  `requires_proof` guard, then transitions — closing the §6 acceptance loop
  that is currently impossible in-browser.

**The seam picker reuses the `:relation` `render_input`** — the record_ref
block's "choose a record" picker and a relation field's picker are the *same
component*. Opening a card (board) and opening a record_ref target (doc) mount
the *same* `RecordDetail`. One truth, many frames — structurally, not by
convention.

`record_ref` render gains assignee + (optionally) inline transition by
embedding the read projection of `RecordDetail`; its `authorize?: false`
read (**C**) is replaced with the actor-scoped read now that it renders in an
authenticated LiveView context.

---

## 5. What each deferred item this folds

| Deferred | Folded by | How |
|---|---|---|
| **A** editors | §1 `render_config_form` (field) + §2 (guard) | editors are generic projectors over the same render contracts |
| **B** assignee/fields on cards | §3.3 | `FieldTypeComponent.value` + assignee avatar, no branching |
| **B** DnD | §3.1 | SortableJS shared-group → same `move` action + guard engine |
| **B** guard-aware affordance | §2 `describe` + §3.4 `requirements` | shown before click |
| **B** record detail | §4 | generic field inputs |
| **B** N+1 | §3.4 | preload transition graph once |
| **B** Canceled-noise / any-workflow | §3.2 | columns = states |
| **C** seam picker | §4 | `:relation` `render_input` reused |
| **C** inline edit / assignee in badge | §4 | record_ref embeds RecordDetail read projection |
| **C** authorize bypass | §4 | actor-scoped read in LV context |
| **E** discovery surfaces guard desc | §2 | `describe/1` already feeds MCP; now also UI |
| **F** N+1 | §3.4 | — |
| **H** nav entry | §6 | add Tasks link to workspace shell |

Remaining (not folded; tracked in ledger for later): **D** agent pull-model
UI, **F** seeder atomicity, **G** trade-offs, EAV.

---

## 6. Build order (thread 2), TDD + browser per the §13 process

Each wave: red→green tests, then browser pass, then a short report.

1. **W1 — FieldType render contract.** Add callbacks + `FieldTypeComponent`
   dispatcher; implement `render_value`/`render_input` for all 8 types +
   `render_config_form` where applicable. Pure-component tests per type.
2. **W2 — Board v2.** Columns-from-states; generic card fields; assignee
   avatars; preload transition graph (kill N+1); guard-requirement tooltips.
   LiveView tests.
3. **W3 — DnD.** `task_board.js` shared-group hook; `move` reuse; spring-back
   on guard rejection. JS unit test (mirror `block_list.test.js`) + LV test
   that the dropped `move` event transitions.
4. **W4 — RecordDetail + seam picker.** Generic detail LiveComponent;
   `:relation` picker; wire record_ref to it; replace `authorize?: false`.
   Closes the proof→review→done human loop. Tests.
5. **W5 — Guard render contract + nav.** `Guard.render_config_form`; add the
   Tasks nav entry to the workspace shell (**H**). Tests.
6. **(thread 1 follow-on) — Type + Workflow editors.** Now trivial: compose
   the §1/§2 config-form components. Filed separately; the seams it needs all
   exist after W1–W5.

Gate per wave: `mix precommit` green (EX9001 LiveView purity — all data via
`Concept.Objects` code interface; field/guard render fns are pure components,
no Ash in `live/`), reviewer sign-off, report.
