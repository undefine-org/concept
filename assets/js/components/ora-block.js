import { LitElement, html } from "lit";
import { createBlockEditor } from "../lexical/registry.js";
import { parseInitial, serialize } from "../lexical/state.js";

export class OraBlock extends LitElement {
  static properties = {
    "blockId": { type: String, attribute: "block-id" },
    "blockType": { type: String, attribute: "block-type" },
    "initialContent": { type: String, attribute: "initial-content" },
    "placeholder": { type: String },
    "readOnly": { type: Boolean, attribute: "read-only" },
  };

  constructor() {
    super();
    this.blockId = "";
    this.blockType = "paragraph";
    this.initialContent = "";
    this.placeholder = "";
    this.readOnly = false;
    this._editor = null;
    this._changeTimer = null;
    this._applyingRemote = false;
  }

  createRenderRoot() {
    return this;
  }

  firstUpdated() {
    const root = this.querySelector("[data-editor]");
    if (!root) {
      console.warn("ora-block: no [data-editor] root found");
      return;
    }

    this._editor = createBlockEditor(root, !this.readOnly);

    const state = parseInitial(this._editor, this.initialContent);
    if (state) {
      this._editor.setEditorState(state);
    }

    this._editor.registerUpdateListener(({ editorState, prevEditorState, tags }) => {
      if (this._applyingRemote) return;
      if (editorState === prevEditorState) return;
      if (tags.has("history-merge") || tags.has("collab")) return;

      this._scheduleChange(serialize(this._editor));
    });

    root.addEventListener("focusin", () => this._onFocus());
    root.addEventListener("focusout", () => this._onBlur());

    root.addEventListener("keydown", (e) => {
      if (e.key === "ArrowUp" && this._isAtStart()) {
        e.preventDefault();
        this.dispatchEvent(new CustomEvent("ora-block-arrow-up", { bubbles: true }));
      }
      if (e.key === "ArrowDown" && this._isAtEnd()) {
        e.preventDefault();
        this.dispatchEvent(new CustomEvent("ora-block-arrow-down", { bubbles: true }));
      }
      if (e.key === "Enter" && !e.shiftKey && this._isAtEnd()) {
        e.preventDefault();
        this.dispatchEvent(new CustomEvent("ora-block-enter-at-end", { bubbles: true }));
      }
      if (e.key === "Backspace" && this._isAtStart() && this._isEmpty()) {
        e.preventDefault();
        this.dispatchEvent(new CustomEvent("ora-block-backspace-at-start", { bubbles: true }));
      }
    });
  }

  _scheduleChange(state) {
    clearTimeout(this._changeTimer);
    this._changeTimer = setTimeout(() => {
      this.dispatchEvent(
        new CustomEvent("ora-block-change", {
          detail: { state },
          bubbles: true,
        })
      );
    }, 400);
  }

  _onFocus() {
    this.dispatchEvent(new CustomEvent("ora-block-focus", { detail: { blockId: this.blockId }, bubbles: true }));
  }

  _onBlur() {
    this.dispatchEvent(new CustomEvent("ora-block-blur", { detail: { blockId: this.blockId }, bubbles: true }));
  }

  _isAtStart() {
    const editor = this._editor;
    if (!editor) return false;
    let atStart = false;
    editor.getEditorState().read(() => {
      const selection = editor.getEditorState()._selection;
      // Quick heuristic: collapsed at offset 0 of first child
      const node = selection?.anchor?.getNode?.();
      atStart = selection?.isCollapsed?.() && node && node.getOffset() === 0;
    });
    return atStart;
  }

  _isAtEnd() {
    const editor = this._editor;
    if (!editor) return false;
    let atEnd = false;
    editor.getEditorState().read(() => {
      const selection = editor.getEditorState()._selection;
      const node = selection?.anchor?.getNode?.();
      atEnd = selection?.isCollapsed?.() && node && (node.getTextContentSize?.() ?? 0) === selection?.anchor?.offset;
    });
    return atEnd;
  }

  _isEmpty() {
    const editor = this._editor;
    if (!editor) return true;
    let empty = true;
    editor.getEditorState().read(() => {
      const root = editor.getEditorState()._nodeMap?.get("root");
      empty = !root || root.getTextContent() === "";
    });
    return empty;
  }

  applyRemote(json) {
    if (!this._editor) return;
    const state = parseInitial(this._editor, json);
    if (!state) return;
    this._applyingRemote = true;
    this._editor.setEditorState(state);
    requestAnimationFrame(() => {
      this._applyingRemote = false;
    });
  }

  setReadOnly(bool) {
    this.readOnly = bool;
    if (this._editor) {
      this._editor.setEditable(!bool);
    }
  }
}

if (!customElements.get("ora-block")) {
  customElements.define("ora-block", OraBlock);
}
