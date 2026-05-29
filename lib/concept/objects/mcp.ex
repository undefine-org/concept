defmodule Concept.Objects.Mcp do
  @moduledoc """
  Per-workspace projected MCP tools for user-defined object types.

  The generic spine (`record_create`, `record_transition`, …) is exposed by
  `Concept.AutoTools` at compile time. This module adds the *runtime* typed
  layer: for a workspace with a `Customer` type, `create_customer` /
  `list_customer` / `customer_transition` appear in `tools/list` and execute
  via `tools/call`, routed back through the generic `Record` actions with
  `object_type_id` pinned from the tool's `_meta`.

  Pure, testable core: `list_entries/1` builds the MCP tool descriptors;
  `call/4` executes a projected tool. The HTTP/JSON-RPC seam is the thin
  `ConceptWeb.Plugs.ProjectedMcpTools`.
  """

  alias Concept.Objects.{SchemaLoader, ToolProjector}

  @doc "All projected `%AshAi.Tool{}` for a workspace (empty when tenant is nil)."
  def projected_tools(nil), do: []

  def projected_tools(workspace_id) do
    workspace_id
    |> SchemaLoader.bundles()
    |> ToolProjector.project_all()
  end

  @doc "Set of projected tool names (strings) for a workspace."
  def projected_names(workspace_id) do
    workspace_id |> projected_tools() |> MapSet.new(&to_string(&1.name))
  end

  @doc """
  MCP `tools/list` entries for a workspace:
  `[%{"name", "description", "inputSchema"}]`, schema derived by AshAi so the
  shape matches the generic tools exactly.
  """
  def list_entries(workspace_id, opts \\ []) do
    strict? = Keyword.get(opts, :strict, true)

    workspace_id
    |> projected_tools()
    |> Enum.map(fn %AshAi.Tool{} = tool ->
      {req_tool, _cb} = AshAi.Tools.build(tool, strict: strict?)

      %{
        "name" => req_tool.name,
        "description" => req_tool.description,
        "inputSchema" => req_tool.parameter_schema
      }
    end)
  end

  @doc """
  Execute a projected tool by name. Returns:
    * `{:ok, text}` on success
    * `{:error, reason}` on failure
    * `:not_projected` when `name` is not a projected tool (caller delegates)
  """
  def call(name, arguments, context, workspace_id) do
    tools = projected_tools(workspace_id)

    case Enum.find(tools, &(to_string(&1.name) == to_string(name))) do
      nil ->
        :not_projected

      %AshAi.Tool{} = tool ->
        args = pin_object_type(tool, arguments)

        case AshAi.Tools.execute(tool, args, context) do
          {:ok, text, _raw} -> {:ok, text}
          {:error, err} -> {:error, err}
        end
    end
  end

  # Inject object_type_id (from the tool's _meta) into the create input so the
  # agent never has to supply it — the typed tool *is* the object type.
  defp pin_object_type(%AshAi.Tool{action: :create, _meta: meta}, arguments) do
    otid = meta["object_type_id"]
    input = Map.get(arguments, "input", %{})
    put_in_arguments(arguments, Map.put(input, "object_type_id", otid))
  end

  defp pin_object_type(_tool, arguments), do: arguments

  defp put_in_arguments(arguments, input), do: Map.put(arguments, "input", input)
end
