const BlockKeyboard = {
  mounted() {
    this._onArrowUp = (e) => {
      e.preventDefault();
      this.pushEvent("nav_block", {
        direction: "up",
        block_id: this.el.dataset.blockId,
      });
    };

    this._onArrowDown = (e) => {
      e.preventDefault();
      this.pushEvent("nav_block", {
        direction: "down",
        block_id: this.el.dataset.blockId,
      });
    };

    this._onEnterAtEnd = (e) => {
      e.preventDefault();
      this.pushEvent("insert_paragraph_below", {
        block_id: this.el.dataset.blockId,
      });
    };

    this._onBackspaceAtStart = (e) => {
      e.preventDefault();
      this.pushEvent("delete_block_merge", {
        block_id: this.el.dataset.blockId,
      });
    };

    this._onFocusBlockCaret = ({ block_id, position }) => {
      if (block_id !== this.el.dataset.blockId) return;
      if (position === "start" && typeof this.el.focusStart === "function") {
        this.el.focusStart();
      } else if (
        position === "end" &&
        typeof this.el.focusEnd === "function"
      ) {
        this.el.focusEnd();
      }
    };

    this.el.addEventListener("ora-block-arrow-up", this._onArrowUp);
    this.el.addEventListener("ora-block-arrow-down", this._onArrowDown);
    this.el.addEventListener("ora-block-enter-at-end", this._onEnterAtEnd);
    this.el.addEventListener(
      "ora-block-backspace-at-start",
      this._onBackspaceAtStart
    );

    if (typeof this.handleEvent === "function") {
      this.handleEvent("focus_block_caret", this._onFocusBlockCaret);
    }
  },

  destroyed() {
    this.el.removeEventListener("ora-block-arrow-up", this._onArrowUp);
    this.el.removeEventListener("ora-block-arrow-down", this._onArrowDown);
    this.el.removeEventListener("ora-block-enter-at-end", this._onEnterAtEnd);
    this.el.removeEventListener(
      "ora-block-backspace-at-start",
      this._onBackspaceAtStart
    );
  },
};

export default BlockKeyboard;
