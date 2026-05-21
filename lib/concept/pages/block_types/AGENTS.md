# Block types

Each module here implements `Concept.Pages.BlockType` and is registered in
`config/config.exs` under `:concept, :block_types`. The registry is the
single source of truth — the dispatcher in `ConceptWeb.BlockRender.block/1`
routes by type, no `case`/`cond` editing required to add a type.

## Adding a new block type

**Read `docs/blocks/ADDING_A_BLOCK.md` first.** It covers the three flavors
(Static, Interactive, Text), the wiring guarantees, and the contract-test
pattern.

TL;DR:

| Flavor | `use` | Provides `render_body/1`? |
|---|---|---|
| Static (`divider`, `image`, `bookmark`, `equation`) | `Concept.Pages.BlockType.Static` | No — provide `render/1` |
| Interactive (`ai_answer`) | `Concept.Pages.BlockType.Interactive, ash_actions: [...]` | Yes — wrapper is auto-generated |
| Text (paragraph, headings, lists, callout, …) | bare `@behaviour` (legacy; covered by `text_block/1` in `BlockRender`) | n/a |

After creating the module, add it to `config/config.exs`:

```elixir
config :concept, :block_types, [..., Concept.Pages.BlockTypes.YourType]
```

That's the entire registration step. No edits to `BlockRender`, JS hooks,
or LiveView event handlers.

## Anti-patterns

| ✗ Don't | ✓ Do instead |
|---|---|
| Edit `lib/concept_web/components/block_render.ex` to add a clause | Define `render/1` (Static) or `render_body/1` (Interactive) in your type module |
| Create a per-block JS hook | Use `OraBlock` + declare `data-events` via `ash_actions:` |
| Add `handle_event/3` to `PageEditorLive` | The Interactive macro generates clauses on your LC from `ash_actions:` |
| Put `phx-hook` inside `render_body/1` | The Interactive wrapper already has it |
| Call the resource directly from `handle_event/3` | Declare it in `ash_actions:`; let the macro dispatch |

## Reference

- `Concept.Pages.BlockType` — the behaviour (`../block_type.ex`)
- `Concept.Pages.BlockType.Static` — `use`-able mixin (`../block_type/static.ex`)
- `Concept.Pages.BlockType.Interactive` — `use`-able mixin with codegen (`../block_type/interactive.ex`)
- `Concept.Pages.BlockTypes` — registry helpers (`../block_types.ex`)
- `ConceptWeb.BlockRender` — dispatcher (`../../../concept_web/components/block_render.ex`)
- `assets/js/hooks/ora_block.js` — generic JS hook for interactive blocks
- **Tutorial:** [`docs/blocks/ADDING_A_BLOCK.md`](../../../../docs/blocks/ADDING_A_BLOCK.md)
- **Reference contract test:** `test/concept_web/blocks/ai_answer_test.exs`
