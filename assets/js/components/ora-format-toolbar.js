import { LitElement, html, css } from "lit";

function closestBlock(node) {
  while (node) {
    if (
      node.nodeType === Node.ELEMENT_NODE &&
      node.tagName === "ORA-BLOCK"
    ) {
      return node;
    }
    if (node instanceof ShadowRoot) {
      node = node.host;
    } else if (node.nodeType === Node.DOCUMENT_NODE) {
      return null;
    } else {
      node = node.parentNode;
    }
  }
  return null;
}

export class OraFormatToolbar extends LitElement {
  static styles = css`
    :host {
      display: none;
      position: absolute;
      background: #1f1f1f;
      color: white;
      border-radius: 6px;
      padding: 4px;
      gap: 2px;
      z-index: 50;
      font-family: Inter, system-ui, sans-serif;
      box-shadow: 0 4px 12px rgba(0, 0, 0, 0.2);
      white-space: nowrap;
    }
    :host([visible]) {
      display: flex;
    }
    button {
      background: transparent;
      border: none;
      color: #ccc;
      cursor: pointer;
      padding: 4px 8px;
      border-radius: 4px;
      font-size: 13px;
      line-height: 1;
      min-width: 28px;
      text-align: center;
    }
    button:hover {
      background: #333;
      color: white;
    }
    button.active {
      color: #3b82f6;
    }
  `;

  static properties = {
    visible: { type: Boolean, reflect: true },
  };

  constructor() {
    super();
    this.visible = false;
  }

  connectedCallback() {
    super.connectedCallback();
    this._selectionHandler = this._onSelectionChange.bind(this);
    document.addEventListener("selectionchange", this._selectionHandler);
  }

  disconnectedCallback() {
    super.disconnectedCallback();
    document.removeEventListener("selectionchange", this._selectionHandler);
  }

  _onSelectionChange() {
    const sel = document.getSelection();
    if (!sel || sel.rangeCount === 0) {
      this.visible = false;
      return;
    }

    const range = sel.getRangeAt(0);
    if (range.collapsed) {
      this.visible = false;
      return;
    }

    const startBlock = closestBlock(range.startContainer);
    const endBlock = closestBlock(range.endContainer);

    if (!startBlock || startBlock !== endBlock) {
      this.visible = false;
      return;
    }

    this.visible = true;

    // Position after the browser has calculated our size
    this.updateComplete.then(() => {
      const rect = range.getBoundingClientRect();
      const toolbarRect = this.getBoundingClientRect();
      const parentRect = this.offsetParent
        ? this.offsetParent.getBoundingClientRect()
        : { left: 0, top: 0 };

      const left =
        rect.left -
        parentRect.left +
        rect.width / 2 -
        toolbarRect.width / 2;
      const top = rect.top - parentRect.top - toolbarRect.height - 8;

      this.style.left = `${Math.max(0, left)}px`;
      this.style.top = `${Math.max(0, top)}px`;
    });
  }

  _toggleFormat(format) {
    this.dispatchEvent(
      new CustomEvent("toggle-format", {
        detail: { format },
        bubbles: true,
        composed: true,
      })
    );
  }

  _requestLink() {
    this.dispatchEvent(
      new CustomEvent("request-link", { bubbles: true, composed: true })
    );
  }

  _askSelection() {
    const sel = document.getSelection();
    if (!sel || sel.rangeCount === 0) return;

    const range = sel.getRangeAt(0);
    const text = range.toString();
    if (!text) return;

    // Find closest ora-block
    const startBlock = closestBlock(range.startContainer);
    const blockId = startBlock?.id || undefined;

    // Find page_id from URL or data attribute
    const pageId = this._getPageId();

    this.dispatchEvent(
      new CustomEvent("ora-ask-selection", {
        detail: { text, blockId, pageId },
        bubbles: true,
        composed: true,
      })
    );
  }

  _getPageId() {
    // Try to get from URL pattern /w/<slug>/p/<page_id>
    const match = window.location.pathname.match(/\/p\/([^/]+)/);
    if (match) return match[1];

    // Fallback: look for data attribute on page editor root
    const editorRoot = document.getElementById("page-editor-root");
    return editorRoot?.dataset?.pageId || undefined;
  }
  _askSelection() {
    const sel = document.getSelection();
    if (!sel || sel.rangeCount === 0) return;

    const range = sel.getRangeAt(0);
    const text = range.toString();
    if (!text) return;

    // Find closest ora-block
    const startBlock = closestBlock(range.startContainer);
    const blockId = startBlock?.id || undefined;

    // Find page_id from URL or data attribute
    const pageId = this._getPageId();

    this.dispatchEvent(
      new CustomEvent("ora-ask-selection", {
        detail: { text, blockId, pageId },
        bubbles: true,
        composed: true,
      })
    );
  }

  _getPageId() {
    // Try to get from URL pattern /w/<slug>/p/<page_id>
    const match = window.location.pathname.match(/\/p\/([^/]+)/);
    if (match) return match[1];

    // Fallback: look for data attribute on page editor root
    const editorRoot = document.getElementById("page-editor-root");
    return editorRoot?.dataset?.pageId || undefined;
  }
  render() {
    const formats = [
      { key: "bold", label: "B" },
      { key: "italic", label: "I" },
      { key: "underline", label: "U" },
      { key: "strikethrough", label: "S" },
      { key: "code", label: "</>" },
    ];
    const preventBlur = (e) => e.preventDefault();
    return html`
      ${formats.map(
        (f) => html`
          <button @mousedown=${preventBlur} @click=${() => this._toggleFormat(f.key)}>${f.label}</button>
        `
      )}
      <button @mousedown=${preventBlur} @click=${this._requestLink}>🔗</button>
      <button @mousedown=${preventBlur} @click=${this._askSelection} title="Ask about this">✨</button>
    `;
  }
}

if (!customElements.get("ora-format-toolbar")) {
  customElements.define("ora-format-toolbar", OraFormatToolbar);
}
