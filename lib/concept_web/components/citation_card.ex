defmodule ConceptWeb.Components.CitationCard do
  @moduledoc """
  Citation card component with block preview popover.

  Renders a citation as a clickable card with metadata (icon, breadcrumbs, snippet, score).
  On hover, triggers a preview request to the parent LiveView to load and display the
  actual block content via BlockRender.
  """
  use Phoenix.Component
  import ConceptWeb.CoreComponents

  alias Concept.Pages

  @doc """
  Renders a citation card with preview popover support.

  ## Examples

      <.citation_card citation={@citation} workspace_slug={@workspace.slug} />
  """
  attr :citation, :map, required: true
  attr :workspace_slug, :string, required: true
  attr :rest, :global

  slot :preview_loader, doc: "Optional preview loader slot"

  def citation_card(assigns) do
    ~H"""
    <ora-citation-popover data-block-id={@citation.block_id}>
      <.link
        navigate={"/w/" <> @workspace_slug <> "/p/" <> @citation.page_id <> "#block-" <> @citation.block_id}
        class="ora-citation-card"
        {@rest}
      >
        <div class="flex items-start gap-2">
          <.icon name={citation_icon(@citation)} class="size-4 shrink-0 mt-0.5" />
          <div class="flex-1 min-w-0">
            <div :if={@citation.breadcrumbs} class="ora-citation-card__breadcrumb">
              {breadcrumb_text(@citation.breadcrumbs)}
            </div>
            <div :if={@citation.snippet} class="ora-citation-card__snippet">
              {@citation.snippet}
            </div>
            <div
              class="ora-citation-card__sparkline"
              role="progressbar"
              aria-valuenow={sparkline_value(@citation.score)}
              aria-valuemin="0"
              aria-valuemax="100"
              style={sparkline_style(@citation.score)}
            >
            </div>
          </div>
        </div>
      </.link>
    </ora-citation-popover>
    """
  end

  @doc """
  Helper function for LiveView to load block preview HTML.

  Call from `handle_event("load_block_preview", %{"block-id" => block_id}, socket)`.

  ## Examples

      def handle_event("load_block_preview", %{"block-id" => block_id}, socket) do
        case CitationCard.load_block_preview(block_id, socket) do
          {:ok, html} -> {:reply, %{html: html}, socket}
          {:error, _} -> {:noreply, socket}
        end
      end
  """
  def load_block_preview(block_id, socket) do
    workspace_id = socket.assigns.workspace.id
    actor = Map.get(socket.assigns, :current_user)

    case Ash.get(Pages.Block, block_id, actor: actor, tenant: workspace_id) do
      {:ok, block} ->
        # Convert block content to displayable HTML
        html = Concept.Lexical.to_html(block.content)

        {:ok, html}

      {:error, _} = error ->
        error
    end
  end

  # Determines icon based on citation type heuristic
  defp citation_icon(%{breadcrumbs: nil}), do: "hero-document-text"
  defp citation_icon(_), do: "hero-sparkles"

  # Formats breadcrumbs with chevron separators
  defp breadcrumb_text(breadcrumbs) when is_binary(breadcrumbs) do
    breadcrumbs
    |> String.split(">")
    |> Enum.map(&String.trim/1)
    |> Enum.join(" › ")
  end

  defp breadcrumb_text(_), do: ""

  # Converts score (0.0-1.0) to percentage for aria-valuenow
  defp sparkline_value(nil), do: 0
  defp sparkline_value(score) when is_float(score), do: round(score * 100)
  defp sparkline_value(_), do: 0

  # Generates inline style for sparkline gradient based on score
  defp sparkline_style(nil), do: "width: 0%"

  defp sparkline_style(score) when is_float(score) do
    percentage = round(score * 100)
    "width: #{percentage}%"
  end

  defp sparkline_style(_), do: "width: 0%"
end
