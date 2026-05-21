defmodule Concept.Pages.BlockType do
  @moduledoc """
  Behaviour each block type implements. Consumed by `Concept.Pages.BlockTypes`
  registry; one module per Notion-style block type. The Block Ash resource
  itself is type-agnostic — each type owns its Lexical schema, props validation,
  slash-menu metadata, render output, and (when interactive) its LiveComponent
  event handlers.

  Most modules should `use Concept.Pages.BlockType.Static` (defaults +
  `Phoenix.Component` import) or `use Concept.Pages.BlockType.Interactive,
  ash_actions: [...]` (LiveComponent + compile-time wiring check).

  ## Rendering contract

  The `ConceptWeb.BlockRender.block/1` dispatcher routes each block to its
  render path based on `live_component?/0`:

  * `live_component?() == false` (static) — the module must define `render/1`
    accepting the dispatcher assigns and returning a HEEx rendered struct.
    `render/1` is *not* a formal `@callback` here to avoid collisions with
    `Phoenix.LiveComponent.render/1`; it is documented contract.
  * `live_component?() == true` (interactive) — the module is a
    `Phoenix.LiveComponent` and defines `render_body/1`; the Interactive macro
    wraps it in the required `phx-hook` wiring and provides `render/1` for
    the LiveComponent contract.
  """

  @callback type :: atom
  @callback default_content :: map
  @callback default_props :: map
  @callback validate_props(map) :: :ok | {:error, term}
  @callback lexical_node :: String.t()
  @callback slash_menu :: %{
              required(:label) => String.t(),
              required(:icon) => String.t(),
              required(:keywords) => [String.t()],
              required(:group) => atom
            }
  @callback container? :: boolean

  @doc """
  Whether this block type renders as a `Phoenix.LiveComponent` (interactive,
  owns its own `handle_event/3`) vs. a stateless function-component render.
  """
  @callback live_component?() :: boolean()

  @doc """
  Interactive types only. The inner template; the `Interactive` macro wraps
  it in a `<div phx-hook="OraBlock" data-events=…>` so the JS hook can forward
  `CustomEvent`s back to the LiveComponent.
  """
  @callback render_body(assigns :: map()) :: Phoenix.LiveView.Rendered.t()

  @doc false
  @callback render_static(map) :: Phoenix.LiveView.Rendered.t() | iodata

  @optional_callbacks render_static: 1, render_body: 1, live_component?: 0
end
