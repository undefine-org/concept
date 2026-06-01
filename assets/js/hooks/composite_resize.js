// CompositeResize — drag the handle between two columns to repartition their
// width. The grid is driven by `fr` ratios (server truth in block.props.ratios);
// during a drag we mutate grid-template-columns live for instant feedback, then
// push `resize_columns` with the final ratios on pointer-up to persist.
//
// Declared once for the Composite flavour (C-6): every resizable composite that
// renders the .ora-column-resizer handles gets this behaviour for free.
const CompositeResize = {
  mounted() {
    this.grid = this.el.querySelector(".ora-columns-grid");
    if (!this.grid) return;

    this.el.querySelectorAll(".ora-column-resizer").forEach((handle) => {
      handle.addEventListener("pointerdown", (e) => this._start(e, handle));
    });
  },

  _ratios() {
    // Read current fr values from the computed template.
    return this.grid.style.gridTemplateColumns
      .split(" ")
      .filter((t) => t.endsWith("fr"))
      .map((t) => parseFloat(t));
  },

  _start(e, handle) {
    e.preventDefault();
    const idx = parseInt(handle.dataset.resizerIndex, 10);
    const ratios = this._ratios();
    const cols = [...this.grid.querySelectorAll(".ora-column")];
    const leftRect = cols[idx].getBoundingClientRect();
    const rightRect = cols[idx + 1].getBoundingClientRect();
    const startX = e.clientX;
    const pairSpan = leftRect.width + rightRect.width;
    const pairRatio = ratios[idx] + ratios[idx + 1];

    const move = (ev) => {
      const dx = ev.clientX - startX;
      // Fraction of the pair the left column now occupies, clamped so neither
      // column collapses below 10% of the pair.
      let leftFrac = (leftRect.width + dx) / pairSpan;
      leftFrac = Math.max(0.1, Math.min(0.9, leftFrac));
      ratios[idx] = pairRatio * leftFrac;
      ratios[idx + 1] = pairRatio * (1 - leftFrac);
      this.grid.style.gridTemplateColumns = ratios
        .map((r) => `${r.toFixed(4)}fr`)
        .join(" ");
    };

    const up = () => {
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);
      document.body.classList.remove("ora-col-resizing");
      this.pushEvent("resize_columns", {
        block_id: this.el.dataset.blockId,
        ratios: this._ratios(),
      });
    };

    document.body.classList.add("ora-col-resizing");
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
  },
};

export default CompositeResize;
