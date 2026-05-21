# Adding a Block Type

Concept's block system is a registry of `Concept.Pages.BlockType`
implementations. Each block type is a single module that owns its full
vertical slice: schema, validation, render, slash-menu entry, and (when
interactive) its event handlers.

This document covers the three flavors you'll write in practice:

1. **Static block** — non-interactive (divider, image, equation, bookmark).
2. **Text block** — Lexical-edited (paragraph, heading, to-do). *Legacy
   path; not yet macro-fied. See "Text blocks today".*
3. **Interactive block** — runs as a `Phoenix.LiveComponent` with
   server-side event handlers (AI Answer).

The wiring guarantee: **if it compiles, it works.** You cannot forget to
register a JS hook, define a LiveView event handler, or wire a `phx-target` —
those are produced by the macros from a single source of truth.

---

## 1. Static block (the common case)

A static block renders some HEEx and that's it. No clicks, no events.

### Skeleton

```elixir
# lib/concept/pages/block_types/divider.ex
defmodule Concept.Pages.BlockTypes.Divider do
  use Concept.Pages.BlockType.Static

  @impl Concept.Pages.BlockType
  def type, do: :divider

  @impl Concept.Pages.BlockType
  def lexical_node, do: "divider"

  @impl Concept.Pages.BlockType
  def slash_menu,
    do: %{label: "Divider", icon: "—", keywords: ["divider", "hr"], group: :media}

  # The render contract. Receives the dispatcher assigns (`@block`,
  # `@locked_by`, `@locked_blocks`, `@current_user`).
  def render(assigns) do
    _ = assigns
    ~H'<hr class="border-notion-divider my-2" />'
  end
end
```

`use Concept.Pages.BlockType.Static` provides:

- `@behaviour Concept.Pages.BlockType`
- `use Phoenix.Component` (so `~H` is in scope)
- defaults for `default_content/0`, `default_props/0`, `validate_props/1`,
  `container?/0`, `live_component?/0` — all overridable
- a `render_static/1` bridge for the legacy callback name

### Register

```elixir
# config/config.exs
config :concept, :block_types, [
  ...,
  Concept.Pages.BlockTypes.Divider
]
```

That's the whole loop. No `block_render.ex` edit. No JS. No tests required
to compile.

### Per-type overrides

Override only what you need. Anything you don't define is supplied by the
macro:

```elixir
@impl Concept.Pages.BlockType
def default_props, do: %{"url" => "", "alt" => "", "aspect_ratio" => nil}

@impl Concept.Pages.BlockType
def validate_props(%{"url" => url}) when is_binary(url), do: :ok
def validate_props(_), do: {:error, "missing url"}
```

---

## 2. Interactive block (AI Answer is the reference)

Interactive blocks run as `Phoenix.LiveComponent`s and accept events from
their inner Lit web component. The `Interactive` macro generates the
LiveComponent boilerplate, one `handle_event/3` clause per declared event,
and a render wrapper that already includes `phx-hook="OraBlock"` +
`data-events` matching your declarations.

### Skeleton

```elixir
# lib/concept/pages/block_types/ai_answer.ex
defmodule Concept.Pages.BlockTypes.AiAnswer do
  use Concept.Pages.BlockType.Interactive,
    ash_actions: [
      evaluate: [Concept.Pages, :evaluate_ai, [:prompt, :scope, :profile]],
      refresh:  [Concept.Pages, :evaluate_ai, [:prompt, :scope, :profile]],
      retry:    [Concept.Pages, :evaluate_ai, [:prompt, :scope, :profile]]
    ]

  @impl Concept.Pages.BlockType
  def type, do: :ai_answer

  @impl Concept.Pages.BlockType
  def lexical_node, do: "ai-answer"

  @impl Concept.Pages.BlockType
  def slash_menu,
    do: %{label: "AI Answer", icon: "✨", keywords: ~w(ai answer), group: :ai}

  # Derive view-state from the current `block`. Runs on mount and after
  # every `block_updated` PubSub broadcast (the dispatcher re-assigns).
  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign(:state, derive_state(assigns.block))
      |> assign(:preview_html, render_preview(assigns.block))

    {:ok, socket}
  end

  # The inner template. The macro wraps this in
  # `<div phx-hook="OraBlock" data-events="evaluate refresh retry" ...>`.
  @impl Concept.Pages.BlockType
  def render_body(assigns) do
    ~H"""
    <ora-ai-block
      id={"ora-ai-" <> @block.id}
      block-id={@block.id}
      state={@state}
      preview-html={@preview_html}
    />
    """
  end

  # ... private helpers (derive_state/1, render_preview/1, etc.) ...
end
```

### `ash_actions` shape

```elixir
ash_actions: [
  verb: [Module, :function, [arg_atom, ...]]
]
```

Each verb generates a `handle_event(to_string(verb), payload, socket)` clause
that calls:

```elixir
Module.function(block, arg1, arg2, ..., actor: actor, tenant: tenant)
```

where each `argN` is pulled from the event payload by atom-or-string key,
`actor` is `socket.assigns.current_user`, and `tenant` is
`block.workspace_id`. The `Module.function/N+1` must exist (Ash code
interface or plain function) and follow that signature.

### The Lit component dispatches `ora-<verb>` events

```js
// assets/js/components/ai_block.js
_dispatch(verb) {
  this.dispatchEvent(
    new CustomEvent(`ora-${verb}`, {
      bubbles: true,
      composed: true,
      detail: { prompt: this._prompt, scope: this._scope, profile: this._profile }
    })
  );
}

_onGenerate() { this._dispatch("evaluate"); }
_onRefresh()  { this._dispatch("refresh");  }
_onRetry()    { this._dispatch("retry");    }
```

