/**
 * @vitest-environment jsdom
 */
import { describe, it, expect, vi, beforeEach } from "vitest";
import Sortable from "sortablejs";
import BlockList from "../block_list.js";

const mockSortable = vi.hoisted(() => vi.fn(() => ({ destroy: vi.fn() })));

vi.mock("sortablejs", () => ({
  default: mockSortable,
}));

function createContext(ul, pushEvent) {
  return Object.assign(
    { el: ul, pushEvent, sortable: null },
    BlockList
  );
}

function createList(blocks) {
  const ul = document.createElement("ul");
  ul.id = "block-list-test";

  for (const b of blocks) {
    const li = document.createElement("li");
    li.dataset.blockId = b.id;
    li.innerHTML = `<ora-block>${b.text}</ora-block>`;
    ul.appendChild(li);
  }

  document.body.appendChild(ul);
  return ul;
}

describe("BlockList hook", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("creates Sortable instance on mount", () => {
    const ul = createList([{ id: "b1", text: "A" }]);

    BlockList.mounted.call(createContext(ul, vi.fn()));

    expect(mockSortable).toHaveBeenCalledTimes(1);
    expect(mockSortable).toHaveBeenCalledWith(
      ul,
      expect.objectContaining({
        handle: ".ora-drag-handle",
        animation: 150,
      }),
    );

    document.body.removeChild(ul);
  });

  it("onEnd dispatches pushEvent with block_id, prev_id, next_id", () => {
    const blocks = [
      { id: "b1", text: "A" },
      { id: "b2", text: "B" },
      { id: "b3", text: "C" },
    ];
    const ul = createList(blocks);
    const pushEvent = vi.fn();

    BlockList.mounted.call(createContext(ul, pushEvent));

    const onEnd = mockSortable.mock.calls[0][1].onEnd;

    // Simulate SortableJS rearranging the DOM: move b1 to after b2
    const b1El = ul.children[0];
    const b3El = ul.children[2];
    ul.insertBefore(b1El, b3El);
    // DOM order after drop: b2, b1, b3

    onEnd({ item: b1El, currentTarget: ul });

    expect(pushEvent).toHaveBeenCalledWith("reorder_block", {
      block_id: "b1",
      prev_id: "b2",
      next_id: "b3",
    });

    document.body.removeChild(ul);
  });

  it("onEnd with first position drop sets prev_id = null", () => {
    const blocks = [
      { id: "b1", text: "A" },
      { id: "b2", text: "B" },
      { id: "b3", text: "C" },
    ];
    const ul = createList(blocks);
    const pushEvent = vi.fn();

    BlockList.mounted.call(createContext(ul, pushEvent));

    const onEnd = mockSortable.mock.calls[0][1].onEnd;

    // Simulate SortableJS: move b3 to first position
    const b3El = ul.children[2];
    ul.insertBefore(b3El, ul.firstChild);
    // DOM order after drop: b3, b1, b2

    onEnd({ item: b3El, currentTarget: ul });

    expect(pushEvent).toHaveBeenCalledWith("reorder_block", {
      block_id: "b3",
      prev_id: null,
      next_id: "b1",
    });

    document.body.removeChild(ul);
  });

  it("onEnd with last position drop sets next_id = null", () => {
    const blocks = [
      { id: "b1", text: "A" },
      { id: "b2", text: "B" },
      { id: "b3", text: "C" },
    ];
    const ul = createList(blocks);
    const pushEvent = vi.fn();

    BlockList.mounted.call(createContext(ul, pushEvent));

    const onEnd = mockSortable.mock.calls[0][1].onEnd;

    // Simulate SortableJS: move b1 to last position
    const b1El = ul.children[0];
    ul.appendChild(b1El);
    // DOM order after drop: b2, b3, b1

    onEnd({ item: b1El, currentTarget: ul });

    expect(pushEvent).toHaveBeenCalledWith("reorder_block", {
      block_id: "b1",
      prev_id: "b3",
      next_id: null,
    });

    document.body.removeChild(ul);
  });

  it("does not pushEvent when blockId is missing", () => {
    const ul = document.createElement("ul");
    const li = document.createElement("li");
    // No data-block-id
    ul.appendChild(li);
    document.body.appendChild(ul);

    const pushEvent = vi.fn();
    BlockList.mounted.call(createContext(ul, pushEvent));

    const onEnd = mockSortable.mock.calls[0][1].onEnd;
    onEnd({ item: li, currentTarget: ul });

    expect(pushEvent).not.toHaveBeenCalled();

    document.body.removeChild(ul);
  });

  it("destroys Sortable on unmount", () => {
    const destroy = vi.fn();
    mockSortable.mockReturnValue({ destroy });

    const ul = createList([{ id: "b1", text: "A" }]);
    const ctx = createContext(ul, vi.fn());
    BlockList.mounted.call(ctx);
    BlockList.destroyed.call(ctx);

    expect(destroy).toHaveBeenCalledTimes(1);

    document.body.removeChild(ul);
  });

  it("syncs disabled state on mount and update", () => {
    const blocks = [
      { id: "b1", text: "A", locked: true },
      { id: "b2", text: "B", locked: false },
    ];
    const ul = createList(blocks);
    BlockList.mounted.call(createContext(ul, vi.fn()));

    expect(
      ul.children[0].classList.contains("sortable-disabled"),
    ).toBe(false);
    expect(
      ul.children[1].classList.contains("sortable-disabled"),
    ).toBe(false);

    document.body.removeChild(ul);
  });
});
