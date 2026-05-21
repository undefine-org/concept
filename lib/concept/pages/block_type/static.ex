defmodule Concept.Pages.BlockType.Static do
  @moduledoc """
  `use`-able mixin for stateless block types. Provides sensible defaults for
  every `Concept.Pages.BlockType` callback so each module only has to declare
  `type/0`, `lexical_node/0`, `slash_menu/0`, and `render/1`.

  Bridges legacy `render_static/1` to the new `render/1` for back-compat with
  any callers that still invoke it.

      defmodule Concept.Pages.BlockTypes.Divider do
        use Concept.Pages.BlockType.Static

        @impl true
        def type, do: :divider
        @impl true
        def lexical_node, do: "divider"
        @impl true
        def slash_menu, do: %{label: "Divider", icon: "—", keywords: ["divider"], group: :media}

        @impl true
        def render(assigns) do
          ~H"<hr class=\"border-notion-divider my-2\" />"
        end
      end
  """

  defmacro __using__(_opts) do
    quote do
      @behaviour Concept.Pages.BlockType
      use Phoenix.Component

      @impl true
      def live_component?, do: false

      @impl true
      def default_content, do: %{}

      @impl true
      def default_props, do: %{}

      @impl true
      def validate_props(p) when p == %{}, do: :ok
      def validate_props(_), do: :ok

      @impl true
      def container?, do: false

      @impl Concept.Pages.BlockType
      def render_static(block), do: render(%{block: block})

      defoverridable live_component?: 0,
                     default_content: 0,
                     default_props: 0,
                     validate_props: 1,
                     container?: 0,
                     render_static: 1
    end
  end
end
