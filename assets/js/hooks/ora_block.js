/**
 * Phoenix LiveView hook: forwards `ora-<verb>` CustomEvents fired by a child
 * Lit element to the owning LiveComponent.
 *
 * Wiring source-of-truth: the block-type module's `ash_actions` declaration.
 * The `Concept.Pages.BlockType.Interactive` macro renders the wrapper
 * `<div phx-hook="OraBlock" data-events="evaluate refresh retry">` with the
 * verbs derived from `ash_actions` — so this hook reads `data-events`,
 * subscribes to one `ora-<verb>` event per token, and pushes the same verb
 * back to the LiveComponent identified by `this.el` itself.
 *
 * Receives `ora:token` server pushes and forwards them to the inner Lit
 * component's `appendToken(token)` method when block IDs match.
 */
export const OraBlock = {
  mounted() {
    const verbs = (this.el.dataset.events || "").trim().split(/\s+/).filter(Boolean);
    const blockId = this.el.dataset.blockId;

    this._listeners = verbs.map((verb) => {
      const fn = (e) =>
        this.pushEventTo(this.el, verb, {
          block_id: blockId,
          ...(e.detail || {}),
        });
      this.el.addEventListener(`ora-${verb}`, fn);
      return [verb, fn];
    });

    this.handleEvent("ora:token", (payload) => {
      if (payload.block_id !== blockId) return;
      const inner = this.el.firstElementChild;
      if (inner && typeof inner.appendToken === "function") {
        inner.appendToken(payload.token);
      }
    });
  },

  destroyed() {
    this._listeners?.forEach(([verb, fn]) => {
      this.el.removeEventListener(`ora-${verb}`, fn);
    });
  },
};

export default OraBlock;
