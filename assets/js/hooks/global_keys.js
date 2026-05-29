const GlobalKeys = {
  mounted() {
    this._paletteOpen = false;

    this._onKeyDown = (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        e.stopPropagation();
        this.pushEvent("open_command_palette", {});
      }

      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "j") {
        e.preventDefault();
        e.stopPropagation();
        this.pushEvent("toggle_chat", {});
      }

      // GlobalKeys is the sole keyboard authority (FUP-034). Escape priority
      // (palette before chat) is decided server-side; we only suppress the
      // browser default when the palette is open, matching prior behaviour.
      if (e.key === "Escape") {
        if (this._paletteOpen) {
          e.preventDefault();
        }
        this.pushEvent("escape", {});
      }
    };

    this._onPaletteState = ({ open }) => {
      this._paletteOpen = open;
    };

    this._onLinkThis = (e) => {
      const { targetBlockId } = e.detail;
      if (targetBlockId) {
        this.pushEvent("ora_link_this", { targetBlockId });
      }
    };

    document.addEventListener("keydown", this._onKeyDown);
    this.el.addEventListener("ora-link-this", this._onLinkThis);

    if (typeof this.handleEvent === "function") {
      this.handleEvent("palette_state", this._onPaletteState);
    }
  },

  destroyed() {
    document.removeEventListener("keydown", this._onKeyDown);
    this.el.removeEventListener("ora-link-this", this._onLinkThis);
  },
};

export default GlobalKeys;
