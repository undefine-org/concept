defmodule Concept.Pages.Page do
  @moduledoc """
  A page in a workspace tree. Soft-deletable via AshArchival, version-tracked
  via AshPaperTrail, multitenant by `workspace_id`, fractional-indexed for sibling
  ordering.
  """
  use Concept.Resources.WorkspaceTenanted,
    otp_app: :concept,
    domain: Concept.Pages,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshArchival.Resource],
    notifiers: [Ash.Notifier.PubSub, Concept.Pages.Notifiers.KnowledgeReindex]

  use Concept.Hostable, type: :page, scope: :subtree, persona: "this page"
  use Concept.Containable, type: :page

  postgres do
    table "pages"
    repo Concept.Repo

    references do
      reference :parent_page, on_delete: :nilify
    end

    custom_indexes do
      index [:workspace_id, :parent_page_id, :position]
    end
  end

  archive do
    attribute :archived_at
  end

  actions do
    defaults [:read]

    create :create_page do
      description "Create a new page in the workspace"
      accept [:title, :icon_emoji, :parent_page_id]

      argument :workspace_id, :uuid,
        allow_nil?: false,
        description: "Workspace where the page will be created"

      change set_attribute(:workspace_id, arg(:workspace_id))
      change Concept.Pages.Changes.AssertWorkspaceMatchesTenant
      change Concept.Pages.Changes.TrimTitle
      change Concept.Pages.Changes.AssignAfterLastSibling
    end

    update :rename do
      description "Rename the page title"
      accept [:title]
      require_atomic? false
      change Concept.Pages.Changes.TrimTitle
    end

    update :set_icon do
      description "Change the page emoji icon"
      accept [:icon_emoji]
    end

    update :set_cover_color do
      description "Set the page cover color"
      accept [:cover_color]
    end

    update :reorder do
      description "Change the page order among siblings"
      accept [:position]
    end

    update :reparent do
      description "Move page to a new parent"
      accept [:parent_page_id, :position]
      require_atomic? false
      change Concept.Pages.Changes.PreventCycles
    end

    update :archive do
      description "Archive the page"
      accept []
      require_atomic? false
      change set_attribute(:archived_at, &DateTime.utc_now/0)
      change Concept.Pages.Changes.CascadeArchive
    end

    update :restore do
      description "Restore an archived page"
      accept []
      change set_attribute(:archived_at, nil)
    end

    read :list_tree do
      description "List the page hierarchy tree"
      prepare build(sort: [parent_page_id: :asc, position: :asc])
    end

    read :recent_pages do
      description "Get recently updated pages"
      prepare build(sort: [updated_at: :desc], limit: 10)
    end

    read :search_titles do
      description "Search pages by title"
      argument :query, :string, allow_nil?: false, description: "Search term for page titles"
      filter expr(ilike(title, fragment("concat('%', ?::text, '%')", ^arg(:query))))
      prepare build(sort: [updated_at: :desc], limit: 20)
    end
  end

  policies do
    # Read floor (members) + system bypass come from
    # `Concept.Resources.WorkspaceTenanted`. Below are the page-specific
    # write policies.
    policy action_type(:create) do
      authorize_if Concept.Pages.Checks.WorkspaceMemberCreate
    end

    policy action_type([:update, :destroy]) do
      authorize_if Concept.Pages.Checks.WorkspaceMember
    end
  end

  pub_sub do
    module ConceptWeb.Endpoint
    prefix "workspace"

    publish_all :create, [:workspace_id, "pages"], event: "page_created"
    publish_all :update, [:workspace_id, "pages"], event: "page_updated"
    publish :archive, [:workspace_id, "pages"], event: "page_archived"
    publish :restore, [:workspace_id, "pages"], event: "page_restored"
  end

  attributes do
    uuid_primary_key :id
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :parent_page_id, :uuid, allow_nil?: true, public?: true
    attribute :title, :string, default: "", public?: true, constraints: [allow_empty?: true]
    attribute :icon_emoji, :string, default: "📄", public?: true

    attribute :cover_color, :atom,
      default: :default,
      public?: true,
      constraints: [one_of: ~w(default red orange yellow green blue purple pink gray)a]

    attribute :position, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :parent_page, __MODULE__,
      attribute_writable?: true,
      source_attribute: :parent_page_id,
      destination_attribute: :id

    has_many :children, __MODULE__, destination_attribute: :parent_page_id

    has_many :blocks, Concept.Pages.Block,
      destination_attribute: :container_id,
      filter: expr(container_type == :page)
  end

  aggregates do
    count :children_count, :children
    count :block_count, :blocks
  end

  @doc """
  Describe a page as a knowledge-ingest source: its title as body, its blocks
  as chunker input. `:skip` when the page no longer exists. See
  `Concept.Containable.ingest_descriptor/2`.
  """
  @impl Concept.Containable
  def ingest_descriptor(page_id, workspace_id) do
    actor = %{system?: true}

    with {:ok, page} <- Concept.Pages.get_page(page_id, actor: actor, tenant: workspace_id),
         {:ok, blocks} <-
           Concept.Pages.list_for_page(page_id, actor: actor, tenant: workspace_id) do
      {:ok,
       %{
         source_id: "page:#{page_id}",
         body: page.title || "Untitled",
         chunker_opts: [page: page, blocks: blocks, workspace_id: workspace_id]
       }}
    else
      {:error, %Ash.Error.Query.NotFound{}} -> :skip
      {:error, reason} -> {:error, reason}
    end
  end
end