The generic `OraBlock` hook (`assets/js/hooks/ora_block.js`) reads
`data-events="evaluate refresh retry"` from the wrapper, subscribes to each
`ora-<verb>` CustomEvent on that element, and forwards them via
`pushEventTo(this.el, verb, { block_id, ...detail })`. The `block_id` is
injected automatically from `data-block-id`.

### Wiring guarantees (compile-time and structural)

| Concern | Mechanism |
|---|---|
| `phx-hook="OraBlock"` is on the rendered element | Macro wraps `render_body/1`; you can't omit it. |
| `data-events` matches `ash_actions` keys | Macro derives the string from `ash_actions` — single source of truth. |
| Every declared verb has a `handle_event/3` clause | Macro generates one per `ash_actions` entry. |
| `render_body/1` exists | `@before_compile` raises `CompileError` if missing. |
| Event dispatched from JS reaches the LC | `OraBlock` hook + `phx-target={@myself}` on the wrapper (also set by macro). |

What's *not* guaranteed (the residual; cover with tests):

- The Lit component dispatches a verb name that matches `data-events`
  (typo `ora-evalaute` no-ops silently — see follow-up #1).
- The event payload contains the right keys.
- The Ash action's signature actually matches what the macro will call.

For the residuals, write a contract test like
`test/concept_web/blocks/ai_answer_test.exs`.

### Register and propagate `current_user`

```elixir
# config/config.exs
config :concept, :block_types, [..., Concept.Pages.BlockTypes.AiAnswer]
```

The dispatcher already passes `current_user` to interactive LCs. Nothing
else to wire — *but* the actor contract below.

### Actor contract (enforced at runtime)

`Concept.Pages.BlockType.Interactive.invoke_action/3` (called from every
generated `handle_event/3` clause) requires `current_user` to be either:

* a **struct** (typically `%Concept.Accounts.User{}`), or
* `%{system?: true}` (internal escalation, e.g. for the spawned task that
  finalizes an AI Answer response).

A bare map like `%{id: user_id, email: "foo@example.com"}` raises an
`ArgumentError` immediately, with a message pointing at the parent
LiveView that needs to load the User struct. This is intentional:
`Concept.Knowledge.Chat.Conversation.create` has
`change relate_actor(:user)`, which uses `actor.__struct__` to resolve the
relationship target — a bare map silently falls through to "could not
relate to actor" deep in the Ash pipeline.

**Common gotcha**: nested `live_render` does not propagate the parent's
`current_user` assign through the auth `on_mount` chain. If you're
mounting an interactive block from a nested LiveView, load the User
explicitly in `mount/3`:

```elixir
@impl Phoenix.LiveView
def mount(_params, session, socket) do
  user_id = session["user_id"]

  user =
    case Ash.get(Concept.Accounts.User, user_id, authorize?: false) do
      {:ok, u} -> u
      _ -> %{system?: true}     # fall back only if reasonable
    end

  {:ok, assign(socket, :current_user, user)}
end
```

See `lib/concept_web/live/page_editor_live.ex` for the reference
implementation.

---

## 3. Text blocks today (legacy path)

Text blocks (paragraph, heading_1/2/3, quote, callout, to_do,
bulleted_list_item, numbered_list_item, code, toggle, table_cell, column)
are still handled by `text_block/1` inside
`lib/concept_web/components/block_render.ex`. Their `BlockType` module only
declares metadata (`type`, `lexical_node`, `slash_menu`, validation).
Conversion to `Static` is a follow-up.

If you're adding a new text-shaped block today, follow `paragraph.ex` as
the template and add the type to the dispatcher's `@text_types` list.

---

## Contract test (recommended for interactive blocks)

Mirrors `test/concept_web/blocks/ai_answer_test.exs`:

```elixir
test "evaluate event invokes the declared Ash action", %{conn: conn, ...} do
  {:ok, view, _} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")
  inner = find_live_child(view, "page-editor-#{page.id}")

  inner
  |> element("div#ai-#{block.id}")
  |> render_hook("evaluate", %{"prompt" => "x", ...})

  reloaded = Ash.get!(Pages.Block, block.id, actor: user, tenant: ws.id)
  assert reloaded.props["prompt"] == "x"
end
```

Two assertions to add per block type:

1. Wrapper carries `phx-hook="OraBlock"` and the expected `data-events`.
2. Pushing one verb actually mutates state observable via the resource.

---

## Reference

| File | Purpose |
|---|---|
| `lib/concept/pages/block_type.ex` | The `@behaviour` callbacks. |
| `lib/concept/pages/block_type/static.ex` | `use`-able for non-interactive types. |
| `lib/concept/pages/block_type/interactive.ex` | `use`-able for LC-backed types. |
| `lib/concept/pages/block_types.ex` | Registry; `lookup/1`, `slash_menu_items/0`. |
| `lib/concept_web/components/block_render.ex` | Dispatcher. Should not need editing. |
| `assets/js/hooks/ora_block.js` | Generic JS hook. Should not need editing. |
| `config/config.exs` `:concept, :block_types` | The single registry list. |

---

## Anti-patterns

- **Editing `block_render.ex`** to add a new block type — the dispatcher is
  type-agnostic; everything lives in the type module.
- **Adding a per-block JS hook** — use `OraBlock` and declare events via
  `data-events`. A per-block hook is the original bug pattern.
- **Adding a `handle_event/3` clause to `PageEditorLive`** for a block
  event — events route to the LC by `phx-target`. Adding it to the LV
  fragments the wiring and bypasses the macro's invariant.
- **Putting `phx-hook` inside `render_body/1`** — the wrapper already has
  it. Double-wrapping breaks LV diffing.
- **Mutating `block` directly from `handle_event/3` callback** — invoke
  the declared Ash action instead. PubSub propagation is what triggers the
  block re-render via `update/2`.
