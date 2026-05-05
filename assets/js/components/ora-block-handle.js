import { LitElement, html, css } from "lit";

export class OraBlockHandle extends LitElement {
  static styles = css`
    :host {
      display: flex;
      align-items: center;
      gap: 2px;
      opacity: 0;
      transition: opacity 0.15s ease;
      pointer-events: auto;
    }
    /* Parent block is expected to have Tailwind 'group' class and
       apply 'group-hover:opacity-100' to this element in the light DOM. */
    :host(.group-hover\:opacity-100) {
      opacity: 1;
    }
    button {
      background: transparent;
      border: none;
      cursor: pointer;
      padding: 2px 4px;
      color: #a3a3a3;
      font-size: 14px;
      line-height: 1;
      border-radius: 4px;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    button:hover {
      background: #f0f0f0;
      color: #37352f;
    }
    .ora-drag-handle {
      cursor: grab;
      letter-spacing: -1px;
    }
    .ora-drag-handle:active {
      cursor: grabbing;
    }
  `;

  render() {
    return html`
      <button
        class="ora-add-below"
        title="Add block below"
        @click=${this._onAdd}
      >
        +
      </button>
      <button
        class="ora-drag-handle"
        title="Drag to move"
        @click=${this._onMenu}
      >
        ⋮⋮
      </button>
    `;
  }

  _onAdd(e) {
    e.stopPropagation();
    this.dispatchEvent(
      new CustomEvent("add-below", { bubbles: true, composed: true })
    );
  }

  _onMenu(e) {
    e.stopPropagation();
    this.dispatchEvent(
      new CustomEvent("open-menu", { bubbles: true, composed: true })
    );
  }
}

if (!customElements.get("ora-block-handle")) {
  customElements.define("ora-block-handle", OraBlockHandle);
}
