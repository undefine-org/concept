defmodule Concept.Pages.BlockType.Static do
  @moduledoc """
  `use`-able mixin for stateless block types. Provides sensible defaults for
  every `Concept.Pages.BlockType` callback so each module only has to declare
  `type/0`, `lexical_node/0`, `slash_menu/0`, and `render/1`.

  Presence of `render/1` is enforced at compile time via `@before_compile`,
  mirroring the guarantee `BlockType.Interactive` gives for `render_body/1`.

      defmodule Concept.Pages.BlockTypes.Divider do
        use Concept.Pages.BlockType.Static

        @impl true
        def type, do: :divider
        @impl true
        def lexical_node, do: "divider"
        @impl true
        def slash_menu, do: %{label: "Divider", icon: "—", keywords: ["divider"], group: :media}

        def render(assigns) do
          ~H"<hr class=\"border-notion-divider my-2\" />"
        end
      end
  """

  defmacro __using__(_opts) do
    quote do
      @behaviour Concept.Pages.BlockType
      @before_compile Concept.Pages.BlockType.Static
      use Phoenix.Component

      @impl Concept.Pages.BlockType
      def render_kind, do: :static

      @impl Concept.Pages.BlockType
      def default_content, do: %{}

      @impl Concept.Pages.BlockType
      def default_props, do: %{}

      @impl Concept.Pages.BlockType
      def validate_props(p) when p == %{}, do: :ok
      def validate_props(_), do: :ok

      @impl Concept.Pages.BlockType
      def container?, do: false

      defoverridable render_kind: 0,
                     default_content: 0,
                     default_props: 0,
                     validate_props: 1,
                     container?: 0
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    unless Module.defines?(env.module, {:render, 1}) do
      raise CompileError,
        file: env.file,
        line: env.line,
        description:
          "#{inspect(env.module)} uses Concept.Pages.BlockType.Static but does not define render/1"
    end

    :ok
  end
end
