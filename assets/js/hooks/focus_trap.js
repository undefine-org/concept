// FocusTrap — keeps keyboard focus inside an overlay (modal, slide-over,
// picker) and restores it to the previously-focused element on teardown.
// Esc forwards an "ora-modal-close" CustomEvent so the server (or a parent
// hook) can decide what closing means. One hook, reused by every overlay.
const FOCUSABLE =
  'a[href],button:not([disabled]),textarea:not([disabled]),input:not([disabled]),select:not([disabled]),[tabindex]:not([tabindex="-1"])';

const FocusTrap = {
  mounted() {
    this._previouslyFocused = document.activeElement;

    this._focusables = () =>
      Array.from(this.el.querySelectorAll(FOCUSABLE)).filter(
        (el) => el.offsetParent !== null,
      );

    // Move focus into the overlay (first focusable, else the container).
    const first = this._focusables()[0];
    (first || this.el).focus({ preventScroll: true });

    this._onKeyDown = (e) => {
      if (e.key === "Escape") {
        this.el.dispatchEvent(
          new CustomEvent("ora-modal-close", { bubbles: true }),
        );
        return;
      }
      if (e.key !== "Tab") return;

      const items = this._focusables();
      if (items.length === 0) {
        e.preventDefault();
        return;
      }
      const first = items[0];
      const last = items[items.length - 1];
      const active = document.activeElement;

      if (e.shiftKey && active === first) {
        e.preventDefault();
        last.focus();
      } else if (!e.shiftKey && active === last) {
        e.preventDefault();
        first.focus();
      }
    };

    this.el.addEventListener("keydown", this._onKeyDown);
  },

  destroyed() {
    this.el.removeEventListener("keydown", this._onKeyDown);
    // Restore focus to where the user was before the overlay opened.
    if (this._previouslyFocused && this._previouslyFocused.focus) {
      this._previouslyFocused.focus({ preventScroll: true });
    }
  },
};

export default FocusTrap;
