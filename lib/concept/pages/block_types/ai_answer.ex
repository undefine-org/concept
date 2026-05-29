defmodule Concept.Pages.BlockTypes.AiAnswer do
  @moduledoc """
  AI Answer block — embeds RAG-powered answers inside Concept pages.

  Implemented as a `Phoenix.LiveComponent` via
  `Concept.Pages.BlockType.Interactive`. The macro:

  * generates `handle_event/3` clauses for `"evaluate"`, `"refresh"`, and
    `"retry"`, each dispatching to `Concept.Pages.evaluate_ai/4`;
  * wraps `render_body/1` in a `<div phx-hook="OraBlock" data-events="…">`
    so the JS hook can forward `ora-<verb>` `CustomEvent`s back to this LC.

  This module owns the cached preview HTML, staleness, and message-state
  derivation. The `<ora-ai-block>` Lit custom element handles the in-block UI
  (textarea, scope/profile pickers, streaming animation).
  """

  use Concept.Pages.BlockType.Interactive,
    ash_actions: [
      evaluate: [Concept.Pages, :evaluate_ai, [:prompt, :scope, :profile]],
      refresh: [Concept.Pages, :evaluate_ai, [:prompt, :scope, :profile]],
      retry: [Concept.Pages, :evaluate_ai, [:prompt, :scope, :profile]]
    ],
    mcp: [
      # refresh/retry both dispatch to the same `evaluate_ai` action; they are
      # UI affordances (re-run on drift / re-run after failure), not distinct
      # capabilities. Expose only `evaluate` to MCP to avoid duplicate tools.
      only: [:evaluate],
      descriptions: [
        evaluate:
          "Run the AI Answer block's prompt against the workspace and stream cited results into the block."
      ]
    ]

  @scopes ~w(subtree page workspace)

  @impl Concept.Pages.BlockType
  def type, do: :ai_answer

  @impl Concept.Pages.BlockType
  def default_content, do: %{}

  @impl Concept.Pages.BlockType
  def default_props, do: %{"prompt" => "", "scope" => "subtree", "model" => nil}

  @impl Concept.Pages.BlockType
  def validate_props(%{"scope" => s} = props) when s in @scopes, do: validate_prompt(props)
  def validate_props(_), do: {:error, "scope must be one of #{Enum.join(@scopes, ",")}"}

  defp validate_prompt(%{"prompt" => p}) when is_binary(p), do: :ok
  defp validate_prompt(_), do: {:error, "prompt must be a string"}

  @impl Concept.Pages.BlockType
  def lexical_node, do: "ai-answer"

  @impl Concept.Pages.BlockType
  def slash_menu,
    do: %{label: "AI Answer", icon: "✨", keywords: ~w(ai answer ask), group: :ai}

  # ---------------------------------------------------------------------------
  # LiveComponent lifecycle
  # ---------------------------------------------------------------------------

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    block = assigns.block
    state = derive_state(block)
    message_id = get_in(block.content, ["message_id"]) || ""

    {preview_html, staleness} =
      if state == "answered" do
        {render_preview(block), Concept.Pages.staleness_for_ai_block(block)}
      else
        {"", %{stale?: false, drifted_count: 0, drifted_block_ids: []}}
      end

    socket =
      socket
      |> assign(assigns)
      |> assign(:state, state)
      |> assign(:message_id, message_id)
      |> assign(:preview_html, preview_html)
      |> assign(:staleness, staleness)

    {:ok, socket}
  end

  @impl Concept.Pages.BlockType
  def render_body(assigns) do
    ~H"""
    <ora-ai-block
      id={"ora-ai-" <> @block.id}
      block-id={@block.id}
      message-id={@message_id}
      state={@state}
      preview-html={@preview_html}
      data-stale={to_string(@staleness.stale?)}
      data-drifted-count={@staleness.drifted_count}
      data-drifted-block-ids={Jason.encode!(@staleness.drifted_block_ids)}
    />
    """
  end

  # ---------------------------------------------------------------------------
  # Derivation helpers (moved from ConceptWeb.BlockRender)
  # ---------------------------------------------------------------------------

  defp derive_state(block) do
    case get_in(block.content, ["message_id"]) do
      nil ->
        "empty"

      message_id ->
        case load_message(message_id, block.workspace_id) do
          {:ok, %{complete: true}} -> "answered"
          {:ok, %{complete: false}} -> "streaming"
          {:error, _} -> "failed"
        end
    end
  end

  defp load_message(message_id, workspace_id) do
    Concept.Knowledge.Chat.Message
    |> Ash.get(message_id, actor: %{system?: true}, tenant: workspace_id, authorize?: false)
    |> case do
      {:ok, message} -> {:ok, message}
      error -> error
    end
  end

  defp render_preview(block) do
    message_id = get_in(block.content, ["message_id"])
    workspace_id = block.workspace_id
    system_actor = %{system?: true}

    with {:ok, message} <- load_message(message_id, workspace_id),
         {:ok, citations} <-
           Concept.Knowledge.citations_for_message(message_id,
             actor: system_actor,
             tenant: workspace_id
           ) do
      answer_html(message) <> citations_html(citations) <> why_this_answer_html(message)
    else
      _ -> ""
    end
  end

  defp answer_html(message) do
    {:safe, escaped_text} = Phoenix.HTML.html_escape(message.text)

    "<div class=\"ai-answer-text mb-4\"><pre class=\"whitespace-pre-wrap text-sm\">" <>
      IO.iodata_to_binary(escaped_text) <> "</pre></div>"
  end

  defp citations_html([]), do: ""

  defp citations_html(citations) when is_list(citations) do
    cards =
      citations
      |> Enum.map(fn citation ->
        {:safe, escaped_snippet} = Phoenix.HTML.html_escape(citation.snippet || "Source")

        "<div class=\"citation-card p-2 border rounded text-xs mb-1\">" <>
          IO.iodata_to_binary(escaped_snippet) <> "</div>"
      end)
      |> Enum.join("")

    "<div class=\"ai-citations mt-3\"><div class=\"text-xs font-medium text-gray-600 mb-2\">Sources:</div>" <>
      cards <> "</div>"
  end

  defp why_this_answer_html(message) do
    has_rewritten = message.rewritten_prompt != nil
    has_search = message.search_trace && length(message.search_trace) > 0
    has_kept = has_search && Enum.any?(message.search_trace, & &1["kept?"])
    has_grounding = message.grounding_score != nil

    prompt_section = prompt_section_html(message, has_rewritten)
    search_section = if has_search, do: search_section_html(message), else: ""
    rerank_section = if has_kept, do: rerank_section_html(message), else: ""
    generation_section = generation_section_html(message, has_grounding)

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

  defp prompt_section_html(message, true) do
    {:safe, original} = Phoenix.HTML.html_escape(message.text)
    {:safe, rewritten} = Phoenix.HTML.html_escape(message.rewritten_prompt)

    """
    <section class="ora-why-section-prompt">
      <h4 class="font-semibold text-zinc-900 dark:text-zinc-100">Prompt</h4>
      <div class="mt-1">
        <p class="text-xs text-zinc-500">Original:</p>
        <p class="text-sm">#{IO.iodata_to_binary(original)}</p>
        <p class="text-xs text-zinc-500 mt-2">Rewritten:</p>
        <p class="text-sm">#{IO.iodata_to_binary(rewritten)}</p>
      </div>
    </section>
    """
  end

  defp prompt_section_html(message, false) do
    {:safe, escaped} = Phoenix.HTML.html_escape(message.text)

    """
    <section class="ora-why-section-prompt">
      <h4 class="font-semibold text-zinc-900 dark:text-zinc-100">Prompt</h4>
      <p class="text-sm mt-1">#{IO.iodata_to_binary(escaped)}</p>
    </section>
    """
  end

  defp search_section_html(message) do
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

            "<p class=\"text-zinc-600 dark:text-zinc-400 mt-0.5 truncate\">" <>
              IO.iodata_to_binary(esc) <> "</p>"
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
  end

  defp rerank_section_html(message) do
    kept_count = Enum.count(message.search_trace, & &1["kept?"])

    """
    <section class="ora-why-section-reranking">
      <h4 class="font-semibold text-zinc-900 dark:text-zinc-100">Reranking</h4>
      <p class="text-xs text-zinc-500 mt-1">#{kept_count} chunks kept for generation</p>
    </section>
    """
  end

  defp generation_section_html(message, has_grounding) do
    latency =
      if message.latency_ms,
        do:
          "<div><dt class=\"inline font-medium\">Latency:</dt><dd class=\"inline ml-1\">#{message.latency_ms}ms</dd></div>",
        else: ""

    tokens =
      if message.prompt_tokens || message.completion_tokens,
        do:
          "<div><dt class=\"inline font-medium\">Tokens:</dt><dd class=\"inline ml-1\">#{message.prompt_tokens || 0} prompt, #{message.completion_tokens || 0} completion</dd></div>",
        else: ""

    grounding =
      if has_grounding,
        do:
          "<div><dt class=\"inline font-medium\">Grounding score:</dt><dd class=\"inline ml-1\">#{Float.round(message.grounding_score, 3)}</dd></div>",
        else: ""

    """
    <section class="ora-why-section-generation">
      <h4 class="font-semibold text-zinc-900 dark:text-zinc-100">Generation</h4>
      <dl class="mt-1 space-y-1 text-xs">
        #{latency}
        #{tokens}
        #{grounding}
      </dl>
    </section>
    """
  end
end
