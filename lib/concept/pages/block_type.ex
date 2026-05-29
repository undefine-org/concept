defmodule Concept.Pages.BlockType do
  @moduledoc """
  Behaviour each block type implements. Consumed by `Concept.Pages.BlockTypes`
  registry; one module per Notion-style block type. The Block Ash resource
  itself is type-agnostic — each type owns its Lexical schema, props validation,
  slash-menu metadata, render output, and (when interactive) its LiveComponent
  event handlers.

  Most modules should `use` one of the four mixins, which supply defaults for
  every callback so each module declares only what is unique to it:

  | Mixin | `render_kind/0` | Renders via |
  |---|---|---|
  | `BlockType.Text` | `:text` | shared Lexical editor host (`placeholder/0`, `editor_class/0`) |
  | `BlockType.Static` | `:static` | module `render/1` |
  | `BlockType.Interactive` | `:interactive` | LiveComponent `render_body/1` |
  | `BlockType.Composite` | `:composite` | shared grid host (`composite_layout/0`) |

  ## Rendering contract

  `ConceptWeb.BlockRender.block/1` is a pure dispatcher: it routes each block
  to a render path by `render_kind/0` alone — no hardcoded type lists, no
  string special-casing. The four kinds:

  * `:text` — edited through the shared `<ora-block>` Lexical host. The module
    supplies presentation metadata via `placeholder/0` and `editor_class/0`;
    the host markup itself is shared web wiring owned by the dispatcher.
  * `:static` — the module defines `render/1` accepting the dispatcher assigns
    and returning a rendered HEEx struct. (`render/1` is documented contract
    rather than a formal `@callback` to avoid colliding with
    `Phoenix.LiveComponent.render/1`; the `Static` mixin enforces its presence
    at compile time.)
  * `:interactive` — the module is a `Phoenix.LiveComponent` and defines
    `render_body/1`; the `Interactive` macro wraps it in the required
    `phx-hook` wiring and provides `render/1`.
  * `:composite` — a container (table/columns) laid out by the shared grid
    host in the dispatcher; `composite_layout/0` selects the layout.
  """

  @type render_kind :: :text | :static | :interactive | :composite

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
  The render path the dispatcher routes this type through. Supplied by each
  mixin; the single source of truth for `ConceptWeb.BlockRender.block/1`.
  """
  @callback render_kind() :: render_kind()

  @doc """
  Text types only. Placeholder shown in the empty Lexical editor. Defaults to
  `\"\"` via `BlockType.Text`.
  """
  @callback placeholder() :: String.t()

  @doc """
  Text types only. CSS class applied to the editor surface. Defaults to
  `\"ora-block\"` via `BlockType.Text`.
  """
  @callback editor_class() :: String.t()

  @doc """
  Composite types only. Selects the shared grid layout (`:table` | `:columns`).
  """
  @callback composite_layout() :: atom()

  @doc """
  Interactive types only. The inner template; the `Interactive` macro wraps
  it in a `<div phx-hook=\"OraBlock\" data-events=…>` so the JS hook can forward
  `CustomEvent`s back to the LiveComponent.
  """
  @callback render_body(assigns :: map()) :: Phoenix.LiveView.Rendered.t()

  @optional_callbacks render_body: 1,
                      placeholder: 0,
                      editor_class: 0,
                      composite_layout: 0
end
