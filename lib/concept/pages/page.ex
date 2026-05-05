defmodule Concept.Pages.Page do
  @moduledoc """
  A page in a workspace tree. Soft-deletable via AshArchival, version-tracked
  via AshPaperTrail, multitenant by `workspace_id`, fractional-indexed for sibling
  ordering.
  """
  use Ash.Resource,
    otp_app: :concept,
    domain: Concept.Pages,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshArchival.Resource],
    notifiers: [Ash.Notifier.PubSub]

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
    base_filter?(true)
  end

  actions do
    defaults [:read]

    create :create_page do
      accept [:title, :icon_emoji, :parent_page_id]
      argument :workspace_id, :uuid, allow_nil?: false
      change set_attribute(:workspace_id, arg(:workspace_id))
      change Concept.Pages.Changes.AssignAfterLastSibling
    end

    update :rename do
      accept [:title]
    end

    update :set_icon do
      accept [:icon_emoji]
    end

    update :set_cover_color do
      accept [:cover_color]
    end

    update :reorder do
      accept [:position]
    end

    update :reparent do
      accept [:parent_page_id, :position]
      change Concept.Pages.Changes.PreventCycles
    end

    update :archive do
      accept []
      change Concept.Pages.Changes.CascadeArchive
    end

    update :restore do
      accept []
      change set_attribute(:archived_at, nil)
    end

    read :list_tree do
      prepare build(sort: [parent_page_id: :asc, position: :asc])
    end

    read :recent_pages do
      prepare build(sort: [updated_at: :desc], limit: 10)
    end

    read :search_titles do
      argument :query, :string, allow_nil?: false
      filter expr(ilike(title, fragment("concat('%', ?::text, '%')", ^arg(:query))))
      prepare build(sort: [updated_at: :desc], limit: 20)
    end
  end

  policies do
    bypass actor_attribute_equals(:system?, true) do
      authorize_if always()
    end

    policy always() do
      authorize_if Concept.Pages.Checks.WorkspaceMember
    end
  end

  pub_sub do
    module ConceptWeb.Endpoint
    prefix "workspace"

    publish_all :create, ["*", :workspace_id, "pages"], event: "page_created"
    publish_all :update, ["*", :workspace_id, "pages"], event: "page_updated"
    publish :archive, ["*", :workspace_id, "pages"], event: "page_archived"
    publish :restore, ["*", :workspace_id, "pages"], event: "page_restored"
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
    global? false
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

    has_many :blocks, Concept.Pages.Block, destination_attribute: :page_id
  end

  aggregates do
    count :children_count, :children
    count :block_count, :blocks
  end
end
