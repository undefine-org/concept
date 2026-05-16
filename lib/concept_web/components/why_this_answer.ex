defmodule ConceptWeb.Components.WhyThisAnswer do
  @moduledoc """
  Disclosure component showing audit trail for AI responses:
  prompt, retrieval, reranking, and generation metadata.
  """
  use Phoenix.Component

  alias Concept.Knowledge.Chat.Message

  @doc """
  Renders a collapsible disclosure with audit trail sections.

  Sections are conditionally rendered based on available data:
  - Prompt: always shown (includes rewritten prompt if available)
  - Retrieval: search_trace
  - Reranking: search_trace with kept chunks
  - Generation: model + latency + tokens + grounding

  ## Attributes
    * `message` - The Message struct with audit fields
  """
  attr :message, Message, required: true

  def why_this_answer(assigns) do
    ~H"""
    <details class="ora-why-this-answer mt-2 text-sm text-zinc-600 dark:text-zinc-400">
      <summary class="cursor-pointer hover:text-zinc-900 dark:hover:text-zinc-200 font-medium">
        Why this answer?
      </summary>
      <div class="mt-2 space-y-4 pl-4 border-l-2 border-zinc-200 dark:border-zinc-700">
        <!-- Prompt Section -->
        <section class="ora-why-section-prompt">
          <h4 class="font-semibold text-zinc-900 dark:text-zinc-100">Prompt</h4>
          <%= if @message.rewritten_prompt do %>
            <div class="mt-1">
              <p class="text-xs text-zinc-500">Original:</p>
              <p class="text-sm">{@message.text}</p>
              <p class="text-xs text-zinc-500 mt-2">Rewritten:</p>
              <p class="text-sm">{@message.rewritten_prompt}</p>
            </div>
          <% else %>
            <p class="text-sm mt-1">{@message.text}</p>
          <% end %>
        </section>
        
    <!-- Retrieval Section -->
        <%= if @message.search_trace && length(@message.search_trace) > 0 do %>
          <section class="ora-why-section-retrieval">
            <h4 class="font-semibold text-zinc-900 dark:text-zinc-100">Retrieval</h4>
            <p class="text-xs text-zinc-500 mt-1">
              {length(@message.search_trace)} chunks retrieved
            </p>
            <ul class="mt-2 space-y-1">
              <%= for chunk <- @message.search_trace do %>
                <li class="text-xs">
                  <span class="font-mono text-zinc-700 dark:text-zinc-300">
                    score: {Float.round(chunk["score"] || 0.0, 3)}
                  </span>
                  <%= if chunk["kept?"] do %>
                    <span class="ml-2 text-green-600">✓ kept</span>
                  <% end %>
                  <%= if chunk["snippet"] do %>
                    <p class="text-zinc-600 dark:text-zinc-400 mt-0.5 truncate">
                      {chunk["snippet"]}
                    </p>
                  <% end %>
                </li>
              <% end %>
            </ul>
          </section>
        <% end %>
        
    <!-- Reranking Section (only kept chunks) -->
        <%= if @message.search_trace && Enum.any?(@message.search_trace, & &1["kept?"]) do %>
          <section class="ora-why-section-reranking">
            <h4 class="font-semibold text-zinc-900 dark:text-zinc-100">Reranking</h4>
            <p class="text-xs text-zinc-500 mt-1">
              {Enum.count(@message.search_trace, & &1["kept?"])} chunks kept for generation
            </p>
          </section>
        <% end %>
        
    <!-- Generation Section -->
        <section class="ora-why-section-generation">
          <h4 class="font-semibold text-zinc-900 dark:text-zinc-100">Generation</h4>
          <dl class="mt-1 space-y-1 text-xs">
            <%= if @message.latency_ms do %>
              <div>
                <dt class="inline font-medium">Latency:</dt>
                <dd class="inline ml-1">{@message.latency_ms}ms</dd>
              </div>
            <% end %>
            <%= if @message.prompt_tokens || @message.completion_tokens do %>
              <div>
                <dt class="inline font-medium">Tokens:</dt>
                <dd class="inline ml-1">
                  {@message.prompt_tokens || 0} prompt, {@message.completion_tokens || 0} completion
                </dd>
              </div>
            <% end %>
            <%= if @message.grounding_score do %>
              <div>
                <dt class="inline font-medium">Grounding score:</dt>
                <dd class="inline ml-1">{Float.round(@message.grounding_score, 3)}</dd>
              </div>
            <% end %>
          </dl>
        </section>
      </div>
    </details>
    """
  end
end
