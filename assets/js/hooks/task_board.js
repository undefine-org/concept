import Sortable from "sortablejs";

/**
 * TaskBoard — cross-column drag-and-drop for the Tasks board.
 *
 * Structural contract (see docs/objects_and_tasks_ux.md §3.1):
 *   - Each column element carries `data-state-id` (its WorkflowState id).
 *   - Cards carry `data-record-id`.
 *   - On a CROSS-column drop, we push the SAME `"move"` event the move
 *     buttons push (`{record, to}`) → same `transition_record` → same guard
 *     engine. DnD adds zero new server authority; it is a second input
 *     device for the one transition action.
 *   - The server re-renders authoritative board state; if a guard rejects
 *     the move, the LiveView diff overwrites Sortable's optimistic DOM move
 *     (the card "springs back"). No optimistic-state divergence.
 *   - Intra-column drops are a no-op (reorder is a later FUP).
 *
 * The hook is mounted on the board container (`#tasks-board`) and wires one
 * Sortable per column, all sharing the `task-board` group so cards drag
 * between columns.
 */
const TaskBoard = {
  mounted() {
    this._init();
  },

  updated() {
    // Columns can be re-rendered by the LiveView diff; rebuild to bind any
    // new column elements and drop stale instances.
    this._destroy();
    this._init();
  },

  destroyed() {
    this._destroy();
  },

  _init() {
    this._sortables = [];
    const columns = this.el.querySelectorAll("[data-state-id]");

    for (const col of columns) {
      const sortable = new Sortable(col, {
        group: "task-board",
        draggable: "[data-record-id]",
        animation: 150,
        ghostClass: "task-drag-ghost",
        dragClass: "task-drag-item",
        onEnd: (evt) => this._onEnd(evt),
      });

      this._sortables.push(sortable);
    }
  },

  _onEnd(evt) {
    const card = evt.item;
    const recordId = card.dataset.recordId;
    const toStateId = evt.to?.dataset?.stateId;
    const fromStateId = evt.from?.dataset?.stateId;

    if (!recordId || !toStateId) return;
    // Intra-column move: no reorder semantics yet.
    if (toStateId === fromStateId) return;

    this.pushEvent("move", { record: recordId, to: toStateId });
  },

  _destroy() {
    if (this._sortables) {
      for (const s of this._sortables) s.destroy();
      this._sortables = [];
    }
  },
};

export default TaskBoard;
