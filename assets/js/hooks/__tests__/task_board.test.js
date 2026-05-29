/**
 * @vitest-environment jsdom
 */

import { describe, it, expect, vi, beforeEach } from "vitest";
import TaskBoard from "../task_board";

const mockSortable = vi.hoisted(() => vi.fn(() => ({ destroy: vi.fn() })));

vi.mock("sortablejs", () => ({ default: mockSortable }));

beforeEach(() => {
  mockSortable.mockClear();
});

// Build a board container with two columns carrying data-state-id.
function boardEl() {
  const el = document.createElement("div");
  for (const sid of ["state-backlog", "state-todo"]) {
    const col = document.createElement("div");
    col.dataset.stateId = sid;
    el.appendChild(col);
  }
  return el;
}

// Bind the full hook (its helper methods are own-properties, not prototype).
function ctx(el, pushEvent) {
  return Object.assign({ el, pushEvent }, TaskBoard);
}

describe("TaskBoard hook", () => {
  it("wires one Sortable per column with the shared group", () => {
    const el = boardEl();
    TaskBoard.mounted.call(ctx(el));
    expect(mockSortable).toHaveBeenCalledTimes(2);
    expect(mockSortable).toHaveBeenCalledWith(
      expect.any(HTMLElement),
      expect.objectContaining({ group: "task-board", draggable: "[data-record-id]" }),
    );
  });

  it("pushes a move event on a cross-column drop", () => {
    const el = boardEl();
    const pushEvent = vi.fn();
    let onEnd;
    mockSortable.mockImplementation((_el, opts) => {
      onEnd = opts.onEnd;
      return { destroy: vi.fn() };
    });
    TaskBoard.mounted.call(ctx(el, pushEvent));

    const card = document.createElement("div");
    card.setAttribute("data-record-id", "rec-1");
    onEnd({
      item: card,
      from: { dataset: { stateId: "state-backlog" } },
      to: { dataset: { stateId: "state-todo" } },
    });

    expect(pushEvent).toHaveBeenCalledWith("move", { record: "rec-1", to: "state-todo" });
  });

  it("does not push on an intra-column drop", () => {
    const el = boardEl();
    const pushEvent = vi.fn();
    let onEnd;
    mockSortable.mockImplementation((_el, opts) => {
      onEnd = opts.onEnd;
      return { destroy: vi.fn() };
    });
    TaskBoard.mounted.call(ctx(el, pushEvent));

    const card = document.createElement("div");
    card.setAttribute("data-record-id", "rec-1");
    onEnd({
      item: card,
      from: { dataset: { stateId: "state-todo" } },
      to: { dataset: { stateId: "state-todo" } },
    });

    expect(pushEvent).not.toHaveBeenCalled();
  });

  it("destroys all sortables on destroyed", () => {
    const el = boardEl();
    const destroy = vi.fn();
    mockSortable.mockImplementation(() => ({ destroy }));
    const c = ctx(el);
    TaskBoard.mounted.call(c);
    TaskBoard.destroyed.call(c);
    expect(destroy).toHaveBeenCalledTimes(2);
  });
});
