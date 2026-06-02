// MarkRead — advance the participant's read cursor when the conversation's
// latest message is in view. Fires the "mark_read" event (debounced) with the
// latest message id; the server records it on the participant. Keyed off
// data-latest-id, which is present only while there is something unread.
export default {
  mounted() {
    this.maybeMark();
  },

  updated() {
    this.maybeMark();
  },

  maybeMark() {
    const latest = this.el.dataset.latestId;
    if (!latest || latest === this._marked) return;

    // Only mark when the panel is actually visible (not a background tab).
    if (document.visibilityState === "hidden") return;

    clearTimeout(this._t);
    this._t = setTimeout(() => {
      this._marked = latest;
      this.pushEventTo(this.el, "mark_read", { message_id: latest });
    }, 400);
  },
};
