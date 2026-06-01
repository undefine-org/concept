defmodule Concept.Pages.BlockType.Composite do
  @moduledoc """
  `use`-able mixin for container block types laid out as a grid of child
  blocks (table, columns).

  Composite blocks render through the shared grid host owned by
  `ConceptWeb.BlockRender`, which recurses into each child via the normal
  dispatcher. The only per-type knob is `composite_layout/0`, selecting which
  shared layout to use:

    * `:table`   — `props["rows"]` × `props["cols"]` grid of `table_cell`s
    * `:columns` — `props["count"]` equal-width columns

  This replaces the former string special-casing (`assigns.type == "table"`)
  inside the dispatcher: layout selection is now declared on the type module,
  not pattern-matched on a literal in `block_render.ex`.

      defmodule Concept.Pages.BlockTypes.Table do
        use Concept.Pages.BlockType.Composite

        @impl true
        def type, do: :table
        @impl true
        def composite_layout, do: :table
        # ...
      end
  """

  defmacro __using__(_opts) do
    quote do
      @behaviour Concept.Pages.BlockType
      use Phoenix.Component

      @impl Concept.Pages.BlockType
      def render_kind, do: :composite

      @impl Concept.Pages.BlockType
      def default_content, do: %{}

      @impl Concept.Pages.BlockType
      def default_props, do: %{}

      @impl Concept.Pages.BlockType
      def validate_props(_), do: :ok

      @impl Concept.Pages.BlockType
      def container?, do: true

      @doc """
      Whether this composite exposes inline resize handles between its tracks
      (columns / table columns). Declared once on the flavour so every composite
      inherits the affordance; override to opt a layout out.
      """
      def resizable?, do: true

      defoverridable render_kind: 0,
                     default_content: 0,
                     default_props: 0,
                     validate_props: 1,
                     container?: 0,
                     resizable?: 0
    end
  end
end
