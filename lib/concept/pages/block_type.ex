defmodule Concept.Pages.BlockType do
  @moduledoc """
  Behaviour each block type implements. Consumed by `Concept.Pages.BlockTypes`
  registry; one module per Notion-style block type. The Block Ash resource
  itself is type-agnostic — each type owns its Lexical schema, props validation,
  slash-menu metadata, and static fallback render.
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
  @callback render_static(map) :: Phoenix.LiveView.Rendered.t() | iodata

  @optional_callbacks render_static: 1
end
