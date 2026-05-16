import { LitElement, html } from "lit";
import { unsafeHTML } from "lit/directives/unsafe-html.js";

/**
 * Citation preview popover.
 * 
 * Wraps a citation card and provides hover-triggered preview functionality.
 * On mouseenter (300ms debounce), dispatches a 'citation-preview-request' event
 * that the parent LiveView can handle to fetch block preview HTML.
 * 
 * @fires citation-preview-request - Dispatched after hover debounce, parent should reply with preview HTML
 * @attr {boolean} open - Controls popover visibility
 * @attr {string} preview-html - HTML content to display in popover
 * @attr {string} data-block-id - Block ID for preview request
 */
export class OraCitationPopover extends LitElement {
  static properties = {
    open: { type: Boolean, reflect: true },
    previewHtml: { type: String, attribute: "preview-html" },
  };

  constructor() {
    super();
    this.open = false;
    this.previewHtml = "";
    this._hoverTimer = null;
    this._boundHandleClickOutside = this._handleClickOutside.bind(this);
  }

  // Use light DOM for Tailwind CSS compatibility
  createRenderRoot() {
    return this;
  }

  connectedCallback() {
    super.connectedCallback();
    this.addEventListener("mouseenter", this._onMouseEnter);
    this.addEventListener("mouseleave", this._onMouseLeave);
  }

  disconnectedCallback() {
    super.disconnectedCallback();
    this.removeEventListener("mouseenter", this._onMouseEnter);
    this.removeEventListener("mouseleave", this._onMouseLeave);
    this._clearHoverTimer();
    this._removeClickOutsideListener();
  }

  updated(changedProperties) {
    super.updated(changedProperties);
    
    if (changedProperties.has("open")) {
      if (this.open) {
        this._addClickOutsideListener();
      } else {
        this._removeClickOutsideListener();
      }
    }
  }

  render() {
    return html`
      <div class="ora-citation-popover-wrapper">
        <slot></slot>
        ${this.open && this.previewHtml
          ? html`
              <div class="ora-citation-popover-content">
                ${unsafeHTML(this.previewHtml)}
              </div>
            `
          : null}
      </div>
    `;
  }

  _onMouseEnter = () => {
    this._clearHoverTimer();
    this._hoverTimer = setTimeout(() => {
      this._requestPreview();
    }, 300);
  };

  _onMouseLeave = () => {
    this._clearHoverTimer();
  };

  _clearHoverTimer() {
    if (this._hoverTimer) {
      clearTimeout(this._hoverTimer);
      this._hoverTimer = null;
    }
  }

  _requestPreview() {
    const blockId = this.getAttribute("data-block-id");
    if (!blockId) return;

    this.dispatchEvent(
      new CustomEvent("citation-preview-request", {
        detail: { blockId },
        bubbles: true,
        composed: true,
      })
    );
  }

  _addClickOutsideListener() {
    // Small delay to avoid immediate closure from the same click
    setTimeout(() => {
      document.addEventListener("mousedown", this._boundHandleClickOutside);
    }, 0);
  }

  _removeClickOutsideListener() {
    document.removeEventListener("mousedown", this._boundHandleClickOutside);
  }

  _handleClickOutside(event) {
    if (!this.contains(event.target)) {
      this.open = false;
      this.previewHtml = "";
    }
  }
}

customElements.define("ora-citation-popover", OraCitationPopover);
