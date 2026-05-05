const GlobalKeys = {
  mounted() {
    this._paletteOpen = false;

    this._onKeyDown = (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        this.pushEvent("open_command_palette", {});
      }

      if (e.key === "Escape" && this._paletteOpen) {
        e.preventDefault();
        this.pushEvent("close_command_palette", {});
      }
    };

    this._onPaletteState = ({ open }) => {
      this._paletteOpen = open;
    };

    document.addEventListener("keydown", this._onKeyDown);

    if (typeof this.handleEvent === "function") {
      this.handleEvent("palette_state", this._onPaletteState);
    }
  },

  destroyed() {
    document.removeEventListener("keydown", this._onKeyDown);
  },
};

export default GlobalKeys;
