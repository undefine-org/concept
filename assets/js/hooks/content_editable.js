/**
 * Hook for the ora-page-title contenteditable <h1>.
 *
 * - blur → push save_title with the trimmed value
 * - Enter → save_title, blur, and dispatch `ora:title-enter` on window so
 *   the PageEditorLive (separate LV) can focus the first block.
 */
const ContentEditable = {
  mounted() {
    this._save = () => {
      this.pushEventTo(this.el, "save_title", { value: this.el.innerText.trim() });
    };
    this._onBlur = () => this._save();
    this._onKeydown = (e) => {
      if (e.key !== "Enter") return;
      e.preventDefault();
      this._save();
      this.el.blur();
      // PageEditorLive lives in a sibling LV process; cross the boundary
      // through a DOM event picked up by its PageScroll colocated hook.
      window.dispatchEvent(new CustomEvent("ora:title-enter"));
    };
    this.el.addEventListener("blur", this._onBlur);
    this.el.addEventListener("keydown", this._onKeydown);
  },

  destroyed() {
    this.el.removeEventListener("blur", this._onBlur);
    this.el.removeEventListener("keydown", this._onKeydown);
  },
};

export default ContentEditable;
