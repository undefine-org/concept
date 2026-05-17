import { LitElement, html, css } from "lit";

const GROUP_ORDER = ["basic", "list", "media", "advanced"];

const FALLBACK_ITEMS = [
  { type: "ai_answer", label: "AI answer", icon: "✨", group: "ai" },
  { type: "paragraph", label: "Text", icon: "T", group: "basic" },
  { type: "heading_1", label: "Heading 1", icon: "H1", group: "basic" },
  { type: "heading_2", label: "Heading 2", icon: "H2", group: "basic" },
  { type: "heading_3", label: "Heading 3", icon: "H3", group: "basic" },
  { type: "to_do", label: "To-do list", icon: "☐", group: "list" },
  { type: "bulleted_list_item", label: "Bulleted list", icon: "•", group: "list" },
  { type: "numbered_list_item", label: "Numbered list", icon: "1.", group: "list" },
  { type: "quote", label: "Quote", icon: '"', group: "basic" },
  { type: "code", label: "Code", icon: "</>", group: "advanced" },
  { type: "callout", label: "Callout", icon: "!", group: "advanced" },
  { type: "toggle", label: "Toggle", icon: "▶", group: "advanced" },
  { type: "divider", label: "Divider", icon: "—", group: "basic" },
  { type: "image", label: "Image", icon: "🖼", group: "media" },
  { type: "bookmark", label: "Bookmark", icon: "🔗", group: "media" },
  { type: "equation", label: "Equation", icon: "∑", group: "media" },
  { type: "table", label: "Table", icon: "▦", group: "advanced" },
  { type: "columns", label: "Columns", icon: "▐▌", group: "advanced" },
];

export class OraSlashMenu extends LitElement {
  static styles = css`
    :host {
      display: none;
      position: fixed;
      top: var(--menu-top, 0);
      left: var(--menu-left, 0);
      background: white;
      border: 1px solid #e5e5e5;
      border-radius: 8px;
      box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
      width: 280px;
      max-height: 320px;
      overflow-y: auto;
      z-index: 50;
      font-family: Inter, system-ui, sans-serif;
      padding: 4px;
      box-sizing: border-box;
    }
    :host([visible]) { display: block; }
    input {
      width: 100%;
      padding: 8px;
      border: none;
      border-bottom: 1px solid #eee;
      outline: none;
      font-size: 14px;
      margin-bottom: 4px;
      box-sizing: border-box;
    }
    .group-label {
      font-size: 11px;
      text-transform: uppercase;
      color: #999;
      padding: 6px 8px 2px;
      letter-spacing: 0.05em;
      font-weight: 600;
    }
    .item {
      display: flex;
      align-items: center;
      gap: 8px;
      padding: 6px 8px;
      border-radius: 4px;
      cursor: pointer;
      font-size: 13px;
      color: #333;
    }
    .item.selected {
      background: #f0f0f0;
    }
    .item:hover {
      background: #f5f5f5;
    }
    .icon {
      width: 24px;
      height: 24px;
      display: flex;
      align-items: center;
      justify-content: center;
      background: #f7f7f7;
      border-radius: 4px;
      font-size: 12px;
      flex-shrink: 0;
    }
  `;

  static properties = {
    items: { type: Array },
    _filter: { state: true },
    _selectedIndex: { state: true },
  };

  constructor() {
    super();
    this.items = FALLBACK_ITEMS;
    this._filter = "";
    this._selectedIndex = 0;
  }

  connectedCallback() {
    super.connectedCallback();
    if (this.hasAttribute("items")) {
      try {
        this.items = JSON.parse(this.getAttribute("items"));
      } catch (e) {
        console.error("ora-slash-menu: invalid items JSON", e);
        this.items = FALLBACK_ITEMS;
      }
    }
    this._keyHandler = this._onKeyDown.bind(this);
    window.addEventListener("keydown", this._keyHandler);
  }

  disconnectedCallback() {
    super.disconnectedCallback();
    window.removeEventListener("keydown", this._keyHandler);
  }

  firstUpdated() {
    const input = this.renderRoot.querySelector("input");
    if (input) input.focus();
  }

  _onKeyDown(e) {
    if (!this.isConnected) return;
    const items = this._filteredItems;
    if (items.length === 0) return;

    if (e.key === "ArrowDown") {
      e.preventDefault();
      this._selectedIndex = (this._selectedIndex + 1) % items.length;
      this._scrollSelectedIntoView();
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      this._selectedIndex =
        (this._selectedIndex - 1 + items.length) % items.length;
      this._scrollSelectedIntoView();
    } else if (e.key === "Enter") {
      e.preventDefault();
      const item = items[this._selectedIndex];
      if (item) this._select(item);
    } else if (e.key === "Escape") {
      e.preventDefault();
      this.dispatchEvent(
        new CustomEvent("close", { bubbles: true, composed: true })
      );
    }
  }

    get _filteredItems() {
    const f = this._filter.toLowerCase().trim();
    if (!f) return this.items;
    return this.items.filter((i) => {
      const labelNorm = i.label.toLowerCase();
      const labelKey = labelNorm.replace(/\s+/g, "");
      const typeNorm = i.type.replace(/[_-]/g, "").toLowerCase();
      // Initials: first char of each space/underscore/hyphen segment.
      const labelInitials = labelNorm
        .split(/[\s\-]+/)
        .filter(Boolean)
        .map((w) => w[0])
        .join("");
      const typeInitials = i.type
        .toLowerCase()
        .split(/[_-]+/)
        .filter(Boolean)
        .map((w) => w[0])
        .join("");
      return (
        labelNorm.includes(f) ||
        typeNorm.includes(f) ||
        labelKey.includes(f) ||
        labelInitials.includes(f) ||
        typeInitials.includes(f)
      );
    });
  }

  _onInput(e) {
    this._filter = e.target.value;
    this._selectedIndex = 0;
  }

  _select(item) {
    this.dispatchEvent(
      new CustomEvent("select", {
        detail: { type: item.type },
        bubbles: true,
        composed: true,
      })
    );
  }

  _scrollSelectedIntoView() {
    const el = this.renderRoot.querySelector(".item.selected");
    if (el) el.scrollIntoView({ block: "nearest" });
  }

  render() {
    const items = this._filteredItems;
    const groups = {};
    for (const item of items) {
      if (!groups[item.group]) groups[item.group] = [];
      groups[item.group].push(item);
    }

    let idx = 0;
    return html`
      <input
        type="text"
        placeholder="Type to filter..."
        .value=${this._filter}
        @input=${this._onInput}
      />
      ${GROUP_ORDER.map((group) => {
        const groupItems = groups[group];
        if (!groupItems || groupItems.length === 0) return null;
        return html`
          <div class="group-label">${group}</div>
          ${groupItems.map((item) => {
            const selected = idx === this._selectedIndex;
            const currentIdx = idx++;
            return html`
              <div
                class="item ${selected ? "selected" : ""}"
                @mousemove=${() => {
                  this._selectedIndex = currentIdx;
                }}
                @click=${() => this._select(item)}
              >
                <div class="icon">${item.icon}</div>
                <div>${item.label}</div>
              </div>
            `;
          })}
        `;
      })}
    `;
  }
}

if (!customElements.get("ora-slash-menu")) {
  customElements.define("ora-slash-menu", OraSlashMenu);
}
