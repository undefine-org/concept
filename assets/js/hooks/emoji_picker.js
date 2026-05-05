const EmojiPicker = {
  mounted() {
    this._onSelect = (e) => {
      this.pushEventTo(this.el, "set_emoji", { emoji: e.detail });
    };
    this._onClose = () => {
      this.pushEventTo(this.el, "toggle_emoji_picker");
    };
    this.el.addEventListener("select", this._onSelect);
    this.el.addEventListener("close", this._onClose);
  },

  destroyed() {
    this.el.removeEventListener("select", this._onSelect);
    this.el.removeEventListener("close", this._onClose);
  },
};

export default EmojiPicker;
