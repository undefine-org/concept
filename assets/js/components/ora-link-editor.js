import { LitElement, html, css } from "lit";

export class OraLinkEditor extends LitElement {
  static styles = css`
    :host {
      display: none;
      position: absolute;
      background: white;
      border: 1px solid #e5e5e5;
      border-radius: 8px;
      box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
      padding: 8px;
      gap: 8px;
      z-index: 50;
      font-family: Inter, system-ui, sans-serif;
      flex-direction: column;
    }
    :host([visible]) {
      display: flex;
    }
    input {
      border: 1px solid #ddd;
      border-radius: 4px;
      padding: 6px 8px;
      font-size: 13px;
      outline: none;
      width: 240px;
      box-sizing: border-box;
    }
    input:focus {
      border-color: #3b82f6;
    }
    .actions {
      display: flex;
      justify-content: flex-end;
      gap: 6px;
      margin-top: 4px;
    }
    button {
      padding: 4px 10px;
      border-radius: 4px;
      border: none;
      font-size: 12px;
      cursor: pointer;
    }
    .apply {
      background: #3b82f6;
      color: white;
    }
    .remove {
      background: #f5f5f5;
      color: #333;
    }
  `;

  static properties = {
    visible: { type: Boolean, reflect: true },
    url: { type: String },
  };

  constructor() {
    super();
    this.visible = false;
    this.url = "";
  }

  firstUpdated() {
    this._focusInput();
  }

  updated(changed) {
    if (changed.has("visible") && this.visible) {
      this._focusInput();
    }
  }

  _focusInput() {
    const input = this.renderRoot.querySelector("input");
    if (input) {
      input.focus();
      input.select();
    }
  }

  _apply() {
    const input = this.renderRoot.querySelector("input");
    const value = input?.value?.trim() || "";
    this.dispatchEvent(
      new CustomEvent("apply-link", {
        detail: { url: value },
        bubbles: true,
        composed: true,
      })
    );
    this.visible = false;
  }

  _remove() {
    this.dispatchEvent(
      new CustomEvent("apply-link", {
        detail: { url: "" },
        bubbles: true,
        composed: true,
      })
    );
    this.visible = false;
  }

  _onKeyDown(e) {
    if (e.key === "Enter") {
      e.preventDefault();
      this._apply();
    } else if (e.key === "Escape") {
      e.preventDefault();
      this.visible = false;
    }
  }

  render() {
    return html`
      <input
        type="text"
        placeholder="https://..."
        .value=${this.url}
        @keydown=${this._onKeyDown}
      />
      <div class="actions">
        <button class="remove" @click=${this._remove}>Remove</button>
        <button class="apply" @click=${this._apply}>Apply</button>
      </div>
    `;
  }
}

if (!customElements.get("ora-link-editor")) {
  customElements.define("ora-link-editor", OraLinkEditor);
}
