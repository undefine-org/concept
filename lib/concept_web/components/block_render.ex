defmodule ConceptWeb.BlockRender do
  @moduledoc "Function component that dispatches per block type to its template."
  use Phoenix.Component

  import Phoenix.HTML

  @text_types ~w(
    paragraph heading_1 heading_2 heading_3 quote
    callout to_do bulleted_list_item numbered_list_item code toggle
  )

  attr :block, :map, required: true

  def block(assigns) do
    assigns = assign(assigns, :type, to_string(assigns.block.type))

    if assigns.type in @text_types do
      ~H"""
      <div id={"block-" <> @block.id} class="block-anchor scroll-mt-20">
        <div class="ora-block-row group" data-block-id={@block.id}>
          <ora-block-handle class="ora-block-handle group-hover:opacity-100" block-id={@block.id} />
          <ora-block
            phx-hook="BlockEditor"
            phx-update="ignore"
            id={"b-#{@block.id}"}
            block-id={@block.id}
            block-type={@type}
            initial-content={Jason.encode!(@block.content)}
            placeholder={placeholder_for(@block.type)}
            class="ora-block-host"
          >
            <div data-editor class={ora_block_class(@type)}>
              {raw(Concept.Lexical.to_html(@block.content))}
            </div>
          </ora-block>
        </div>
      </div>
      """
    else
      ~H"""
      <div id={"block-" <> @block.id} class="block-anchor scroll-mt-20">
        {static_block(@block)}
      </div>
      """
    end
  end

  defp ora_block_class("heading_1"), do: "ora-block h1"
  defp ora_block_class("heading_2"), do: "ora-block h2"
  defp ora_block_class("heading_3"), do: "ora-block h3"
  defp ora_block_class(_), do: "ora-block"

  defp placeholder_for(:paragraph), do: "Type something…"
  defp placeholder_for(:heading_1), do: "Heading 1"
  defp placeholder_for(:heading_2), do: "Heading 2"
  defp placeholder_for(:heading_3), do: "Heading 3"
  defp placeholder_for(:quote), do: "Quote"
  defp placeholder_for(:callout), do: "Callout"
  defp placeholder_for(:to_do), do: "To-do"
  defp placeholder_for(:bulleted_list_item), do: "List"
  defp placeholder_for(:numbered_list_item), do: "List"
  defp placeholder_for(:code), do: "Code"
  defp placeholder_for(:toggle), do: "Toggle"
  defp placeholder_for(_), do: ""

  defp static_block(%{type: :divider} = _block),
    do: raw("<hr class=\"border-notion-divider my-2\" />")

  defp static_block(%{type: :image, props: %{"url" => url}} = _block) do
    safe = Phoenix.HTML.html_escape(url) |> Phoenix.HTML.safe_to_string()
    raw("<img src=\"" <> safe <> "\" class=\"max-w-full rounded\" />")
  end

  defp static_block(%{type: :image} = _block),
    do: raw("<div class=\"text-notion-text-light\">Image</div>")

  defp static_block(%{type: :bookmark, props: %{"url" => url}} = _block) do
    safe = Phoenix.HTML.html_escape(url) |> Phoenix.HTML.safe_to_string()

    raw(
      "<a href=\"" <>
        safe <>
        "\" target=\"_blank\" rel=\"noopener\" class=\"text-notion-blue underline\">" <>
        safe <> "</a>"
    )
  end

  defp static_block(%{type: :bookmark} = _block),
    do: raw("<div class=\"text-notion-text-light\">Bookmark</div>")

  defp static_block(%{type: :equation} = _block),
    do: raw("<div class=\"text-notion-text-light py-2\">Equation (KaTeX)</div>")

  defp static_block(%{type: :ai_answer} = block) do
    raw(
      "<ora-ai-block id=\"ai-#{block.id}\" block-id=\"#{block.id}\" state=\"#{ai_state(block.content)}\"></ora-ai-block>"
    )
  end

  defp static_block(_block), do: raw("")

  defp ai_state(content) when is_map(content) do
    if Map.get(content, "message_id") do
      "answered"
    else
      "empty"
    end
  end

  defp ai_state(_), do: "empty"
end
