/**
 * Hook for the ora-page-title contenteditable <h1>.
 *
 * The <h1> sets `phx-update="ignore"` so LiveView never patches its inner text
 * (which would reset the caret to position 0 mid-edit). This hook therefore
 * owns the element's content:
 *
 * - blur → push save_title with the trimmed value
 * - Enter → save_title, blur, and dispatch `ora:title-enter` on window so
 *   the PageEditorLive (separate LV) can focus the first block
 * - updated() → apply the server's canonical title (carried in data-title,
 *   which IS patched under phx-update=ignore) but ONLY when the element is not
 *   focused, so a remote rename syncs in without clobbering a local editor's
 *   caret.
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

  updated() {
    // Sync remote renames into the element we otherwise own. Skip while the
    // local user is editing — applying text here would move their caret.
    if (document.activeElement === this.el) return;
    const canonical = this.el.dataset.title || "";
    if (this.el.innerText !== canonical) {
      this.el.innerText = canonical;
    }
  },

  destroyed() {
    this.el.removeEventListener("blur", this._onBlur);
    this.el.removeEventListener("keydown", this._onKeydown);
  },
};

export default ContentEditable;
