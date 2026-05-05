defmodule Concept.Pages do
  @moduledoc "Page tree + Block content domain."
  use Ash.Domain, otp_app: :concept, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Concept.Pages.Page do
      define :create_page, args: [:title, :workspace_id, {:optional, :parent_page_id}]
      define :rename_page, args: [:title], action: :rename
      define :set_icon, args: [:icon_emoji]
      define :set_cover_color, args: [:cover_color]
      define :reorder, args: [:position]
      define :reparent, args: [:parent_page_id, :position]
      define :archive
      define :restore
      define :list_tree, action: :list_tree
      define :recent_pages, action: :recent_pages
      define :search_titles, args: [:query]
      define :get_page, action: :read, get_by: :id
    end

    resource Concept.Pages.Block do
      define :create_block, args: [:page_id, :type, :workspace_id, {:optional, :parent_block_id}]
      define :update_content, args: [:content]
      define :update_props, args: [:props]
      define :reorder_block, args: [:position], action: :reorder
      define :reparent_block, args: [:parent_block_id, :position], action: :reparent
      define :archive_block, action: :archive
      define :acquire_lock
      define :release_lock
      define :refresh_lock
      define :list_for_page, args: [:page_id]
    end
  end
end
