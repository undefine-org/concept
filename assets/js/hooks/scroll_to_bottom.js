// ScrollToBottom — keeps a scrollable feed (chat message list) pinned to the
// latest content as it grows, but only when the user is already near the
// bottom. If they've scrolled up to read history, new content does not yank
// them down — it just becomes available below. Standard chat affordance.
const NEAR_BOTTOM_PX = 120;

const ScrollToBottom = {
  mounted() {
    this._stick = true;

    this._onScroll = () => {
      const distance =
        this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight;
      this._stick = distance <= NEAR_BOTTOM_PX;
    };

    this.el.addEventListener("scroll", this._onScroll, { passive: true });
    this._toBottom("auto");
  },

  updated() {
    if (this._stick) this._toBottom("smooth");
  },

  destroyed() {
    this.el.removeEventListener("scroll", this._onScroll);
  },

  _toBottom(behavior) {
    // rAF so layout has settled after the LiveView patch.
    requestAnimationFrame(() => {
      this.el.scrollTo({ top: this.el.scrollHeight, behavior });
    });
  },
};

export default ScrollToBottom;
