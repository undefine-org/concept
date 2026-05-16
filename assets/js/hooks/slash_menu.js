/**
 * Phoenix LiveView hook attached to <div id="slash-menu-host">.
 *
 * Detects "/" typed at line-start or after whitespace in an <ora-block>,
 * opens the <ora-slash-menu> with filter, and dispatches
 * `insert_block_below` on selection.
 */
import { $getRoot, $createTextNode } from "lexical";

export const SlashMenu = {
  mounted() {
    this.host = this.el;
    this._open = false;
    this._triggerRange = null;
    this._triggerPreLength = 0;
    this._activeBlockId = null;
    this._activeEditor = null;

    // Bind once for cleanup
    this._onInput = this._handleInput.bind(this);
    this._onKeyDown = this._handleKeyDown.bind(this);
    this._onClickOutside = this._handleClickOutside.bind(this);
    this._onSelectItem = this._handleSelectItem.bind(this);
    this._onClose = this._handleClose.bind(this);

    // Global input detection (Lexical contenteditable fires input events)
    document.addEventListener("input", this._onInput);
    document.addEventListener("keydown", this._onKeyDown);
    document.addEventListener("click", this._onClickOutside);

    // Listen for events from the <ora-slash-menu> Lit component
    this.host.addEventListener("select", this._onSelectItem);
    this.host.addEventListener("close", this._onClose);
  },

  /**
   * Walk up from an event to the nearest <ora-block> element.
   * Handles shadow DOM via composedPath().
   * @param {Event} [event]
   * @returns {HTMLElement|null}
   */
  _resolveOraBlock(event) {
    if (event && typeof event.composedPath === "function") {
      const path = event.composedPath();
      for (const el of path) {
        if (el.tagName === "ORA-BLOCK") return el;
      }
    }
    let el = document.activeElement;
    while (el) {
      if (el.tagName === "ORA-BLOCK") return el;
      el = el.parentElement;
    }
    return null;
  },

  /**
   * Detect "/" insertion after whitespace / line-start inside an ora-block.
   * @param {InputEvent} event
   */
  _handleInput(event) {
    if (this._open) return; // Already showing menu

    const oraBlock = this._resolveOraBlock(event);
    if (!oraBlock) return;

    // Only trigger on "/" text insertion
    if (event.inputType !== "insertText" || event.data !== "/") return;

    const sel = window.getSelection();
    if (!sel || !sel.rangeCount) return;

    const range = sel.getRangeAt(0);
    const offset = range.startOffset;

    // Check that the character before "/" is whitespace or line-start.
    // offset is the caret position AFTER the "/" was inserted, so the "/"
    // sits at offset-1 and the prior char at offset-2.
    if (offset >= 2) {
      const textNode = range.startContainer;
      const priorChar =
        textNode.nodeType === Node.TEXT_NODE
          ? textNode.textContent?.[offset - 2]
          : null;
      if (priorChar && !/[\s]/.test(priorChar)) {
        return; // Mid-word — not a trigger
      }
    }

    // Save trigger state
    this._triggerRange = range.cloneRange();
    this._activeEditor = oraBlock._editor;
    this._activeBlockId = oraBlock.getAttribute("block-id");
    if (!this._activeEditor) return;

    // Capture the editor text length before "/" was inserted.
    // At this point the editor already contains "/" (input event fires after insertion),
    // so we subtract 1 to get the pre-slash length.
    this._triggerPreLength =
      this._activeEditor
        .getEditorState()
        .read(() => $getRoot().getTextContent().length) - 1;

    // Show and position the slash menu
    this._open = true;
    const menu = this.host.querySelector("ora-slash-menu");
    if (!menu) return;

    try {
      const caretRect = range.getBoundingClientRect();
      menu.style.setProperty("--menu-top", `${caretRect.bottom + window.scrollY}px`);
      menu.style.setProperty("--menu-left", `${caretRect.left + window.scrollX}px`);
    } catch {
      // Position unavailable (e.g. jsdom tests) — menu still shows without coords
    }

    menu.setAttribute("visible", "");

    // Reset filter state on the Lit component
    if (typeof menu._filter !== "undefined") {
      menu._filter = "";
      menu._selectedIndex = 0;
      if (typeof menu.requestUpdate === "function") {
        menu.requestUpdate();
      }
    }

    // Focus the menu's filter input on next frame
    requestAnimationFrame(() => {
      const input =
        menu.renderRoot && menu.renderRoot.querySelector("input");
      if (input) input.focus();
    });
  },

  /**
   * While menu is open, pressing Escape closes it.
   * The ora-slash-menu Lit component also handles Arrow keys + Enter
   * on window keydown; we let it handle those. We only intercept Escape
   * if the Lit component didn't already.
   * @param {KeyboardEvent} event
   */
  _handleKeyDown(event) {
    if (!this._open) return;

    if (event.key === "Escape") {
      // The Lit component may already dispatch 'close' on Escape.
      // We use a flag to avoid double-close.
      if (this._open) {
        this._close();
      }
    } else if (event.key === "Backspace") {
      // Backspace on empty filter closes the menu
      const menu = this.host.querySelector("ora-slash-menu");
      if (menu && (menu._filter === "" || menu._filter == null)) {
        event.preventDefault();
        this._close();
      }
    }
  },

  /**
   * Close the menu when clicking outside both the host and any ora-block.
   * @param {MouseEvent} event
   */
  _handleClickOutside(event) {
    if (!this._open) return;

    const path =
      typeof event.composedPath === "function"
        ? event.composedPath()
        : [event.target];

    // Allow clicks inside the host (e.g. on the menu items)
    if (path.includes(this.host)) return;

    // Allow clicks inside ora-blocks (user editing)
    if (path.some((el) => el.tagName === "ORA-BLOCK")) return;

    this._close();
  },

  /**
   * Handle item selection from the slash menu.
   * Deletes the trigger "/" + filter chars from the editor via simpler
   * root-manipulation approach (rather than Lexical's selection-range API).
   *
   * Why the simpler approach:
   * The Lexical selection API ($getSelection().removeText()) requires
   * reconstructing a multi-character DOM-to-Lexical range mapping, which
   * is fragile across Lexical versions. The root-manipulation path is
   * deterministic: we know the pre-slash text length, so we clear the
   * editor and re-insert only the pre-slash portion.
   *
   * @param {CustomEvent} event  detail: {type: string}
   */
  _handleSelectItem(event) {
    const editor = this._activeEditor;
    if (!editor) return;

    const type = event.detail?.type;
    if (!type) return;

    // Delete the trigger "/" + filter chars from Lexical editor
    editor.update(() => {
      const root = $getRoot();
      const text = root.getTextContent();
      const startIdx = this._triggerPreLength;
      // Keep only pre-slash content; discard "/" + any filter chars
      // that were typed while the menu was open
      root.clear();
      root.append($createTextNode(text.slice(0, startIdx)));
    });

    // Push insert event to server
    this.pushEvent("insert_block_below", {
      block_id: this._activeBlockId || "",
      type: type,
    });

    this._close();
  },

  /** Close the menu without dispatching a block insert. */
  _handleClose() {
    this._close();
  },

  _close() {
    this._open = false;
    const menu = this.host.querySelector("ora-slash-menu");
    if (menu) {
      menu.removeAttribute("visible");
    }
    this._triggerRange = null;
    this._activeBlockId = null;
    this._activeEditor = null;
  },

  destroyed() {
    document.removeEventListener("input", this._onInput);
    document.removeEventListener("keydown", this._onKeyDown);
    document.removeEventListener("click", this._onClickOutside);
    this.host.removeEventListener("select", this._onSelectItem);
    this.host.removeEventListener("close", this._onClose);
    this._close();
  },
};

export default SlashMenu;
