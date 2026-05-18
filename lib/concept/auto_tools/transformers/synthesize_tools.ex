defmodule Concept.AutoTools.Transformers.SynthesizeTools do
  @moduledoc """
  Reads every resource registered on the domain, walks its public actions,
  and contributes one `%AshAi.Tool{}` entity per described action into the
  domain's `[:tools]` section.

  Skipped when:

  * `action.description` is `nil`
  * `{resource, action_name}` appears in
    `Application.get_env(:concept, Concept.AutoTools)[:exclude]`
  * A manual `tool` entry with the same synthesized name already exists
    (a compile warning is emitted via `Logger.warning/1` so authors notice
    and can drop the manual entry).
  """
  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer
  require Logger

  # Run after AshAi's own transformers so manual `tool ...` entries are
  # already in `[:tools]` when we check for name collisions.
  def after?(AshAi.Transformers.Vectorize), do: true
  def after?(AshAi.Transformers.McpApps), do: true
  def after?(_), do: false

  def before?(_), do: false

  def transform(dsl_state) do
    domain = Transformer.get_persisted(dsl_state, :module)
    existing_tools = Transformer.get_entities(dsl_state, [:tools]) || []
    existing_names = MapSet.new(existing_tools, & &1.name)
    excluded = excluded_actions()

    resources =
      dsl_state
      |> Transformer.get_entities([:resources])
      |> Enum.map(& &1.resource)

    synthesis_results =
      for resource <- resources,
          action <- Ash.Resource.Info.actions(resource),
          not is_nil(action.description),
          {resource, action.name} not in excluded do
        name = synth_name(resource, action.name)

        if MapSet.member?(existing_names, name) do
          Logger.warning(
            "[Concept.AutoTools] manual `tool :#{name}` in #{inspect(domain)} " <>
              "shadows auto-synthesized tool for #{inspect(resource)}.#{action.name}. " <>
              "Consider removing the manual entry — the action's description is now the single source of truth."
          )

          :shadowed
        else
          {:ok, build_tool(name, resource, action)}
        end
      end

    dsl_state =
      synthesis_results
      |> Enum.reduce(dsl_state, fn
        {:ok, tool}, acc -> Transformer.add_entity(acc, [:tools], tool)
        :shadowed, acc -> acc
      end)

    {:ok, dsl_state}
  end

  @doc false
  def synth_name(resource, action_name) do
    slug = resource |> Module.split() |> List.last() |> Macro.underscore()
    :"#{slug}_#{action_name}"
  end

  defp build_tool(name, resource, action) do
    %AshAi.Tool{
      name: name,
      resource: resource,
      action: action.name,
      description: action.description,
      load: [],
      async: false,
      arguments: [],
      action_parameters: nil,
      _meta: nil,
      ui: nil,
      identity: nil,
      domain: nil
    }
  end

  defp excluded_actions do
    :concept
    |> Application.get_env(Concept.AutoTools, [])
    |> Keyword.get(:exclude, [])
    |> MapSet.new()
  end
end
