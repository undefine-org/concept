import Sortable from "sortablejs";

const BlockList = {
  mounted() {
    this._syncDisabled();
    this.sortable = new Sortable(this.el, {
      handle: ".ora-drag-handle",
      animation: 150,
      ghostClass: "ora-drag-ghost",
      filter: ".sortable-disabled",
      preventOnFilter: false,
      onEnd: (evt) => {
        const movedEl = evt.item;
        const blockId = movedEl.dataset.blockId;
        if (!blockId) return;

        const prevEl = movedEl.previousElementSibling;
        const nextEl = movedEl.nextElementSibling;
        const prevId = prevEl?.dataset.blockId || null;
        const nextId = nextEl?.dataset.blockId || null;

        this.pushEvent("reorder_block", {
          block_id: blockId,
          prev_id: prevId,
          next_id: nextId,
        });
      },
    });
  },

  updated() {
    this._syncDisabled();
  },

  destroyed() {
    if (this.sortable) {
      this.sortable.destroy();
    }
  },

  _syncDisabled() {
    for (const child of this.el.children) {
      if (child.hasAttribute("data-locked-by-other")) {
        child.classList.add("sortable-disabled");
      } else {
        child.classList.remove("sortable-disabled");
      }
    }
  },
};

export default BlockList;
