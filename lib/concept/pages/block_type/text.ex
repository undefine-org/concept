defmodule Concept.Pages.BlockType.Text do
  @moduledoc """
  `use`-able mixin for Lexical-edited text block types (paragraph, headings,
  quote, callout, to-do, list items, code, toggle, and the composite leaves
  table_cell / column).

  Text blocks render through the shared `<ora-block>` Lexical editor host owned
  by `ConceptWeb.BlockRender`. The host markup is shared web wiring; each type
  contributes only its *presentation metadata*:

    * `placeholder/0` — empty-editor hint (default `""`)
    * `editor_class/0` — CSS class on the editor surface (default `"ora-block"`)

  This is the seam that previously leaked into `block_render.ex` as the
  `@text_types` whitelist plus `placeholder_for/1` and `ora_block_class/1`
  lookup tables. Declaring it here keeps a text type's full vertical slice in
  one module, restoring the "no edits to BlockRender" contract.

      defmodule Concept.Pages.BlockTypes.Heading1 do
        use Concept.Pages.BlockType.Text

        @impl true
        def type, do: :heading_1
        @impl true
        def default_content, do: Concept.Lexical.empty_heading(1)
        @impl true
        def lexical_node, do: "heading"
        @impl true
        def slash_menu,
          do: %{label: "Heading 1", icon: "H1", keywords: ~w(heading h1 title), group: :basic}

        @impl true
        def placeholder, do: "Heading 1"
        @impl true
        def editor_class, do: "ora-block h1"
      end
  """

  defmacro __using__(_opts) do
    quote do
      @behaviour Concept.Pages.BlockType
      use Phoenix.Component

      @impl Concept.Pages.BlockType
      def render_kind, do: :text

      @impl Concept.Pages.BlockType
      def default_content, do: %{}

      @impl Concept.Pages.BlockType
      def default_props, do: %{}

      @impl Concept.Pages.BlockType
      def validate_props(p) when p == %{}, do: :ok
      def validate_props(_), do: :ok

      @impl Concept.Pages.BlockType
      def container?, do: false

      @impl Concept.Pages.BlockType
      def placeholder, do: ""

      @impl Concept.Pages.BlockType
      def editor_class, do: "ora-block"

      defoverridable render_kind: 0,
                     default_content: 0,
                     default_props: 0,
                     validate_props: 1,
                     container?: 0,
                     placeholder: 0,
                     editor_class: 0
    end
  end
end
