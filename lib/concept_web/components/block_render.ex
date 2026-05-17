defmodule ConceptWeb.BlockRender do
  @moduledoc "Function component that dispatches per block type to its template."
  use Phoenix.Component

  import Phoenix.HTML

  @text_types ~w(
    paragraph heading_1 heading_2 heading_3 quote
    callout to_do bulleted_list_item numbered_list_item code toggle
    table_cell column
  )

  attr :block, :map, required: true
  attr :locked_by, :map, default: nil
  attr :locked_blocks, :map, default: %{}

  def block(assigns) do
    assigns = assign(assigns, :type, to_string(assigns.block.type))

    cond do
      assigns.type == "table" -> composite_table(assigns)
      assigns.type == "columns" -> composite_columns(assigns)
      assigns.type in @text_types -> text_block(assigns)
      true ->
        ~H"""
        <div id={"block-" <> @block.id} class="block-anchor scroll-mt-20">
          {static_block(@block)}
        </div>
        """
    end
  end

  defp text_block(assigns) do
    ~H"""
    <div id={"block-" <> @block.id} class="block-anchor scroll-mt-20">
      <div
        class="ora-block-row group"
        data-block-id={@block.id}
        data-locked-by={@locked_by && @locked_by.user_id}
        style={@locked_by && "--lock-color: #{@locked_by.color}"}
      >
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
  end

  defp composite_table(assigns) do
    rows = get_in(assigns.block.props, ["rows"]) || 0
    cols = get_in(assigns.block.props, ["cols"]) || 0
    cells = composite_children(assigns.block)

    grid =
      Enum.chunk_every(
        Enum.sort_by(cells, fn c ->
          {get_in(c.props, ["row_index"]) || 0, get_in(c.props, ["col_index"]) || 0}
        end),
        max(cols, 1)
      )

    assigns = assign(assigns, rows: rows, cols: cols, grid: grid)

    ~H"""
    <div
      id={"block-" <> @block.id}
      class="block-anchor scroll-mt-20 ora-composite-table"
      data-block-id={@block.id}
      data-composite-parent="table"
      data-rows={@rows}
      data-cols={@cols}
    >
      <table class="ora-table border-collapse w-full">
        <tbody>
          <tr :for={row <- @grid} class="ora-table-row">
            <td :for={cell <- row} class="ora-table-cell border border-notion-divider align-top p-1">
              <.block block={cell} locked_by={@locked_blocks[cell.id]} locked_blocks={@locked_blocks} />
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp composite_columns(assigns) do
    children =
      assigns.block
      |> composite_children()
      |> Enum.sort_by(& &1.position)

    count = get_in(assigns.block.props, ["count"]) || length(children)
    assigns = assign(assigns, children: children, count: count)

    ~H"""
    <div
      id={"block-" <> @block.id}
      class="block-anchor scroll-mt-20 ora-composite-columns"
      data-block-id={@block.id}
      data-composite-parent="columns"
      data-count={@count}
    >
      <div class="grid gap-2" style={"grid-template-columns: repeat(#{@count}, minmax(0, 1fr));"}>
        <div :for={child <- @children} class="ora-column" data-block-id={child.id}>
          <.block block={child} locked_by={@locked_blocks[child.id]} locked_blocks={@locked_blocks} />
        </div>
      </div>
    </div>
    """
  end

  defp composite_children(%{children: %Ash.NotLoaded{}}), do: []
  defp composite_children(%{children: nil}), do: []
  defp composite_children(%{children: children}) when is_list(children), do: children
  defp composite_children(_), do: []

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
    state = ai_block_state(block)
    message_id = get_in(block.content, ["message_id"]) || ""

    {preview_html, staleness_attrs} =
      if state == "answered" do
        preview = render_ai_answer_preview(block)
        staleness = Concept.Pages.staleness_for_ai_block(block)

        attrs =
          if staleness.stale? do
            " data-stale=\"true\" data-drifted-count=\"#{staleness.drifted_count}\" data-drifted-block-ids=\"#{Jason.encode!(staleness.drifted_block_ids)}\""
          else
            " data-stale=\"false\""
          end

        {preview, attrs}
      else
        {"", ""}
      end

    safe_preview = Phoenix.HTML.html_escape(preview_html) |> Phoenix.HTML.safe_to_string()

    raw(
      "<ora-ai-block id=\"ai-#{block.id}\" block-id=\"#{block.id}\" message-id=\"#{message_id}\" state=\"#{state}\" preview-html=\"#{safe_preview}\"#{staleness_attrs}></ora-ai-block>"
    )
  end

  defp static_block(_block), do: raw("")

  defp ai_block_state(block) do
    message_id = get_in(block.content, ["message_id"])

    cond do
      is_nil(message_id) ->
        "empty"

      true ->
        # Try to load message to check completion status
        case load_message(message_id, block.workspace_id) do
          {:ok, %{complete: true}} -> "answered"
          {:ok, %{complete: false}} -> "streaming"
          {:error, _} -> "failed"
        end
    end
  end

  defp load_message(message_id, _workspace_id) do
    system_actor = %{system?: true}

    Concept.Knowledge.Chat.Message
    |> Ash.get(message_id, actor: system_actor, authorize?: false)
    |> case do
      {:ok, message} -> {:ok, message}
      error -> error
    end
  end

  defp render_ai_answer_preview(block) do
    message_id = get_in(block.content, ["message_id"])
    workspace_id = block.workspace_id
    system_actor = %{system?: true}

    with {:ok, message} <- load_message(message_id, workspace_id),
         {:ok, citations} <-
           Concept.Knowledge.citations_for_message(message_id,
             actor: system_actor,
             tenant: workspace_id
           ) do
      # Render answer text
      {:safe, escaped_text} = Phoenix.HTML.html_escape(message.text)

      answer_html =
        "<div class=\"ai-answer-text mb-4\"><pre class=\"whitespace-pre-wrap text-sm\">#{IO.iodata_to_binary(escaped_text)}</pre></div>"

      # Render citations if any
      citations_html =
        if length(citations) > 0 do
          citation_cards =
            citations
            |> Enum.map(fn citation ->
              # This is a simplified rendering; in production you'd use the full component
              {:safe, escaped_snippet} = Phoenix.HTML.html_escape(citation.snippet || "Source")

              "<div class=\"citation-card p-2 border rounded text-xs mb-1\">#{IO.iodata_to_binary(escaped_snippet)}</div>"
            end)
            |> Enum.join("")

          "<div class=\"ai-citations mt-3\"><div class=\"text-xs font-medium text-gray-600 mb-2\">Sources:</div>#{citation_cards}</div>"
        else
          ""
        end

      # Render why_this_answer disclosure
      why_html = render_why_this_answer_html(message)

      answer_html <> citations_html <> why_html
    else
      _ -> ""
    end
  end

  defp render_why_this_answer_html(message) do
    # Manually construct HTML for why_this_answer disclosure
    has_rewritten = message.rewritten_prompt != nil
    has_search = message.search_trace && length(message.search_trace) > 0
    has_kept = has_search && Enum.any?(message.search_trace, & &1["kept?"])
    has_grounding = message.grounding_score != nil

    prompt_section = """
    <section class="ora-why-section-prompt">
      <h4 class="font-semibold text-zinc-900 dark:text-zinc-100">Prompt</h4>
      #{if has_rewritten do
      {:safe, escaped_original} = Phoenix.HTML.html_escape(message.text)
      {:safe, escaped_rewritten} = Phoenix.HTML.html_escape(message.rewritten_prompt)
      """
      <div class="mt-1">
        <p class="text-xs text-zinc-500">Original:</p>
        <p class="text-sm">#{IO.iodata_to_binary(escaped_original)}</p>
        <p class="text-xs text-zinc-500 mt-2">Rewritten:</p>
        <p class="text-sm">#{IO.iodata_to_binary(escaped_rewritten)}</p>
      </div>
      """
    else
      {:safe, escaped_text} = Phoenix.HTML.html_escape(message.text)
      "<p class=\"text-sm mt-1\">#{IO.iodata_to_binary(escaped_text)}</p>"
    end}
    </section>
    """

    search_section =
      if has_search do
        chunk_count = length(message.search_trace)

        chunk_items =
          message.search_trace
          |> Enum.map(fn chunk ->
            score = Float.round(chunk["score"] || 0.0, 3)

            kept =
              if chunk["kept?"], do: "<span class=\"ml-2 text-green-600\">✓ kept</span>", else: ""

            snippet =
              if chunk["snippet"] do
                {:safe, esc} = Phoenix.HTML.html_escape(chunk["snippet"])

                "<p class=\"text-zinc-600 dark:text-zinc-400 mt-0.5 truncate\">#{IO.iodata_to_binary(esc)}</p>"
              else
                ""
              end

            """
            <li class="text-xs">
              <span class="font-mono text-zinc-700 dark:text-zinc-300">score: #{score}</span>
              #{kept}
              #{snippet}
            </li>
            """
          end)
          |> Enum.join("")

        """
        <section class="ora-why-section-retrieval">
          <h4 class="font-semibold text-zinc-900 dark:text-zinc-100">Retrieval</h4>
          <p class="text-xs text-zinc-500 mt-1">#{chunk_count} chunks retrieved</p>
          <ul class="mt-2 space-y-1">#{chunk_items}</ul>
        </section>
        """
      else
        ""
      end

    rerank_section =
      if has_kept do
        kept_count = Enum.count(message.search_trace, & &1["kept?"])

        """
        <section class="ora-why-section-reranking">
          <h4 class="font-semibold text-zinc-900 dark:text-zinc-100">Reranking</h4>
          <p class="text-xs text-zinc-500 mt-1">#{kept_count} chunks kept for generation</p>
        </section>
        """
      else
        ""
      end

    generation_section = """
    <section class="ora-why-section-generation">
      <h4 class="font-semibold text-zinc-900 dark:text-zinc-100">Generation</h4>
      <dl class="mt-1 space-y-1 text-xs">
        #{if message.latency_ms, do: "<div><dt class=\"inline font-medium\">Latency:</dt><dd class=\"inline ml-1\">#{message.latency_ms}ms</dd></div>", else: ""}
        #{if message.prompt_tokens || message.completion_tokens, do: "<div><dt class=\"inline font-medium\">Tokens:</dt><dd class=\"inline ml-1\">#{message.prompt_tokens || 0} prompt, #{message.completion_tokens || 0} completion</dd></div>", else: ""}
        #{if has_grounding, do: "<div><dt class=\"inline font-medium\">Grounding score:</dt><dd class=\"inline ml-1\">#{Float.round(message.grounding_score, 3)}</dd></div>", else: ""}
      </dl>
    </section>
    """

    """
    <details class="ora-why-this-answer mt-2 text-sm text-zinc-600 dark:text-zinc-400">
      <summary class="cursor-pointer hover:text-zinc-900 dark:hover:text-zinc-200 font-medium">Why this answer?</summary>
      <div class="mt-2 space-y-4 pl-4 border-l-2 border-zinc-200 dark:border-zinc-700">
        #{prompt_section}
        #{search_section}
        #{rerank_section}
        #{generation_section}
      </div>
    </details>
    """
  end
end
