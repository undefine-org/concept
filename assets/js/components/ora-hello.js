import { LitElement, html, css } from "lit";

export class OraHello extends LitElement {
  static styles = css`
    :host { display: inline-block; padding: 4px 12px; border-radius: 6px; background: #EFEEEC; color: #37352F; font: 500 14px/1.4 Inter, system-ui, sans-serif; }
  `;
  render() { return html`<span>ok — lit + lexical pipeline live</span>`; }
}

if (!customElements.get("ora-hello")) customElements.define("ora-hello", OraHello);
