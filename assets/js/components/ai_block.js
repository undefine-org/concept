import { LitElement, html, css } from "lit";

export class OraAiBlock extends LitElement {
  static properties = {
    blockId: { type: String, attribute: "block-id" },
    messageId: { type: String, attribute: "message-id" },
    state: { type: String },
    previewHtml: { type: String, attribute: "preview-html" },
    stale: { type: Boolean, attribute: "data-stale" },
    driftedCount: { type: Number, attribute: "data-drifted-count" },
    driftedBlockIds: { type: String, attribute: "data-drifted-block-ids" },
    _prompt: { type: String, state: true },
    _scope: { type: String, state: true },
    _profile: { type: String, state: true },
    _streamingText: { type: String, state: true },
  };

  constructor() {
    super();
    this.state = "empty";
    this._prompt = "";
    this._scope = "workspace";
    this._profile = "default";
    this._streamingText = "";
  }

  // Light DOM for Tailwind compatibility
  createRenderRoot() {
    return this;
  }

  render() {
    switch (this.state) {
      case "empty":
        return this._renderEmpty();
      case "streaming":
        return this._renderStreaming();
      case "answered":
        return this._renderAnswered();
      case "failed":
        return this._renderFailed();
      default:
        return html`<div class="text-gray-500">Unknown state: ${this.state}</div>`;
    }
  }

  _renderEmpty() {
    return html`
      <div class="ai-block-empty border border-gray-200 rounded-lg p-4 space-y-3">
        <div class="flex items-center gap-2 text-sm text-gray-600">
          <span class="text-xl">✨</span>
          <span class="font-medium">AI Answer</span>
        </div>
        
        <textarea
          class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 resize-none"
          placeholder="Ask a question about your workspace..."
          rows="3"
          @input=${(e) => (this._prompt = e.target.value)}
          .value=${this._prompt}
        ></textarea>
        
        <div class="flex gap-3 items-center">
          <select
            class="px-3 py-1.5 text-sm border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
            @change=${(e) => (this._scope = e.target.value)}
            .value=${this._scope}
          >
            <option value="workspace">Workspace</option>
            <option value="page">This page</option>
            <option value="subtree">This section</option>
          </select>
          
          <select
            class="px-3 py-1.5 text-sm border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
            @change=${(e) => (this._profile = e.target.value)}
            .value=${this._profile}
          >
            <option value="fast">Fast</option>
            <option value="default">Default</option>
            <option value="thorough">Thorough</option>
          </select>
          
          <button
            class="px-4 py-1.5 text-sm font-medium text-white bg-blue-600 rounded-md hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 disabled:opacity-50 disabled:cursor-not-allowed"
            @click=${this._onGenerate}
            ?disabled=${!this._prompt.trim()}
          >
            Generate
          </button>
        </div>
      </div>
    `;
  }

  _renderStreaming() {
    return html`
      <div class="ai-block-streaming border border-blue-200 rounded-lg p-4 space-y-3 bg-blue-50">
        <div class="flex items-center gap-2 text-sm text-blue-700">
          <span class="animate-pulse">✨</span>
          <span class="font-medium">Generating answer...</span>
        </div>
        
        <div class="text-gray-800 whitespace-pre-wrap font-mono text-sm">
          ${this._streamingText || "Starting..."}
        </div>
      </div>
    `;
  }

  _renderAnswered() {
    return html`
      <div class="ai-block-answered border border-gray-200 rounded-lg p-4 space-y-3">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2 text-sm text-gray-600">
            <span class="text-xl">✨</span>
            <span class="font-medium">AI Answer</span>
          </div>
          
          <button
            class="px-3 py-1 text-xs font-medium text-gray-700 bg-gray-100 rounded-md hover:bg-gray-200 focus:outline-none focus:ring-2 focus:ring-gray-400"
            @click=${this._onRefresh}
          >
            Refresh
          </button>
        </div>
        
        ${this.stale
          ? html`
              <button
                @click=${this._onRefresh}
                class="flex items-center gap-2 px-3 py-2 text-xs font-medium text-yellow-800 bg-yellow-50 border border-yellow-200 rounded-md hover:bg-yellow-100 focus:outline-none focus:ring-2 focus:ring-yellow-400 w-full"
              >
                <span>⚠️</span>
                <span>Context drifted (${this.driftedCount} source ${this.driftedCount === 1 ? 'block' : 'blocks'} edited since)</span>
              </button>
            `
          : ''}
        
        <div class="prose prose-sm max-w-none">
          ${this.previewHtml
            ? html`<div .innerHTML=${this.previewHtml}></div>`
            : html`<pre class="whitespace-pre-wrap text-sm">${this._getAnswerText()}</pre>`}
        </div>
      </div>
    `;
  }

  _renderFailed() {
    return html`
      <div class="ai-block-failed border border-red-200 rounded-lg p-4 space-y-3 bg-red-50">
        <div class="flex items-center gap-2 text-sm text-red-700">
          <span>⚠️</span>
          <span class="font-medium">Failed to generate answer</span>
        </div>
        
        <div class="flex gap-2">
          <button
            class="px-4 py-1.5 text-sm font-medium text-white bg-red-600 rounded-md hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-red-500"
            @click=${this._onRetry}
          >
            Retry
          </button>
        </div>
      </div>
    `;
  }

  _dispatch(verb) {
    // Wiring source-of-truth lives in the `ash_actions` declaration on the
    // server-side BlockType module; the OraBlock hook injects `block_id` from
    // the wrapper's `data-block-id` attribute, so we omit it here.
    this.dispatchEvent(
      new CustomEvent(`ora-${verb}`, {
        bubbles: true,
        composed: true,
        detail: {
          prompt: this._prompt,
          scope: this._scope,
          profile: this._profile,
        },
      })
    );
  }

  _onGenerate() {
    if (!this._prompt.trim()) return;
    this._dispatch("evaluate");
  }

  _onRefresh() {
    this._dispatch("refresh");
  }

  _onRetry() {
    this._dispatch("retry");
  }

  _getAnswerText() {
    // Placeholder for when previewHtml is not available
    return this._streamingText || "Answer content here";
  }

  // Method to be called by hook when streaming tokens arrive
  appendToken(token) {
    this._streamingText += token;
  }

  // Method to be called by hook when streaming completes
  completeStreaming() {
    this.state = "answered";
  }

  // Method to be called by hook when staleness changes
  updateStaleness(stale, driftedCount, driftedBlockIds) {
    this.stale = stale;
    this.driftedCount = driftedCount;
    this.driftedBlockIds = JSON.stringify(driftedBlockIds);
  }
}

if (!customElements.get("ora-ai-block")) {
  customElements.define("ora-ai-block", OraAiBlock);
}
