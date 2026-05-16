defmodule Concept.Knowledge.ProfileBuilder do
  @moduledoc """
  Entry point for declaring profiles via the Knowledge profile DSL.

      defmodule MyApp.Profiles do
        use Concept.Knowledge.ProfileBuilder

        profile :fast do
          rewrite false
          search mode: :semantic, limit: 6
          rerank false
          answer model: "google:gemini-2.5-flash-lite"
          tools [:search_workspace]
        end
      end

  Introspection helpers (list/0, get/1, get!/1) are injected at compile time.
  """
  defmacro __using__(_opts) do
    quote do
      use Spark.Dsl,
        many_extension_kinds: [:extensions],
        default_extensions: [extensions: [unquote(Concept.Knowledge.ProfileDsl)]]

      @doc "List all profiles declared in this module."
      def list, do: Spark.Dsl.Extension.get_entities(__MODULE__, [:profiles])

      @doc "Get a profile by name; returns nil if not found."
      def get(name) when is_atom(name), do: Enum.find(list(), &(&1.name == name))

      @doc "Get a profile by name; raises ArgumentError if not found."
      def get!(name) when is_atom(name) do
        get(name) || raise ArgumentError, "unknown profile: #{inspect(name)}"
      end

      @doc "Profile name → keyword list consumable by Arcana.Pipeline."
      def to_pipeline_opts(name), do: name |> get!() |> Concept.Knowledge.Profile.to_pipeline_opts()

      @doc "Profile name → keyword list consumable by AshAi.ToolLoop."
      def to_ash_ai_opts(name), do: name |> get!() |> Concept.Knowledge.Profile.to_ash_ai_opts()
    end
  end
end
