/**
 * Phoenix LiveView hook attached to <ora-block>.
 * Bridges custom DOM events to server pushes and vice versa.
 */

// Module-level queue of focus_block_caret payloads received before the
// target BlockEditor hook has mounted. The server pushes focus_block_caret
// immediately after inserting a new block; the new block's hook may not
// be attached yet, in which case any already-mounted hook receives the
// event and stashes it here. The new hook consumes its entry on mount.
const _pendingFocus = new Map(); // block_id -> { position, ts }
const PENDING_FOCUS_TTL_MS = 5000;

function _applyCaret(el, position) {
  try {
    if (position === "start") {
      el.focusStart?.();
    } else if (position === "end") {
      el.focusEnd?.();
    }
  } catch (err) {
    console.warn("BlockEditor: focus_block_caret failed", err);
  }
}

function _consumePendingFocus(blockId, el) {
  if (!blockId) return;
  const pending = _pendingFocus.get(blockId);
  if (!pending) return;
  _pendingFocus.delete(blockId);
  if (Date.now() - pending.ts > PENDING_FOCUS_TTL_MS) return;
  _applyCaret(el, pending.position);
}

export const BlockEditor = {
  mounted() {
    this.el = this.el;
    this.heartbeat = null;

    this._onFocus = (e) => {
      this.pushEvent("focus_block", { block_id: e.detail?.blockId || this.el.getAttribute("block-id") });
      this._startHeartbeat();
    };

    this._onBlur = (e) => {
      this.pushEvent("blur_block", { block_id: e.detail?.blockId || this.el.getAttribute("block-id") });
      this._stopHeartbeat();
    };

    this._onChange = (e) => {
      this.pushEvent("save_content", {
        block_id: e.detail?.blockId || this.el.getAttribute("block-id"),
        state: JSON.stringify(e.detail?.state),
      });
    };

    this.el.addEventListener("ora-block-focus", this._onFocus);
    this.el.addEventListener("ora-block-blur", this._onBlur);
    this.el.addEventListener("ora-block-change", this._onChange);

    // Keyboard listeners
    this._onArrowUp = (e) => {
      this.pushEvent("nav_block", { direction: "up", block_id: this.el.getAttribute("block-id") });
    };
    this._onArrowDown = (e) => {
      this.pushEvent("nav_block", { direction: "down", block_id: this.el.getAttribute("block-id") });
    };
    this._onEnterAtEnd = (e) => {
      this.pushEvent("insert_paragraph_below", { block_id: this.el.getAttribute("block-id") });
    };
    this._onBackspaceAtStart = (e) => {
      this.pushEvent("delete_block_merge", { block_id: this.el.getAttribute("block-id") });
    };
    this.el.addEventListener("ora-block-arrow-up", this._onArrowUp);
    this.el.addEventListener("ora-block-arrow-down", this._onArrowDown);
    this.el.addEventListener("ora-block-enter-at-end", this._onEnterAtEnd);
    this.el.addEventListener("ora-block-backspace-at-start", this._onBackspaceAtStart);

    // Handle server-pushed focus_block_caret event
    this.handleEvent("focus_block_caret", ({ block_id, position }) => {
      if (block_id === this.el.getAttribute("block-id")) {
        _applyCaret(this.el, position);
      } else {
        // Target block's hook isn't mounted yet — stash for its mount.
        _pendingFocus.set(block_id, { position, ts: Date.now() });
      }
    });

    // Consume any pending focus payload that arrived before this hook
    // attached (e.g. server pushed focus_block_caret immediately after
    // inserting the block this hook is now bound to).
    _consumePendingFocus(this.el.getAttribute("block-id"), this.el);

    // Server-pushed events
    this.handleEvent("lock_granted", ({ block_id }) => {
      if (block_id === this.el.getAttribute("block-id")) {
        this.el.removeAttribute("data-locked-by-other");
        this.el.removeAttribute("data-locked-by");
        this.el.style.removeProperty("--lock-color");
        const editor = this.el.querySelector("[data-editor]");
        if (editor) editor.setAttribute("contenteditable", "true");
      }
    });

    this.handleEvent("lock_denied", ({ block_id, user_id, color }) => {
      if (block_id === this.el.getAttribute("block-id")) {
        this.el.setReadOnly?.(true);
        this.el.setAttribute("data-locked-by-other", "true");
        if (user_id) {
          this.el.setAttribute("data-locked-by", user_id);
          this.el.style.setProperty("--lock-color", color || "var(--color-notion-blue)");
        }
        const editor = this.el.querySelector("[data-editor]");
        if (editor) editor.setAttribute("contenteditable", "false");
      }
    });

    this.handleEvent("set_locked_by", ({ block_id, user_id, color }) => {
      if (block_id === this.el.getAttribute("block-id")) {
        this.el.setAttribute("data-locked-by", user_id);
        this.el.style.setProperty("--lock-color", color || "var(--color-notion-blue)");
        const editor = this.el.querySelector("[data-editor]");
        if (editor) editor.setAttribute("contenteditable", "false");
      }
    });

    this.handleEvent("apply_remote", ({ block_id, state }) => {
      if (block_id === this.el.getAttribute("block-id")) {
        this.el.applyRemote?.(state);
      }
    });
  },

  _startHeartbeat() {
    this._stopHeartbeat();
    this.heartbeat = setInterval(() => {
      this.pushEvent("refresh_lock", { block_id: this.el.getAttribute("block-id") });
    }, 15000);
  },

  _stopHeartbeat() {
    if (this.heartbeat) {
      clearInterval(this.heartbeat);
      this.heartbeat = null;
    }
  },

  disconnected() {
    this._stopHeartbeat();
    this.pushEvent("blur_block", { block_id: this.el.getAttribute("block-id") });
  },

  destroyed() {
    this._stopHeartbeat();
    this.pushEvent("blur_block", { block_id: this.el.getAttribute("block-id") });
    this.el.removeEventListener("ora-block-focus", this._onFocus);
    this.el.removeEventListener("ora-block-blur", this._onBlur);
    this.el.removeEventListener("ora-block-change", this._onChange);
    this.el.removeEventListener("ora-block-arrow-up", this._onArrowUp);
    this.el.removeEventListener("ora-block-arrow-down", this._onArrowDown);
    this.el.removeEventListener("ora-block-enter-at-end", this._onEnterAtEnd);
    this.el.removeEventListener("ora-block-backspace-at-start", this._onBackspaceAtStart);
  },
};
