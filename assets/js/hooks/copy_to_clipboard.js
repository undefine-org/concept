// CopyToClipboard — copy a data-clipboard-text value on click, with a brief
// "copied" affordance. Client-only (no round-trip); a message is already
// addressable by id, so a copy-link is a pure clipboard write.
export default {
  mounted() {
    this.el.addEventListener("click", (e) => {
      e.preventDefault();
      const text = this.el.dataset.clipboardText || "";
      const done = () => this.flash();
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(done).catch(() => this.fallback(text, done));
      } else {
        this.fallback(text, done);
      }
    });
  },

  fallback(text, done) {
    const ta = document.createElement("textarea");
    ta.value = text;
    ta.style.position = "fixed";
    ta.style.opacity = "0";
    document.body.appendChild(ta);
    ta.select();
    try {
      document.execCommand("copy");
    } catch (_) {
      /* no-op */
    }
    document.body.removeChild(ta);
    done();
  },

  flash() {
    this.el.setAttribute("data-copied", "true");
    this.el.setAttribute("title", "Copied!");
    setTimeout(() => {
      this.el.removeAttribute("data-copied");
      this.el.setAttribute("title", "Copy link to message");
    }, 1200);
  },
};
