defmodule Concept.Containable do
  @moduledoc """
  Declares an Ash resource a **block container**: a surface that owns a tree of
  `Concept.Pages.Block`s. A Page is a container; a chat Message is a container
  (talk carries the editor's full block expressiveness); a Record detail body
  will be the third.

  This is the content-layer twin of `Concept.Hostable`. Where `Hostable`
  makes a resource the polymorphic
  *subject* of a conversation (`host_type`/`host_id`), `Containable` makes a
  resource the polymorphic *owner* of a block tree (`container_type`/
  `container_id`). Both replace per-parent foreign keys with a
  registry-validated `{type_atom, uuid}` pair — the codebase's idiom for "one
  resource, many possible parents" (Ash has no `belongs_to polymorphic?:`).

  ## Two halves (mirroring `Hostable` and the block-type registry)

  * **Mixin** (`use Concept.Containable, type: :page`) — supplies the
    `Concept.Containable` behaviour and `__containable__/0` introspection.
  * **Registry** (application config) — the set of container modules, exactly
    like `config :concept, :hostables` / `:block_types`. Read via
    `registered/0` / `types/0`.

  ## Usage

      defmodule Concept.Pages.Page do
        use Concept.Resources.WorkspaceTenanted, ...
        use Concept.Containable, type: :page
      end

  And register it:

      config :concept, :containables, [Concept.Pages.Page, Concept.Knowledge.Chat.Message]

  The `Concept.Containable.TypeAttr` Ash type validates a block's
  `container_type` against `types/0` at write time, so the stored discriminator
  can never drift from the registry.
  """

  @typedoc "A container's discriminator atom, e.g. `:page` or `:message`."
  @type type :: atom()

  @doc """
  Static metadata declared at `use Concept.Containable` time:
  `%{type: atom}`. The single source of a container module's discriminator.
  """
  @callback __containable__() :: %{required(:type) => type()}

  @typedoc """
  How a container presents itself to the knowledge-ingest pipeline:

    * `source_id`    — the Arcana source key, conventionally `"<type>:<id>"`
    * `body`         — a non-blank document body string (title / breadcrumb)
    * `chunker_opts` — opts handed to `Concept.Knowledge.Indexer.ingest_source/4`
      (must carry `:blocks` and `:workspace_id`; pages add `:page`, messages add
      `:message_id` / `:breadcrumbs`).
  """
  @type ingest_descriptor :: %{
          required(:source_id) => String.t(),
          required(:body) => String.t(),
          required(:chunker_opts) => keyword()
        }

  @doc """
  Describe this container instance as a knowledge-ingest source, loading its
  blocks. Returns `{:ok, descriptor}` to ingest, `:skip` when there is nothing
  to index (missing record, no blocks), or `{:error, reason}` on failure.

  This is the single dispatch point that lets `Concept.Knowledge.Workers.IngestPage`
  ingest *any* container without a per-type clause — a new container becomes
  searchable by implementing this callback alone.
  """
  @callback ingest_descriptor(id :: Ecto.UUID.t(), workspace_id :: Ecto.UUID.t()) ::
              {:ok, ingest_descriptor()} | :skip | {:error, term()}

  @doc "All registered container modules (from `config :concept, :containables`)."
  @spec registered() :: [module()]
  def registered, do: Application.get_env(:concept, :containables, [])

  @doc """
  All valid `container_type` atoms — every registered container module's
  declared `type`. Drives the `one_of`/`TypeAttr` validation on
  `Block.container_type`.
  """
  @spec types() :: [type()]
  def types, do: Enum.map(registered(), & &1.__containable__().type)

  @doc "The container module for a `container_type` atom, or `nil` if unknown."
  @spec module_for(type()) :: module() | nil
  def module_for(type) when is_atom(type) do
    Enum.find(registered(), fn mod -> mod.__containable__().type == type end)
  end

  defmacro __using__(opts) do
    type = Keyword.fetch!(opts, :type)

    quote bind_quoted: [type: type] do
      @behaviour Concept.Containable

      @__containable_meta__ %{type: type}

      @impl Concept.Containable
      def __containable__, do: @__containable_meta__
    end
  end
end
