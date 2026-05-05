/**
 * Phoenix LiveView hook attached to <ora-block>.
 * Bridges custom DOM events to server pushes and vice versa.
 */
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

    // Server-pushed events
    this.handleEvent("lock_granted", ({ block_id }) => {
      if (block_id === this.el.getAttribute("block-id")) {
        this.el.removeAttribute("data-locked-by-other");
      }
    });

    this.handleEvent("lock_denied", ({ block_id }) => {
      if (block_id === this.el.getAttribute("block-id")) {
        this.el.setReadOnly?.(true);
        this.el.setAttribute("data-locked-by-other", "true");
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
  },
};
