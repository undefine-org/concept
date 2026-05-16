/**
 * Phoenix LiveView hook attached to <div id="format-toolbar-host">.
 *
 * Resolves the active Lexical editor from the nearest <ora-block>,
 * listens for selection changes to position the floating toolbar,
 * and routes custom DOM events to Lexical commands.
 */
import { toggleFormat, setLink } from "../lexical/commands.js";

export const FormatToolbar = {
  mounted() {
    /** @type {HTMLElement} */
    this.host = this.el;

    /** @type {import("lexical").LexicalEditor|null} */
    this._activeEditor = null;

    /** @type {HTMLElement|null} */
    this._toolbar = null;

    /** @type {HTMLElement|null} */
    this._linkEditor = null;

    // Bind handlers once so they can be removed
    this._onSelectionChange = this._handleSelectionChange.bind(this);
    this._onToggleFormat = this._handleToggleFormat.bind(this);
    this._onRequestLink = this._handleRequestLink.bind(this);
    this._onApplyLink = this._handleApplyLink.bind(this);
    this._onCancelLink = this._handleCancelLink.bind(this);

    // Locate child elements
    this._toolbar = this.host.querySelector("ora-format-toolbar");
    this._linkEditor = this.host.querySelector("ora-link-editor");

    // Subscribe to global selection changes
    document.addEventListener("selectionchange", this._onSelectionChange);

    // Listen for custom events dispatched on this host
    this.host.addEventListener("toggle-format", this._onToggleFormat);
    this.host.addEventListener("request-link", this._onRequestLink);
    this.host.addEventListener("apply-link", this._onApplyLink);
    this.host.addEventListener("cancel-link", this._onCancelLink);

    // Initial check
    this._handleSelectionChange();
  },

  /**
   * Walk up from an element (or composedPath) to the nearest <ora-block>.
   * Handles Lit closed shadow roots via composedPath() when the event
   * provides one.
   *
   * @param {Event} [event] - optional event whose composedPath to use
   * @returns {HTMLElement|null}
   */
  _resolveOraBlock(event) {
    // Try composedPath first (handles shadow DOM boundaries)
    if (event && typeof event.composedPath === "function") {
      const path = event.composedPath();
      for (const el of path) {
        if (el.tagName === "ORA-BLOCK") return el;
      }
    }

    // Fallback: walk up from activeElement
    let el = document.activeElement;
    while (el) {
      if (el.tagName === "ORA-BLOCK") return el;
      el = el.parentElement;
    }

    return null;
  },

  /**
   * Given an <ora-block>, return its Lexical editor instance.
   *
   * @param {HTMLElement} oraBlock
   * @returns {import("lexical").LexicalEditor|null}
   */
  _getEditor(oraBlock) {
    return oraBlock._editor || null;
  },

  /** @param {Event} [event] */
  _handleSelectionChange(event) {
    const sel = window.getSelection();

    // Hide toolbar if selection is empty, collapsed, or outside an ora-block
    if (!sel || sel.isCollapsed || !sel.rangeCount) {
      this._hideToolbar();
      return;
    }

    const oraBlock = this._resolveOraBlock(event);
    if (!oraBlock) {
      this._hideToolbar();
      return;
    }

    const editor = this._getEditor(oraBlock);
    if (!editor) {
      this._hideToolbar();
      return;
    }

    this._activeEditor = editor;

    // Compute caret rect for toolbar positioning
    let rect;
    try {
      rect = sel.getRangeAt(0).getBoundingClientRect();
    } catch {
      this._hideToolbar();
      return;
    }

    if (!rect || (rect.width === 0 && rect.height === 0)) {
      this._hideToolbar();
      return;
    }

    this._showToolbar(rect);
  },

  /**
   * Show the formatting toolbar at the given caret position.
   * Sets visible attribute and positions via CSS custom properties.
   *
   * @param {DOMRect} rect
   */
  _showToolbar(rect) {
    if (!this._toolbar) return;

    this._toolbar.setAttribute("visible", "");
    this._toolbar.style.setProperty("--toolbar-x", `${rect.left + rect.width / 2}px`);
    this._toolbar.style.setProperty("--toolbar-y", `${rect.top}px`);
  },

  /** Hide the toolbar and dismiss link editor overlay. */
  _hideToolbar() {
    if (this._toolbar) {
      this._toolbar.removeAttribute("visible");
    }
    if (this._linkEditor) {
      this._linkEditor.removeAttribute("visible");
    }
    this._activeEditor = null;
  },

  /**
   * Toggle a text format on the active editor.
   *
   * Expects event.detail.format {"bold"|"italic"|"underline"|"strikethrough"|"code"}
   *
   * @param {CustomEvent} event
   */
  _handleToggleFormat(event) {
    const editor = this._activeEditor;
    if (!editor) return;

    const format = event.detail?.format;
    if (!format) return;

    toggleFormat(editor, format);
  },

  /**
   * Reveal the link editor overlay.
   */
  _handleRequestLink() {
    if (this._linkEditor) {
      this._linkEditor.setAttribute("visible", "");
    }
  },

  /**
   * Apply or remove a link.
   *
   * Expects event.detail.url {string} – empty string removes the link.
   * Also hides the link editor overlay.
   *
   * @param {CustomEvent} event
   */
  _handleApplyLink(event) {
    const editor = this._activeEditor;
    if (!editor) return;

    const url = event.detail?.url ?? "";
    setLink(editor, url);

    if (this._linkEditor) {
      this._linkEditor.removeAttribute("visible");
    }
  },

  /**
   * Hide the link editor overlay without applying.
   */
  _handleCancelLink() {
    if (this._linkEditor) {
      this._linkEditor.removeAttribute("visible");
    }
  },

  destroyed() {
    document.removeEventListener("selectionchange", this._onSelectionChange);
    this.host.removeEventListener("toggle-format", this._onToggleFormat);
    this.host.removeEventListener("request-link", this._onRequestLink);
    this.host.removeEventListener("apply-link", this._onApplyLink);
    this.host.removeEventListener("cancel-link", this._onCancelLink);
    this._activeEditor = null;
  },
};

export default FormatToolbar;
