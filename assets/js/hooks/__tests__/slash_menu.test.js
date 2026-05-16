/**
 * @vitest-environment jsdom
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { SlashMenu } from "../slash_menu.js";
import "../../components/ora-slash-menu.js";

// Track Lexical root state across tests for the module-level mock.
const mockRootState = { text: "" };
// Selection state consumed by the mock $getSelection.
const mockSelState = { offset: 0, nodeText: "" };

// jsdom doesn't implement scrollIntoView; polyfill for the Lit component.
if (typeof Element.prototype.scrollIntoView !== "function") {
  Element.prototype.scrollIntoView = () => {};
}

vi.mock("lexical", () => {
  const mockRoot = {
    getTextContent: () => mockRootState.text,
    clear: () => {
      mockRootState.text = "";
    },
    getChildren: () => [],
    append: vi.fn((node) => {
      const t = node.__text ?? node.getTextContent?.() ?? "";
      mockRootState.text = t;
    }),
    select: vi.fn(),
    selectStart: vi.fn(),
    getLastDescendant: vi.fn(),
  };
  const mockSelection = {
    isCollapsed: () => true,
    anchor: {
      get offset() {
        return mockSelState.offset;
      },
      getNode: () => ({
        getTextContent: () => mockSelState.nodeText,
      }),
    },
  };
  const mockParagraph = {
    _text: "",
    append: vi.fn((node) => {
      mockParagraph._text = node.__text ?? node.getTextContent?.() ?? "";
    }),
    getTextContent: () => mockParagraph._text,
  };
  return {
    $getRoot: vi.fn(() => mockRoot),
    $createTextNode: vi.fn((text) => ({
      getTextContent: () => text,
      __text: text,
    })),
    $createParagraphNode: vi.fn(() => mockParagraph),
    $getSelection: vi.fn(() => mockSelection),
  };
});

// ── helpers ───────────────────────────────────────────────────────────────

/**
 * Create an <ora-block> with a mock Lexical editor that supports
 * `registerTextContentListener`.
 */
function createOraBlock(id) {
  const el = document.createElement("ora-block");
  el.setAttribute("block-id", id);
  const listeners = [];
  el._editor = {
    getEditorState: () => ({
      read: (cb) => cb(),
    }),
    update: vi.fn((cb) => {
      cb();
    }),
    focus: vi.fn(),
    registerTextContentListener: vi.fn((cb) => {
      listeners.push(cb);
      return () => {
        const i = listeners.indexOf(cb);
        if (i >= 0) listeners.splice(i, 1);
      };
    }),
    _listeners: listeners,
  };
  return el;
}

/** Fire ora-block-focus so the hook subscribes to the editor's listener. */
function focusBlock(block) {
  block.dispatchEvent(
    new CustomEvent("ora-block-focus", {
      detail: { blockId: block.getAttribute("block-id") },
      bubbles: true,
    }),
  );
}

/**
 * Simulate the user typing inside a block:
 *  - sets the mocked Lexical state (full text + caret + node text)
 *  - invokes the registered text-content listener(s) on the editor
 *
 * Requires the block to be focused first (focusBlock).
 */
function emitText(block, text, offset, nodeText) {
  mockRootState.text = text;
  mockSelState.nodeText = nodeText ?? text;
  mockSelState.offset = offset;
  for (const cb of block._editor._listeners) cb(text);
}

function mountHook() {
  const host = document.createElement("div");
  host.id = "slash-menu-host";
  host.innerHTML = `<ora-slash-menu></ora-slash-menu>`;
  document.body.appendChild(host);

  const pushEvent = vi.fn();
  const ctx = Object.assign({ el: host, pushEvent }, SlashMenu);
  SlashMenu.mounted.call(ctx);
  return { host, ctx, menu: host.querySelector("ora-slash-menu"), pushEvent };
}

function destroyHook(env) {
  SlashMenu.destroyed.call(env.ctx);
  if (env.host.parentNode) {
    env.host.parentNode.removeChild(env.host);
  }
}

// ── tests ─────────────────────────────────────────────────────────────────

