# Objects & Tasks — a database builder for human + agent teams

> A task is not a row, a page, a checkbox, and a mention all at once.
> A task is **one entity** with **one home**. Everything else is a *reference*.
> What teams customize is the **schema and the rules** — never the entity's identity.

This document specifies Concept's project-management primitive. It is, at
its foundation, a **runtime database builder**: workspaces define their own
object *types*, *fields*, and *workflows*. **Task** is the first built-in
type — the proof that the engine works — not a special case in the code.

It is the companion design doc to [`mcp_parity.md`](mcp_parity.md). Read
that first: the contract it describes ("every described Ash action is an
agent tool") is what makes this feature usable by agents *by construction*.

---

## 1. The problem, from first principles

Concept is for **human and agent teams working together**. A
project-management system for that audience must satisfy three principles:

1. **Simple** — one mental model that both a human and an agent can hold.
   An agent dropped into any workspace must reason about work **without
   per-workspace configuration**.
2. **Transparent, not redundant** — there is exactly one answer to "where
   is this task?" and exactly one answer to "where do I put this?".
3. **Manageable** — "what is ready, and who is on it?" is answerable in one
   query, for humans *and* for agents pulling work.

### 1.1 Why the Notion model fails these

The expert critique of Notion converges on one root cause: **flexibility
without identity.** Notion has no opinion about what a task *is*, so:

- a task is simultaneously a page, a database row, a checkbox, and an
  `@`-mention — the same work lives in N places, none canonical
  (the "relations trap"; redundancy by construction);
- "committed work" and "someday-idea" are the same visual object — the
  backlog becomes noise no one trusts;
- there is no native notion of *ready* / *blocked* / *who owns it* as a
  queryable set — "what's next?" is unanswerable at scale.

The disease is **not** customization. It is customization **without a
strong-identity content layer underneath it.** This design keeps total
customization of *schema and rules* while making the *entity* canonical.

### 1.2 What OpenAI Symphony teaches

[Symphony](https://github.com/openai/symphony) orchestrates coding agents
against an issue tracker. Three lessons carry directly:

- **The tracker is the single source of truth.** Agents do not get
  push-assigned; they **poll** for eligible work, claim it, execute.
- **Success ≠ Done.** A run ends at a *handoff state* (e.g. "Human
  Review"), attaching **proof of work** (CI, PR, walkthrough). A human
  accepts.
- **"Manage the work, not the workers."** The unit of management is the
  task and its state, not the agent.

These become, respectively: a queryable `Record` set; a `category: :review`
state gated by a **guard**; and a workflow whose transitions encode the
acceptance rules.

---

## 2. The core decision: Records are entities, Blocks are content

Concept already has a runtime-typed, JSONB-payload, registry-dispatched
content primitive: the **Block** (`Concept.Pages.Block` +
`Concept.Pages.BlockType`). The natural question is: *why aren't objects
just block types?*

They share a **mechanism** but differ in **identity model**, and identity
is the entire point.

| Axis | **Block** (content) | **Record** (entity) |
|---|---|---|
| Identity | positional — exists *at a spot* in one page's tree | canonical — exists independent of any page |
| Cardinality | exactly one home (`page_id` not null); deleting the page deletes it | 0..N placements; survives any page |
| Addressability | found by walking a page tree | found by querying a **set** (`SELECT … WHERE assignee = me ∧ category = :todo`) |
| Lifecycle | content edits + collaborative locks | **state machine** with guarded transitions + acceptance |
| Reference | *is* the content | is *referenced by* content |

The decisive test is the agent's primary question — *"what is ready and
mine across the whole workspace?"* A block type **cannot** answer it:
blocks live in page trees, not sets. Crawling every page's block tree to
find tasks **is** the Notion failure mode. A `Record` answers it with one
indexed query.

So the relationship is two layers with an explicit seam:

```
  Record  — queryable entity, identity + lifecycle      (the "tracker")
    ▲
    │  task_ref block  →  { record_id }                 (the SEAM)
    │
  Block   — page-bound content, type-dispatched         (the "document")
```

A document **mentions** a record by embedding a `task_ref` block holding
`record_id`; the block renders the record's *live* state. The entity lives
in one set; documents hold references. **This is what structurally kills
redundancy** — there is nothing to duplicate, only to reference.

### 2.1 What we reuse (the rhyme pays off)

We do **not** reinvent the type machinery. The Block stack is lifted one
level to drive the *meta* layer:

| Block stack (exists) | Object stack (new) | Relationship |
|---|---|---|
| `BlockType` `@behaviour` + registry | `FieldType` + `Guard` `@behaviour` + registries | same pattern, dev-extensible vocabulary |
| `Block.Changes.ValidatePropsForType` | `Record.Changes.ValidateFieldsForType` | the *same* "validate JSONB bag vs type config" change, generalized |
| `BlockTypeAttr` (custom Ash type) | `CategoryAttr` etc. | same technique |
| `AshStateMachine` on Block (locks) | transition engine on Record | state, generalized to user-defined graphs |
| `config :concept, :block_types` | `config :concept, :field_types` + `:record_guards` | same registry idiom |

We share the **engine**; we keep two **identity models**; the **seam** is
the `task_ref` block. That is the harmonious answer.

---

## 3. The two-layer lifecycle (customization + agent-legibility together)

The hardest tension: **users want custom workflows**, but **agents must
reason about state without learning each workspace's vocabulary.** These
look opposed. They are not. Resolve by splitting the lifecycle into two
layers — the same resolution Linear, Jira, and GitHub Projects each reached
independently:

```
  CUSTOM layer  (users own):   named States, any count, per workflow
       "Backlog" "Up Next" "In Dev" "Code Review" "QA" "Shipped" "Won't Do"
                              │  every State declares exactly one ↓
  FIXED layer   (agents own):  CATEGORY  ∈ closed set
       :backlog → :todo → :doing → :review → :done → :canceled
```

- **States are open.** Users add/rename/reorder them freely.
- **Categories are closed.** Six, fixed forever, in code.
- **Invariant (load-bearing):** every `WorkflowState` MUST map to exactly
  one category.

Agents bind to **categories**, never to state names:

```
  ready?(record) := category(state) == :todo
                  ∧ ∀ b ∈ blocked_by(record): category(state(b)) == :done
                  ∧ assignee == nil
```

`"review = needs acceptance"` holds whether the team calls that state "QA"
or "Sign-off". The fixed contract moved **up** from `status` to `category`.
That single move buys total customization *and* universal legibility.

---

## 4. Resource model

Three layers: **meta** (the schema, user-authored as rows), **data** (the
records), **registries** (the dev-extensible vocabulary, compile-time).

All workspace-scoped resources `use Concept.Resources.WorkspaceTenanted`
(multitenancy by `workspace_id`, member-read floor, `system?`-actor bypass)
and follow the existing archival + paper-trail conventions.

### 4.1 Meta layer

```
ObjectType            workspace_id, name, key, icon, color
                      workflow_id → Workflow
                      is_system?  (Task seeds one; built-ins are not deletable)
                      position

FieldDef              object_type_id, name, key, position
                      field_type : atom (registry key: :text|:number|:select|
                                   :date|:user|:relation|:checklist|:url …)
                      required?  : boolean
                      config     : map (JSONB; e.g. select options, relation target type)

Workflow              workspace_id, name
                      has_many :states, :transitions

WorkflowState         workflow_id, name (custom), position
                      category : :backlog|:todo|:doing|:review|:done|:canceled   ← FIXED
                      is_initial? : boolean

Transition            workflow_id, from_state_id, to_state_id
                      guards : list(map)   (JSONB; [%{kind, config}], see §5)
```

### 4.2 Data layer

```
Record                workspace_id, object_type_id
                      state_id → WorkflowState   INVARIANT: state ∈ object_type.workflow.states
                      fields  : map (JSONB; validated against the type's FieldDefs)
                      title   : string  (a designated display field, denormalized for lists)
                      assignee_id   → User, nullable   (human OR agent — same field, §6)
                      created_by_id → User             (relate_actor; acceptor of agent work)
                      page_id → Page, nullable         ("project" = a Page with records)
                      position : fractional index

RecordLink            workspace_id, from_record_id, to_record_id
                      field_def_id → FieldDef   (which relation/which edge; blocked_by is one)
```

**Field storage is a validated JSONB bag** (matching the `Block.content` /
`Block.props` grain), **except relations**, which are first-class
`RecordLink` rows. Rationale:

- JSONB + GIN indexing handles per-field filter/sort (board grouped by a
  select field) without a table per field;
- relations as rows give real referential edges — `blocked_by`,
  `relation`-typed fields, and graph queries all route through `RecordLink`
  (joins), never through JSONB;
- `ready?` derives from `RecordLink` (blockers) + `state.category`.

> **Trade-off — JSONB vs EAV.** EAV (a `FieldValue` row per value) buys
> first-class per-field indexing and constraints at the cost of N joins per
> record and two more resources. JSONB+GIN is leaner, matches existing
> precedent, and is sufficient for workspace-scale datasets. We choose
> JSONB+GIN; revisit only if a workspace needs cross-field relational
> queries at a scale GIN can't serve.

### 4.3 Registries (developer plane, compile-time)

```elixir
# config/config.exs
config :concept, :field_types,   [Concept.Objects.FieldTypes.Text, …]
config :concept, :record_guards, [Concept.Objects.Guards.RequiresApproval, …]
```

`FieldType` behaviour (mirrors `BlockType`):

```elixir
@callback key :: atom
@callback validate(value :: term, config :: map) :: :ok | {:error, term}
@callback default(config :: map) :: term
@callback cast(input :: term, config :: map) :: {:ok, term} | {:error, term}
```

New field type = new module + one registry line + a contract test. Exactly
the `ADDING_A_BLOCK.md` ergonomics, for fields.

### 4.4 Task as a seeded type (not a resource)

There is **no `Task` module.** On workspace creation (extend the existing
`Accounts.Reactors.Onboarding`), seed:

- an `ObjectType` `"Task"` (`is_system? true`) with built-in `FieldDef`s
  (`priority` select, `blocked_by` relation);
- a default `Workflow` "Default" with states **Backlog→Todo→Doing→Review→
  Done** (+ **Canceled**) mapped to the matching categories;
- a `→ Done` transition carrying a `RequiresApproval{by: :creator}` guard
  (Symphony's accept gate, expressed as data).

Out of the box this *feels* like a fixed 5-state task system — but it is
already the generic engine, with zero migration debt when users start
editing.

---

## 5. Transition guards — the validation engine

> Requirement: **declarative transition guards in v1** — requires-proof,
> requires-approval, requires-checklist-complete — represented in a way
> that fits Ash/Spark leanness and extensibility.

Two extensibility planes, deliberately separated:

**Developer plane (compile-time, behaviour + registry): the guard vocabulary.**

```elixir
defmodule Concept.Objects.Guard do
  @callback kind :: atom
  @callback check(record :: map, config :: map, context :: map) ::
              :ok | {:error, reason :: String.t()}
  @callback describe(config :: map) :: String.t()   # ← agent/UI legibility
end
```

Built-in guards (each a module, registered in config):

| `kind` | gate | `config` |
|---|---|---|
| `requires_approval` | actor must be `:creator` / `:owner` / a named role | `%{by: :creator}` |
| `requires_proof` | a designated field must be present/non-empty | `%{field: "pr_url"}` |
| `requires_checklist_complete` | a checklist field has all items checked | `%{field: "acceptance"}` |
| `requires_fields` | listed fields non-empty before leaving a state | `%{fields: [...]}` |

**User plane (runtime, rows): the guard composition.** A `Transition` row
carries `guards: [%{kind: "requires_approval", config: %{by: :creator}}, …]`.

**The engine is one Ash action + one Change** — mirroring how
`RequireOwnLock` and `ValidatePropsForType` already gate `Block` updates:

```elixir
# Record action
update :transition do
  description "Move a record to a new workflow state, enforcing the transition's guards."
  argument :to_state_id, :uuid, allow_nil?: false,
    description: "Target workflow state. Must be reachable from the current state."
  accept []
  require_atomic? false
  change Concept.Objects.Record.Changes.RunTransition
end
```

```
RunTransition (before_action):
  1. resolve transition (record.state_id → to_state_id) in the workflow graph
       ∄ transition  → add_error "no transition from <from> to <to>"
  2. ∀ g ∈ transition.guards:
       mod = registry[g.kind]; mod.check(record, g.config, ctx)
       {:error, r} → add_error r   (collect all; report together)
  3. ok → set_attribute(:state_id, to_state_id)
```

Why **interpret** the graph rather than express it in a Spark DSL: Spark is
compile-time; transitions and their guards are **user data**. So the graph
must be rows. Spark/behaviour earns its keep for the *guard vocabulary*
(developers); runtime rows carry the *graph + composition* (users). Right
tool, right plane — and `Guard.describe/1` keeps the composed rules legible
to both the editing UI and agents.

---

## 6. Assignment: humans and agents are the same field

**Agents are already Users in this codebase** (`AiAgentActorPersister`
stores an agent as a `%User{}` with `chat_agent?` metadata; `ApiKey` is
workspace-bindable). So an "agent" is a **User holding a workspace-scoped
Membership**, flagged by role.

- `Membership.role` gains `:agent` (alongside `:owner | :member`).
  Agent-ness is **per-workspace** — matching the chosen "dedicated
  service-user per workspace" model. (Note: `Scope`'s typespec already
  lists an `:admin` role the `Membership` enum lacks; reconcile the role
  set when touching this — pre-existing, out of scope here.)
- `Record.assignee_id → User`, uniformly. One foreign key; existing
  `WorkspaceMember` policies apply unchanged; an agent gets exactly its
  membership's permissions.

**Two assignment motions, both supported:**

- **Push** — a human calls `assign(record, user_id)` then `transition`
  into a `:doing` state ("do this one, @agent").
- **Pull** — an agent calls `ready_records(type)` (category `:todo`,
  unblocked, unassigned, optional skill/kind filter), then claims one.
  This is the Symphony model and the reason the whole system works for
  agent swarms.

**Acceptance.** Agent work lands in a `:review`-category state via a
`requires_proof` guard, then a human advances `→ :done` gated by
`requires_approval{by: :creator}`. `created_by_id` is the acceptor — **no
separate `owner` field.**

> **Trade-off — `created_by` as acceptor.** Edge case: a record created by
> an agent *and* executed by an agent has no human acceptor. v1 answer: a
> `requires_approval{by: :creator}` guard simply won't pass for a non-human
> creator, so such a record routes to a human before `:done`. Acceptable
> for "teams working together"; revisit for fully autonomous agent→agent
> chains.

---

## 7. MCP surface — generic spine + per-type dynamic tools

The CI-enforced parity contract (`AGENTS.md` #1) says every described
action is an agent tool. Records-as-rows means typed tools cannot all come
from the compile-time `AutoTools` transformer (object types are runtime
data). **Two composed sources:**

**(A) Generic spine — compile-time, free via `AutoTools`.** Described
actions on `Record`/`ObjectType`/`Workflow`: `record_create`,
`record_transition`, `record_assign`, `record_link`, `record_list`,
`record_ready` — plus schema reads. Available the moment the actions exist.

**(B) Per-type dynamic tools — runtime projector (chosen for v1).** A
projector reads `ObjectType` + `FieldDef` + `Workflow` per workspace and
synthesizes **typed** tools so that *"user invents `Customer` → agent
immediately gets `create_customer`"* is true:

- `create_<type>(<typed fields from FieldDefs>)`
- `<type>_transition(record_id, to: <state names>)` — descriptions carry
  `Guard.describe/1` output so the agent sees *"→Done requires creator
  approval"*
- `list_<type>(filter by field / state / assignee)`

```
  ObjectType + FieldDef + Workflow (rows, per workspace)
        │  Concept.Objects.ToolProjector  (runtime)
        ▼
  [%AshAi.Tool{name: "create_customer", schema: …, description: …}, …]
        │  merged with AutoTools generic spine + manual tools
        ▼
  MCP tools/list  (per-workspace, tenant-resolved by MCPWorkspaceContext)
```

**Feasibility (verified against the installed `ash_ai`).** The MCP server
resolves `tools/list` *and* `tools/call` through `AshAi.exposed_tools/1`,
which reads only the **compile-time** domain DSL (`AshAi.Info.tools/1`);
router options are static, and `extra_tools` exists only on the LLM prompt
path, not the MCP server. Therefore the dynamic projector is **not a config
flip** — it requires a thin **custom MCP router/server wrapper** that runs
the projector per request (keyed on the tenant `MCPWorkspaceContext` already
resolves) and merges the synthesized `%AshAi.Tool{}`s into the tool list for
both `list` and `call`. The seam is clean: `tools/0` inside
`AshAi.Mcp.Server` is the single chokepoint for both paths. Precedent:
Symphony ships `dynamic_tool.ex` (per-issue dynamic tools); AshAi's `Tool`
struct is the target format. This is net-new infrastructure and is the
highest-risk item in the build (see §12, Wave 4).

> Parity is preserved, reframed: parity guarantees **same policies, same
> data, same behavior** for human and agent — guards run identically inside
> `transition` for both. The dynamic projector additionally restores
> **typed tool granularity** so agents see workspace-specific verbs, not
> only the generic spine. A schema-introspection MCP **resource**
> (`list_object_types` → fields, states, valid transitions + guard
> descriptions) complements the tools so agents can discover before acting.

---

## 8. The seam: the `task_ref` (record_ref) block type

One new block type, registered per `docs/blocks/ADDING_A_BLOCK.md` (one
registry line, zero dispatcher edits):

- `props: %{record_id}`; renders the record's **live** title, state (by
  category color), and assignee;
- editing status/assignee from inside a doc calls the same `Record`
  actions — one truth, many views;
- this is the projection that lets any page, brief, or roadmap *mention* a
  record without copying it.

---

## 9. Scenario walk-throughs (validation)

**S1 — a thought becomes work.** "Support SSO eventually" and "signup is
broken now" are both captured instantly as `Record`s in a `:backlog` state
— zero taxonomy decision at capture. Promoting "signup" to a `:todo` state
is the single commitment act. The category line (`:backlog` vs `:todo`)
separates noise from work. *Capture is cheap; clarify later.*

**S2 — where does a task live?** "Redesign Acme logo" is one `Record`.
The Acme page, the Q3 roadmap, and a designer's view all hold `task_ref`
blocks → same `record_id`, all rendering live state. One flip updates every
surface. *One truth, many views.*

**S3 — human or agent?** 30 ready records, 1 human, 6 agents. Agents call
`ready_records` and claim; the human pushes a specific one to a specific
agent via `assign`. Agent finishes → `:review` (proof guard) → human
accepts → `:done` (approval guard). *Push and pull, one gate.*

**S4 — custom object, custom workflow.** A team defines a `Customer`
ObjectType with fields (ARR, tier, owner) and a workflow
(Lead→Trial→Active→Churned). The agent immediately gets `create_customer`
and `customer_transition`. *The database builder, working end to end.*

**S5 — custom validation.** "Bugs can't reach Done without a linked PR and
QA sign-off." Two guards on the `→Done` transition: `requires_proof{field:
pr_url}` + `requires_approval{by: qa_role}`. *Validation workflow as data.*

---

## 10. How the three principles are satisfied — structurally

| Principle | Mechanism |
|---|---|
| **Simple** | agents bind to **6 fixed categories**, valid in every workspace; one entity, one home; customization confined to a config layer above a strong-identity content layer |
| **Transparent / non-redundant** | one `Record` = one id = one home; documents hold `task_ref` references, never copies — duplication is structurally impossible |
| **Manageable** | `ready_records` / `my_records` are single indexed queries; `:review` is the universal human gate on agent output; push *and* pull assignment |

---

## 11. Trade-offs accepted (summary)

1. **Categories are fixed forever.** Teams customize state *names* and the
   *set*, never the six semantic buckets. This is the price of universal
   agent-legibility — and it is what Notion never had.
2. **`created_by` doubles as acceptor** (no `owner` field). Autonomous
   agent→agent chains need a follow-up.
3. **JSONB+GIN, not EAV.** Lean and precedented; revisit only at
   cross-field relational scale.
4. **"Project = Page."** A project and its brief are the same object;
   free-floating records (`page_id = nil`) cover the project-less case.
5. **Platform scope.** This is an Airtable/Linear-class primitive with Task
   as its first app — larger than a PM feature, delivered in waves (§12).

---

## 12. Dynamic MCP tools — how, without codegen

The per-type tool requirement (§7) looks like it needs either a runtime
"DSL writer" (generate + compile an Ash resource per `ObjectType`) or some
built-in framework feature. **Both are wrong**, and the installed `ash_ai`
source says why:

- `AshAi.Tool.Schema.for_tool/1` derives a tool's JSON schema **from a real
  action** on a **real resource** (`action.accept`, `action.arguments`).
  There is no free-floating "typed tool" — a `%AshAi.Tool{}` always points at
  `{resource, action}`.
- Runtime resource codegen (a module per type per workspace, recompiled on
  every schema edit) means module explosion and hot-recompilation races in
  prod. **Rejected.**

**The approach: one generic resource + runtime projection + a thin wrapper.**

```
  Compile-time (real, TDD-able):
    Concept.Objects.Record  with generic actions :create, :transition, :list

  Runtime projection (data → data, NO codegen):
    ToolProjector.project(object_type, field_defs, workflow) :: [%AshAi.Tool{}]
      for each ObjectType, emit a tool that POINTS AT the generic action but:
        name:        "create_customer"           (rewritten from generic)
        resource:    Concept.Objects.Record       (real)
        action:      :create                       (real)
        description: built from FieldDefs + Guard.describe/1   (per type, runtime)
        action_parameters / arguments: pin object_type_id, shape the fields
      (↑ %AshAi.Tool{} already carries `action_parameters` + `arguments`, so a
       per-type typed surface needs NO per-type action.)

  Thin MCP wrapper:
    `tools/0` in AshAi.Mcp.Server is the SINGLE chokepoint for both tools/list
    and tools/call. A custom Server/Router wrapper injects the projected tools
    there, keyed on the tenant MCPWorkspaceContext already resolves per request.
```

No DSL writer. No runtime compilation. Tools stay derived-from-actions, so
the entire dynamic surface is **pure-function testable without an LLM**:
`project/3` is a pure function; `:create`/`:transition` are ordinary action
tests; the wrapper is one integration test (seed type → `tools/list` → assert
`create_customer` schema → `tools/call` → row created).

## 13. Process model (applies to every wave)

This build runs on the **main thread** (no isolated worktrees). Every
implementation wave is bracketed by a **reviewer wave** and closed by a
**mid-flight report**.

**Dual verification — both required, neither sufficient alone:**

1. **TDD (red→green)** — write the failing test first, for every wave. The
   engine is designed to make this possible: pure functions (`ToolProjector`,
   guards), standard Ash action tests (resources, transitions), and the
   existing `mcp_parity_test.exs` harness (MCP). No wave is "done" on
   compilation — only on green tests that encode the behaviour.
2. **Manual browser testing** — once a wave has UI or an observable surface,
   exercise it in the browser (`puppeteer` against the running app). Compiling
   and passing unit tests is necessary but not sufficient: the human-facing
   projection must be verified by interaction (capture a record, drag a
   transition, watch a `record_ref` block re-render live).

**Reviewer waves (interleaved).** After each implementation wave and before
the next begins, a review pass (`reviewer` agent) audits the wave's diff for
correctness, policy/tenancy holes, LiveView purity (EX9001), and contract
drift. The next implementation wave does not start until review findings are
resolved or explicitly deferred.

**Mid-flight report (between every wave).** A short written report carrying:

- **Work done** — what landed, with the tests that prove it.
- **Work to be done** — what the next wave assumes from this one; open risks.
- **Process learnings** — what the codebase taught us (surprises, dead ends,
  patterns to reuse), so later waves and future sessions inherit it.

**Wave gate.** Each wave ends green against `mix precommit` (Credo
LiveView-purity EX9001, MCP surface drift, tests) **and** carries its
reviewer sign-off **and** its mid-flight report before the next wave starts.

## 14. Build sequence (waves)

Implementation waves (I) are interleaved with reviewer waves (R); each pair
emits a mid-flight report.

1. **I1 Engine core** — meta + data resources, `WorkspaceTenanted`, JSONB
   field validation Change, `FieldType` registry + built-in field types.
   *(R1 → report)*
2. **I2 Workflow + guards** — `Workflow`/`WorkflowState`/`Transition`, the
   `RunTransition` engine, `Guard` registry + built-in guards, category
   invariant. *(R2 → report)*
3. **I3 Task seed** — onboarding seeds the Task ObjectType + default workflow;
   `ready_records` / `my_records` reads. *(R3 → report)*
4. **I4 MCP** — generic spine via `AutoTools`; runtime `ToolProjector`
   (§12); thin MCP wrapper; schema-introspection resource; parity test
   extension. *(R4 → report)*
5. **I5 Seam** — `record_ref` block type (live render). *(R5 → report)*
6. **I6 UI** — Tasks list + board-by-category; ObjectType/field editor;
   workflow editor (states + drag transitions + guard palette). *(R6 → report)*
