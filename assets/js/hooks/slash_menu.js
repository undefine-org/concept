/**
 * Phoenix LiveView hook attached to <div id="slash-menu-host">.
 *
 * Detects "/" typed at line-start or after whitespace in an <ora-block>,
 * opens the <ora-slash-menu> with filter, and dispatches
 * `insert_block_below` on selection.
 */
import { $getRoot, $getSelection, $createParagraphNode, $createTextNode } from "lexical";

export const SlashMenu = {
  mounted() {
    this.host = this.el;
    this._open = false;
    this._triggerPreLength = 0;
    this._activeBlockId = null;
    this._activeEditor = null;
    this._editorUnsub = null;
    this._focusedBlock = null;
    this._pendingVerifyRaf = null;

    // Bind once for cleanup
    this._onBlockFocus = this._handleBlockFocus.bind(this);
    this._onKeyDown = this._handleKeyDown.bind(this);
    this._onClickOutside = this._handleClickOutside.bind(this);
    this._onSelectItem = this._handleSelectItem.bind(this);
    this._onClose = this._handleClose.bind(this);

    // Subscribe to ora-block focus events so we can attach Lexical listeners.
    document.addEventListener("ora-block-focus", this._onBlockFocus);
    document.addEventListener("keydown", this._onKeyDown);
    document.addEventListener("click", this._onClickOutside);

    // Listen for events from the <ora-slash-menu> Lit component
    this.host.addEventListener("select", this._onSelectItem);
    this.host.addEventListener("close", this._onClose);
  },

  /**
   * When an ora-block receives focus, subscribe to its Lexical editor's
   * text-content listener so we detect "/" insertion through the Lexical
   * pipeline (not via unreliable document-level `input` events).
   */
  _handleBlockFocus(event) {
    const block = event.target;
    if (!block || block.tagName !== "ORA-BLOCK") return;
    const editor = block._editor;
    if (!editor) return;

    // Unsubscribe from previous editor if focus moved to a different block.
    if (this._editorUnsub && this._focusedBlock !== block) {
      this._editorUnsub();
      this._editorUnsub = null;
    }

    if (this._focusedBlock === block && this._editorUnsub) {
      return; // already subscribed
    }

    this._focusedBlock = block;
    const blockId = block.getAttribute("block-id");

    this._editorUnsub = editor.registerTextContentListener((text) => {
      if (this._open) return;

      editor.getEditorState().read(() => {
        const sel = $getSelection();
        if (!sel || !sel.isCollapsed || !sel.isCollapsed()) return;

        const anchor = sel.anchor;
        if (!anchor) return;
        const offset = anchor.offset;
        const node = anchor.getNode();
        const nodeText = node?.getTextContent ? node.getTextContent() : "";

        // The "/" must be at offset-1.
        if (nodeText[offset - 1] !== "/") return;

        // Prior char (offset-2) must be whitespace or absent (line-start).
        if (offset >= 2) {
          const priorChar = nodeText[offset - 2];
          if (priorChar && !/\s/.test(priorChar)) return;
        }

        // Valid trigger — capture state before opening.
        this._triggerPreLength = text.length - 1;
        this._activeEditor = editor;
        this._activeBlockId = blockId;
        this._open = true;
        this._openMenu();
      });
    });
  },

  _openMenu() {
    const menu = this.host.querySelector("ora-slash-menu");
    if (!menu) return;

    // Position via the live DOM selection.
    try {
      const domSel = window.getSelection();
      if (domSel && domSel.rangeCount) {
        const range = domSel.getRangeAt(0);
        const caretRect = range.getBoundingClientRect();
        menu.style.setProperty("--menu-top", `${caretRect.bottom + window.scrollY}px`);
        menu.style.setProperty("--menu-left", `${caretRect.left + window.scrollX}px`);
      }
    } catch {
      // Position unavailable (e.g. jsdom tests) — menu still shows without coords.
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
      const input = menu.renderRoot && menu.renderRoot.querySelector("input");
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
    if (path.some((el) => el && el.tagName === "ORA-BLOCK")) return;

    this._close();
  },

  /**
   * Handle item selection from the slash menu.
   * Deletes the trigger "/" + filter chars from the editor by removing
   * them inside `editor.update`, then re-reads the state to verify.
   *
   * @param {CustomEvent} event  detail: {type: string}
   */
  _handleSelectItem(event) {
    const editor = this._activeEditor;
    if (!editor) return;

    const type = event.detail?.type;
    if (!type) return;

    const preLength = this._triggerPreLength;
    const blockId = this._activeBlockId || "";

    // Capture expected pre-slash text before we mutate the editor.
    const expectedPreText = editor
      .getEditorState()
      .read(() => $getRoot().getTextContent())
      .slice(0, preLength);

    // Rebuild the editor content without the trigger chars.
    editor.update(() => {
      const root = $getRoot();
      const fullText = root.getTextContent();
      const preText = fullText.slice(0, preLength);

      // Remove all block children so we can rebuild cleanly.
      const children = root.getChildren();
      for (const child of children) {
        child.remove();
      }

      // Append a paragraph with the preserved pre-slash text so the tree
      // remains structurally valid (root may only contain block nodes).
      const para = $createParagraphNode();
      if (preText) {
        para.append($createTextNode(preText));
      }
      root.append(para);
    });

    // Verify deletion by re-reading the committed editor state on the
    // next frame. Lexical commits asynchronously after editor.update(),
    // so a synchronous read may still see the pre-update state.
    if (this._pendingVerifyRaf) {
      cancelAnimationFrame(this._pendingVerifyRaf);
      this._pendingVerifyRaf = null;
    }
    this._pendingVerifyRaf = requestAnimationFrame(() => {
      this._pendingVerifyRaf = null;
      let verifiedText;
      editor.getEditorState().read(() => {
        verifiedText = $getRoot().getTextContent();
      });
      if (verifiedText !== expectedPreText) {
        // eslint-disable-next-line no-console
        console.warn(
          `SlashMenu: trigger deletion mismatch — expected "${expectedPreText}", got "${verifiedText}"`,
        );
      }
    });

    // Push insert event to server. Composite types (table/columns) go
    // through the rows×cols picker first; everything else inserts a
    // single block immediately.
    if (type === "table" || type === "columns") {
      this._openCompositePicker(type, blockId);
    } else {
      this.pushEvent("insert_block_below", {
        block_id: blockId,
        type: type,
      });
    }

    this._close();
  },

  /** Close the menu without dispatching a block insert. */
  _handleClose() {
    this._close();
  },

  /**
   * Open the composite picker overlay for the given type ({@code "table"}
   * or {@code "columns"}). The picker reads `data-source-block-id` and
   * `data-mode` to know what to dispatch when the user selects an option.
   */
  _openCompositePicker(type, sourceBlockId) {
    const picker = document.getElementById("composite-picker");
    if (!picker) return;

    picker.classList.remove("hidden");
    picker.setAttribute("data-open", "true");
    picker.setAttribute("data-mode", type);
    picker.setAttribute("data-source-block-id", sourceBlockId || "");

    picker.querySelectorAll("[data-mode-target]").forEach((el) => {
      if (el.getAttribute("data-mode-target") === type) {
        el.classList.remove("hidden");
      } else {
        el.classList.add("hidden");
      }
    });

    // Intercept clicks once: read the chosen dimensions + source id,
    // dispatch insert_composite_below, then close the picker.
    if (!picker._oraPickerBound) {
      picker.addEventListener("click", (e) => {
        const btn = e.target.closest("[phx-click='insert_composite_below']");
        if (!btn || !picker.contains(btn)) return;
        e.preventDefault();
        e.stopPropagation();

        const mode = picker.getAttribute("data-mode") || "table";
        const blockId = picker.getAttribute("data-source-block-id") || "";

        const payload = { type: mode, block_id: blockId };
        if (mode === "table") {
          payload.rows = Number(btn.getAttribute("data-rows")) || 2;
          payload.cols = Number(btn.getAttribute("data-cols")) || 2;
        } else {
          payload.count = Number(btn.getAttribute("data-count")) || 2;
        }

        this.pushEvent("insert_composite_below", payload);
        this._closeCompositePicker();
      });
      picker._oraPickerBound = true;
    }
  },

  _closeCompositePicker() {
    const picker = document.getElementById("composite-picker");
    if (!picker) return;
    picker.classList.add("hidden");
    picker.setAttribute("data-open", "false");
    picker.setAttribute("data-source-block-id", "");
  },

  _close() {
    this._open = false;
    const menu = this.host.querySelector("ora-slash-menu");
    if (menu) {
      menu.removeAttribute("visible");
    }
    this._triggerPreLength = 0;
    this._activeBlockId = null;
    this._activeEditor = null;
  },

  destroyed() {
    document.removeEventListener("ora-block-focus", this._onBlockFocus);
    document.removeEventListener("keydown", this._onKeyDown);
    document.removeEventListener("click", this._onClickOutside);
    this.host.removeEventListener("select", this._onSelectItem);
    this.host.removeEventListener("close", this._onClose);
    if (this._editorUnsub) {
      this._editorUnsub();
      this._editorUnsub = null;
    }
    if (this._pendingVerifyRaf) {
      cancelAnimationFrame(this._pendingVerifyRaf);
      this._pendingVerifyRaf = null;
    }
    this._close();
  },
};

export default SlashMenu;
