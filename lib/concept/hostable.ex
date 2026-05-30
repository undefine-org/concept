defmodule Concept.Hostable do
  @moduledoc """
  Declares an Ash resource **conversable**: a resource that can be the *host*
  (subject) of conversations, and whose grounded AI "voice" speaks scoped to
  the host's own knowledge subgraph.

  This is the keystone of the conversation substrate (see
  `docs/messaging_design.md`). A conversation is always *about* a host
  (a `Page`, a `Record`, the `Workspace` as a whole, …). The host is both the
  subject of the conversation and a participant in it — its voice is the
  internal Concept AI, grounded in `subgraph_scope/1`.

  ## Two halves (mirroring the repo's extension idioms)

  * **Mixin** (`use Concept.Hostable`) — supplies the per-resource ergonomics:
    the `Concept.Hostable` behaviour, a default `subgraph_scope/1` derived from
    the declared `:scope`, and `__hostable__/0` introspection. This mirrors
    `Concept.Pages.BlockType` mixins (`defoverridable` callback defaults).
  * **Registry** (application config) — the set of host modules, exactly like
    `config :concept, :block_types`. Read via `registered/0` / `types/0`.

  ## Usage

      defmodule Concept.Pages.Page do
        use Concept.Resources.WorkspaceTenanted, ...
        use Concept.Hostable, type: :page, scope: :subtree, persona: "this page"
      end

  And register it:

      config :concept, :hostables, [Concept.Pages.Page]

  ## The `:scope` contract

  `subgraph_scope/1` returns a value the retrieval layer
  (`Concept.Knowledge.Search`) already understands — a `source_id` filter or
  `:workspace` for the whole tenant. The default is derived from `:scope`:

  | `:scope`          | `subgraph_scope/1` returns        |
  |-------------------|-----------------------------------|
  | `:subtree`        | `{:source_id, "page:<id>"}`       |
  | `{:self, _}`      | `{:source_id, "record:<id>"}`     |
  | `:workspace`      | `:workspace`                      |
  | `{:union, refs}`  | `{:union, refs}`                  |

  Override `subgraph_scope/1` in the host module for bespoke grounding.
  """

  @typedoc "The retrieval scope a host contributes to its conversations' RAG."
  @type scope ::
          {:source_id, String.t()}
          | {:union, [term()]}
          | :workspace

  @doc """
  The grounding scope this host contributes to a conversation's retrieval.

  Receives the host *record* (a struct) and returns a `t:scope/0`. The default
  implementation (from the mixin) derives the scope from the declared `:scope`
  option; override for bespoke grounding.
  """
  @callback subgraph_scope(record :: struct()) :: scope()

  # Static metadata declared at `use Concept.Hostable` time:
  # `%{type: atom, scope: term, persona: String.t() | :generative}`.
  @callback __hostable__() :: %{
              required(:type) => atom(),
              required(:scope) => term(),
              required(:persona) => String.t() | :generative
            }

  # The `:workspace` host is always available — it is the degenerate case (a
  # conversation about the whole workspace, `host_id == nil`) and needs no
  # dedicated module. Other host types come from the registry.
  @builtin_types [:workspace]

  @doc "All registered host modules (from `config :concept, :hostables`)."
  @spec registered() :: [module()]
  def registered, do: Application.get_env(:concept, :hostables, [])

  @doc """
  All valid `host_type` atoms: the built-in `:workspace` plus every registered
  host module's declared `type`. Used for the `one_of` constraint on
  `Conversation.host_type`.
  """
  @spec types() :: [atom()]
  def types do
    @builtin_types ++ Enum.map(registered(), & &1.__hostable__().type)
  end

  @doc "The host module for a `host_type` atom, or `nil` (incl. `:workspace`)."
  @spec module_for(atom()) :: module() | nil
  def module_for(:workspace), do: nil

  def module_for(type) when is_atom(type) do
    Enum.find(registered(), fn mod -> mod.__hostable__().type == type end)
  end

  @doc """
  Resolve a `host_type`/`host_id` pair to a grounding scope, loading the host
  record when needed. Workspace host (or unknown type) grounds across the whole
  tenant.
  """
  @spec scope_for(atom(), Ecto.UUID.t() | nil, keyword()) :: scope()
  def scope_for(:workspace, _host_id, _opts), do: :workspace

  def scope_for(type, host_id, opts) when is_atom(type) and is_binary(host_id) do
    case module_for(type) do
      nil ->
        :workspace

      mod ->
        case Ash.get(mod, host_id, Keyword.put(opts, :authorize?, false)) do
          {:ok, record} -> mod.subgraph_scope(record)
          _ -> :workspace
        end
    end
  end

  def scope_for(_type, _host_id, _opts), do: :workspace

  @doc """
  Default scope resolver — translates a declared `:scope` option into a
  `t:scope/0` for a given host record. Public so mixin-generated
  `subgraph_scope/1` can delegate here.
  """
  @spec resolve_scope(term(), struct()) :: scope()
  def resolve_scope(:subtree, %{id: id}) when is_binary(id), do: {:source_id, "page:" <> id}
  def resolve_scope({:self, _}, %{id: id}) when is_binary(id), do: {:source_id, "record:" <> id}
  def resolve_scope(:workspace, _record), do: :workspace
  def resolve_scope({:union, refs}, _record), do: {:union, refs}
  def resolve_scope(_other, _record), do: :workspace

  defmacro __using__(opts) do
    type = Keyword.fetch!(opts, :type)
    scope = Keyword.get(opts, :scope, :workspace)
    persona = Keyword.get(opts, :persona, :generative)

    quote bind_quoted: [type: type, scope: scope, persona: persona] do
      @behaviour Concept.Hostable

      @__hostable_meta__ %{type: type, scope: scope, persona: persona}

      @impl Concept.Hostable
      def __hostable__, do: @__hostable_meta__

      @impl Concept.Hostable
      def subgraph_scope(record),
        do: Concept.Hostable.resolve_scope(@__hostable_meta__.scope, record)

      defoverridable subgraph_scope: 1
    end
  end
end