describe("SlashMenu hook", () => {
  /** @type {{ host: HTMLElement, ctx: object, menu: HTMLElement, pushEvent: import("vitest").Mock }} */
  let env;

  beforeEach(() => {
    vi.clearAllMocks();
    mockRootState.text = "";
    mockSelState.offset = 0;
    mockSelState.nodeText = "";
    env = mountHook();
  });

  afterEach(() => {
    destroyHook(env);
  });

  // ── Test 1: "/" at text-start triggers menu ─────────────────────

  it('detects "/" at text start and shows menu', () => {
    const block = createOraBlock("b1");
    document.body.appendChild(block);
    focusBlock(block);
    emitText(block, "/", 1);

    expect(env.menu.hasAttribute("visible")).toBe(true);
    expect(env.ctx._open).toBe(true);

    document.body.removeChild(block);
  });

  // ── Test 2: "/" after whitespace triggers menu ──────────────────

  it('detects "/" after whitespace and shows menu', () => {
    const block = createOraBlock("b2");
    document.body.appendChild(block);
    focusBlock(block);
    emitText(block, "hello /", 7);

    expect(env.menu.hasAttribute("visible")).toBe(true);

    document.body.removeChild(block);
  });

  // ── Test 3: "/" mid-word does NOT trigger ───────────────────────

  it('does NOT trigger for "/" mid-word', () => {
    const block = createOraBlock("b3");
    document.body.appendChild(block);
    focusBlock(block);
    emitText(block, "foo/bar", 4);

    expect(env.menu.hasAttribute("visible")).toBe(false);

    document.body.removeChild(block);
  });

  // ── Test 4: text change in non-focused block does not trigger ─────

  it("does NOT trigger when no ora-block has been focused", () => {
    const block = createOraBlock("b1");
    document.body.appendChild(block);
    // Do NOT focusBlock(block) — hook never subscribes.
    emitText(block, "/", 1);

    expect(env.menu.hasAttribute("visible")).toBe(false);

    document.body.removeChild(block);
  });

  // ── Test 5: click select dispatches pushEvent ────────────────────

  it("dispatches pushEvent on item select", () => {
    const block = createOraBlock("b1");
    document.body.appendChild(block);
    focusBlock(block);
    emitText(block, "/", 1);

    expect(env.menu.hasAttribute("visible")).toBe(true);
    expect(env.pushEvent).not.toHaveBeenCalled();

    env.host.dispatchEvent(
      new CustomEvent("select", {
        detail: { type: "heading_1" },
        bubbles: true,
        composed: true,
      }),
    );

    expect(env.pushEvent).toHaveBeenCalledTimes(1);
    expect(env.pushEvent).toHaveBeenCalledWith("insert_block_below", {
      block_id: "b1",
      type: "heading_1",
    });
    expect(env.menu.hasAttribute("visible")).toBe(false);

    document.body.removeChild(block);
  });

  // ── Test 6: real `select` CustomEvent works ────────────────────

  it("dispatches pushEvent for real `select` CustomEvent", () => {
    const block = createOraBlock("b1");
    document.body.appendChild(block);
    focusBlock(block);
    emitText(block, "/", 1);

    env.host.dispatchEvent(
      new CustomEvent("select", {
        detail: { type: "heading_2" },
        bubbles: true,
        composed: true,
      }),
    );

    expect(env.pushEvent).toHaveBeenCalledTimes(1);
    expect(env.pushEvent).toHaveBeenCalledWith("insert_block_below", {
      block_id: "b1",
      type: "heading_2",
    });

    document.body.removeChild(block);
  });

  // ── Test 7: keyboard nav ─ ArrowDown×2 + Enter → heading_2 ──────────

  it("dispatches insert_block_below for keyboard-selected item", () => {
    const block = createOraBlock("b1");
    document.body.appendChild(block);
    focusBlock(block);
    emitText(block, "/", 1);

    window.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true }));
    window.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true }));
    window.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true }));

    expect(env.pushEvent).toHaveBeenCalledTimes(1);
    expect(env.pushEvent).toHaveBeenCalledWith("insert_block_below", {
      block_id: "b1",
      type: "heading_2",
    });

    document.body.removeChild(block);
  });

  // ── Test 8: filter narrows ──────────────────────────────────────────────

  it("filter narrows items as user types", () => {
    const block = createOraBlock("b1");
    document.body.appendChild(block);
    focusBlock(block);
    emitText(block, "/", 1);

    env.menu._onInput({ target: { value: "h" } });
    expect(env.menu._filter).toBe("h");

    env.menu._onInput({ target: { value: "h1" } });
    expect(env.menu._filter).toBe("h1");

    document.body.removeChild(block);
  });

  // ── Test 9: backspace narrows back ───────────────────────────────────

  it("backspace narrows filter back", () => {
    const block = createOraBlock("b1");
    document.body.appendChild(block);
    focusBlock(block);
    emitText(block, "/", 1);

    env.menu._onInput({ target: { value: "h1" } });
    expect(env.menu._filter).toBe("h1");

    env.menu._onInput({ target: { value: "h" } });
    expect(env.menu._filter).toBe("h");

    document.body.removeChild(block);
  });

  // ── Test 10: backspace past trigger closes menu ────────────────────

  it("backspace past trigger closes menu", () => {
    const block = createOraBlock("b1");
    document.body.appendChild(block);
    focusBlock(block);
    emitText(block, "/", 1);

    expect(env.menu.hasAttribute("visible")).toBe(true);
    expect(env.ctx._open).toBe(true);

    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Backspace", bubbles: true }));

    expect(env.menu.hasAttribute("visible")).toBe(false);
    expect(env.ctx._open).toBe(false);

    document.body.removeChild(block);
  });

  // ── Test 11: Escape closes without dispatching ────────────────────

  it("Escape closes menu without pushEvent", () => {
    const block = createOraBlock("b1");
    document.body.appendChild(block);
    focusBlock(block);
    emitText(block, "/", 1);

    expect(env.menu.hasAttribute("visible")).toBe(true);

    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));

    expect(env.menu.hasAttribute("visible")).toBe(false);
    expect(env.pushEvent).not.toHaveBeenCalled();

    document.body.removeChild(block);
  });

  // ── Test 12: removes leading slash from source block on item select ───

  it("removes leading slash from source block on item select", () => {
    const block = createOraBlock("b1");
    document.body.appendChild(block);
    mockRootState.text = "foo/h1";

    env.ctx._activeEditor = block._editor;
    env.ctx._activeBlockId = "b1";
    env.ctx._triggerPreLength = 3;
    env.ctx._open = true;
    env.menu.setAttribute("visible", "");

    env.host.dispatchEvent(
      new CustomEvent("select", {
        detail: { type: "heading_1" },
        bubbles: true,
        composed: true,
      }),
    );

    expect(mockRootState.text).toBe("foo");
    expect(env.pushEvent).toHaveBeenCalledWith("insert_block_below", {
      block_id: "b1",
      type: "heading_1",
    });

    document.body.removeChild(block);
  });

  // ── Phase A: filter case-fold + normalize (BUG-033 defect 1) ────────

  it("filter 'h1' matches Heading 1", () => {
    const menu = document.createElement("ora-slash-menu");
    document.body.appendChild(menu);
    menu._filter = "h1";
    const labels = menu._filteredItems.map((i) => i.label);
    expect(labels).toContain("Heading 1");
    document.body.removeChild(menu);
  });

  // ── Test 13: destroyed cleans up listeners ──────────────────────────

  it("destroyed removes event listeners and hides menu", () => {
    const block = createOraBlock("b1");
    document.body.appendChild(block);
    focusBlock(block);
    emitText(block, "/", 1);

    expect(env.menu.hasAttribute("visible")).toBe(true);

    const docSpy = vi.spyOn(document, "removeEventListener");
    const hostSpy = vi.spyOn(env.host, "removeEventListener");

    SlashMenu.destroyed.call(env.ctx);

    expect(docSpy).toHaveBeenCalledWith("ora-block-focus", expect.any(Function));
    expect(docSpy).toHaveBeenCalledWith("keydown", expect.any(Function));
    expect(docSpy).toHaveBeenCalledWith("click", expect.any(Function));
    expect(hostSpy).toHaveBeenCalledWith("select", expect.any(Function));
    expect(hostSpy).toHaveBeenCalledWith("close", expect.any(Function));
    expect(env.menu.hasAttribute("visible")).toBe(false);

    document.body.removeChild(block);
  });
});
