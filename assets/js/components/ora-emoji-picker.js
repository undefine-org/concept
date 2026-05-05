import { LitElement, html } from "lit";
import emojis from "../data/emojis.js";

export class OraEmojiPicker extends LitElement {
  static properties = {
    filter: { type: String, state: true },
    _selectedIndex: { type: Number, state: true },
  };

  constructor() {
    super();
    this.filter = "";
    this._selectedIndex = 0;
  }

  createRenderRoot() {
    return this;
  }

  get filtered() {
    const q = this.filter.toLowerCase();
    if (!q) return emojis;
    return emojis.filter(
      (e) =>
        e.name.includes(q) || e.keywords.some((k) => k.includes(q)),
    );
  }

  firstUpdated() {
    const input = this.querySelector(".ora-emoji-picker-filter");
    if (input) input.focus();
  }

  render() {
    const list = this.filtered;
    return html`
      <div class="ora-emoji-picker" @keydown=${this._onKeydown}>
        <input
          type="text"
          class="ora-emoji-picker-filter"
          placeholder="Filter..."
          .value=${this.filter}
          @input=${(e) => {
            this.filter = e.target.value;
            this._selectedIndex = 0;
          }}
        />
        <div class="ora-emoji-picker-grid">
          ${list.map(
            (e, i) => html`
              <button
                type="button"
                class="ora-emoji-picker-btn ${i === this._selectedIndex ? "selected" : ""}"
                @click=${() => this._select(e.emoji)}
                tabindex="-1"
              >
                ${e.emoji}
              </button>
            `,
          )}
        </div>
      </div>
    `;
  }

  _onKeydown(e) {
    const cols = 8;
    const list = this.filtered;
    if (e.key === "ArrowDown") {
      e.preventDefault();
      this._selectedIndex = Math.min(this._selectedIndex + cols, list.length - 1);
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      this._selectedIndex = Math.max(this._selectedIndex - cols, 0);
    } else if (e.key === "ArrowRight") {
      e.preventDefault();
      this._selectedIndex = Math.min(this._selectedIndex + 1, list.length - 1);
    } else if (e.key === "ArrowLeft") {
      e.preventDefault();
      this._selectedIndex = Math.max(this._selectedIndex - 1, 0);
    } else if (e.key === "Enter") {
      e.preventDefault();
      if (list[this._selectedIndex]) {
        this._select(list[this._selectedIndex].emoji);
      }
    } else if (e.key === "Escape") {
      e.preventDefault();
      this.dispatchEvent(
        new CustomEvent("close", { bubbles: true, composed: true }),
      );
    }
  }

  _select(emoji) {
    this.dispatchEvent(
      new CustomEvent("select", { detail: emoji, bubbles: true, composed: true }),
    );
  }
}

customElements.define("ora-emoji-picker", OraEmojiPicker);
