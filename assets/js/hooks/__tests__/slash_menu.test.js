/**
 * @vitest-environment jsdom
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { SlashMenu } from "../slash_menu.js";
import "../../components/ora-slash-menu.js";

// Track Lexical root state across tests for the module-level mock
const mockRootState = { text: "" };


// jsdom doesn't implement scrollIntoView; polyfill for Lit component
if (typeof Element.prototype.scrollIntoView !== 'function') {
  Element.prototype.scrollIntoView = () => {};
}

vi.mock("lexical", () => {
  const mockRoot = {
    getTextContent: () => mockRootState.text,
    clear: () => {
      mockRootState.text = "";
    },
    append: vi.fn((node) => {
      mockRootState.text = node.__text ?? node.getTextContent?.() ?? "";
    }),
    select: vi.fn(),
    selectStart: vi.fn(),
    getLastDescendant: vi.fn(),
  };
  return {
    $getRoot: vi.fn(() => mockRoot),
    $createTextNode: vi.fn((text) => ({
      getTextContent: () => text,
      __text: text,
    })),
    $getSelection: vi.fn(() => null),
  };
});

// ── helpers ────────────────────────────────────────────────────────────

/**
 * Create an <ora-block> with a mock Lexical editor.
 * @param {string} id
 * @returns {HTMLElement}
 */
function createOraBlock(id) {
  const el = document.createElement("ora-block");
  el.setAttribute("block-id", id);
  el._editor = {
    getEditorState: () => ({
      read: vi.fn((cb) => cb()),
    }),
    update: vi.fn((cb) => {
      cb();
    }),
    focus: vi.fn(),
  };
  return el;
}

/**
 * Mount the SlashMenu hook.
 */
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

/**
 * Simulate "/" being typed at a given offset in a text node.
 * Sets window selection to the position after "/", then dispatches
 * an InputEvent matching Lexical's insertText behavior.
 *
 * Dispatches on the container node so events bubble up through the DOM
 * tree (textNode → ora-block → body → document), giving the hook's
 * `_resolveOraBlock` a proper composedPath to traverse.
 *
 * @param {Node} container - node containing the text (e.g. textNode inside ora-block)
 * @param {number} offset - position after "/" (i.e. offset-1 is "/")
 * @returns {boolean} whether the input event was dispatched
 */
function typeSlash(container, offset) {
  const range = document.createRange();
  range.setStart(container, offset);
  range.collapse(true);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(range);

  const event = new InputEvent("input", {
    inputType: "insertText",
    data: "/",
    bubbles: true,
    cancelable: true,
  });
  return container.dispatchEvent(event);
}

/** Reset window selection. */
function clearSelection() {
  window.getSelection().removeAllRanges();
}

/** Clean up a mounted hook and its host. */
function destroyHook(env) {
  SlashMenu.destroyed.call(env.ctx);
  if (env.host.parentNode) {
    env.host.parentNode.removeChild(env.host);
  }
}

// ── tests ──────────────────────────────────────────────────────────────

describe("SlashMenu hook", () => {
  /** @type {{ host: HTMLElement, ctx: object, menu: HTMLElement, pushEvent: import("vitest").Mock }} */
  let env;

  beforeEach(() => {
    vi.clearAllMocks();
    env = mountHook();
    clearSelection();
  });

  afterEach(() => {
    destroyHook(env);
  });

  // ── Test 1: "/" at line start triggers menu ───────────────────────

  it('detects "/" at text start and shows menu with position', () => {
    const block = createOraBlock("b1");
    document.body.appendChild(block);
    const textNode = document.createTextNode("/");
    block.appendChild(textNode);
    typeSlash(textNode, 1);

    expect(env.menu.hasAttribute("visible")).toBe(true);

    document.body.removeChild(block);
  });

  // ── Test 2: "/" after whitespace triggers menu ────────────────────

  it('detects "/" after whitespace and shows menu', () => {
    const block = createOraBlock("b2");
    document.body.appendChild(block);
    const textNode = document.createTextNode("hello /");
    block.appendChild(textNode);
    typeSlash(textNode, 7);

    expect(env.menu.hasAttribute("visible")).toBe(true);

    document.body.removeChild(block);
  });

  // ── Test 3: "/" mid-word does NOT trigger ─────────────────────────

  it('does NOT trigger for "/" mid-word', () => {
    const block = createOraBlock("b3");
    document.body.appendChild(block);
    const textNode = document.createTextNode("foo/bar");
    block.appendChild(textNode);
    typeSlash(textNode, 4);

    expect(env.menu.hasAttribute("visible")).toBe(false);

    document.body.removeChild(block);
  });

  // ── Test 4: input outside ora-block does not trigger ──────────────

  it("does NOT trigger for input outside any ora-block", () => {
    const outside = document.createElement("div");
    outside.contentEditable = "true";
    outside.textContent = "/";
    document.body.appendChild(outside);

    const textNode = outside.firstChild;
    typeSlash(textNode, 1);

    expect(env.menu.hasAttribute("visible")).toBe(false);

    document.body.removeChild(outside);
  });

  // ── Test 5: click on menu item dispatches pushEvent ───────────────

  it("dispatches pushEvent on item select", () => {
    const block = createOraBlock("b1");
    document.body.appendChild(block);
    const textNode = document.createTextNode("/");
    block.appendChild(textNode);
    typeSlash(textNode, 1);

    expect(env.menu.hasAttribute("visible")).toBe(true);
    expect(env.pushEvent).not.toHaveBeenCalled();

    env.host.dispatchEvent(
      new CustomEvent("select", {
        detail: { type: "heading_1" },
        bubbles: true,
        composed: true,
      })
    );

    expect(env.pushEvent).toHaveBeenCalledTimes(1);
    expect(env.pushEvent).toHaveBeenCalledWith("insert_block_below", {
      block_id: "b1",
      type: "heading_1",
    });
    expect(env.menu.hasAttribute("visible")).toBe(false);

    document.body.removeChild(block);
  });

  // ── Test 6: contract guard — real `select` event works ────────────────

  it("dispatches pushEvent for real `select` CustomEvent", () => {
    const block = createOraBlock("b1");
    document.body.appendChild(block);
    const textNode = document.createTextNode("/");
    block.appendChild(textNode);
    typeSlash(textNode, 1);

    expect(env.menu.hasAttribute("visible")).toBe(true);
    expect(env.pushEvent).not.toHaveBeenCalled();

    env.host.dispatchEvent(
      new CustomEvent("select", {
        detail: { type: "heading_2" },
        bubbles: true,
        composed: true,
      })
    );

    expect(env.pushEvent).toHaveBeenCalledTimes(1);
    expect(env.pushEvent).toHaveBeenCalledWith("insert_block_below", {
      block_id: "b1",
      type: "heading_2",
    });
    expect(env.menu.hasAttribute("visible")).toBe(false);

    document.body.removeChild(block);
  });

  // ── Test 7: keyboard nav — ArrowDown×2 + Enter → heading_2 ───────────

  it("dispatches insert_block_below for keyboard-selected item", () => {
    const block = createOraBlock("b1");
    document.body.appendChild(block);
    const textNode = document.createTextNode("/");
    block.appendChild(textNode);
    typeSlash(textNode, 1);

    expect(env.menu.hasAttribute("visible")).toBe(true);
    expect(env.pushEvent).not.toHaveBeenCalled();

    // Simulate keyboard nav via the Lit component's window keydown handler.
    // After import of ora-slash-menu.js, the custom element is upgraded to
    // OraSlashMenu and its window keydown listener is active.
    // ArrowDown twice selects FALLBACK_ITEMS[2] = heading_2, then Enter dispatches select.
    window.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true }));
    window.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true }));
    window.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true }));

    expect(env.pushEvent).toHaveBeenCalledTimes(1);
    expect(env.pushEvent).toHaveBeenCalledWith("insert_block_below", {
      block_id: "b1",
      type: "heading_2",
    });
    expect(env.menu.hasAttribute("visible")).toBe(false);

    document.body.removeChild(block);
  });

  // ── Test 8: filter narrows ───────────────────────────────────────────

  it("filter narrows items as user types", () => {
    const block = createOraBlock("b1");
    document.body.appendChild(block);
    const textNode = document.createTextNode("/");
    block.appendChild(textNode);
    typeSlash(textNode, 1);

    expect(env.menu.hasAttribute("visible")).toBe(true);

    // The Lit component's _onInput sets _filter from the input event target value
    env.menu._onInput({ target: { value: "h" } });
    expect(env.menu._filter).toBe("h");

    env.menu._onInput({ target: { value: "h1" } });
    expect(env.menu._filter).toBe("h1");

    document.body.removeChild(block);
  });

  // ── Test 9: backspace narrows back ────────────────────────────────────

  it("backspace narrows filter back", () => {
    const block = createOraBlock("b1");
    document.body.appendChild(block);
    const textNode = document.createTextNode("/");
    block.appendChild(textNode);
    typeSlash(textNode, 1);

    expect(env.menu.hasAttribute("visible")).toBe(true);

    env.menu._onInput({ target: { value: "h1" } });
    expect(env.menu._filter).toBe("h1");

    env.menu._onInput({ target: { value: "h" } });
    expect(env.menu._filter).toBe("h");

    document.body.removeChild(block);
  });

  // ── Test 10: backspace past trigger closes menu ───────────────────────

  it("backspace past trigger closes menu", () => {
    const block = createOraBlock("b1");
    document.body.appendChild(block);
    const textNode = document.createTextNode("/");
    block.appendChild(textNode);
    typeSlash(textNode, 1);

    expect(env.menu.hasAttribute("visible")).toBe(true);
    expect(env.ctx._open).toBe(true);

    // Filter is empty, Backspace document keydown should close menu
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Backspace", bubbles: true }));

    expect(env.menu.hasAttribute("visible")).toBe(false);
    expect(env.ctx._open).toBe(false);

    document.body.removeChild(block);
  });

  // ── Test 11: Escape closes without dispatching ─────────────────────

  it("Escape closes menu without pushEvent", () => {
    const block = createOraBlock("b1");
    document.body.appendChild(block);
    const textNode = document.createTextNode("/");
    block.appendChild(textNode);
    typeSlash(textNode, 1);

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

    const range = document.createRange();
    range.selectNodeContents(block);
    range.collapse(false);
    env.ctx._triggerRange = range.cloneRange();
    env.ctx._activeEditor = block._editor;
    env.ctx._activeBlockId = "b1";
    env.ctx._triggerPreLength = 3;
    env.ctx._open = true;
    env.menu.setAttribute("visible", "");

    expect(env.menu.hasAttribute("visible")).toBe(true);

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

  // ── Test 13: destroyed cleans up listeners ─────────────────────────

  it("destroyed removes event listeners and hides menu", () => {
    const block = createOraBlock("b1");
    document.body.appendChild(block);
    const textNode = document.createTextNode("/");
    block.appendChild(textNode);
    typeSlash(textNode, 1);

    expect(env.menu.hasAttribute("visible")).toBe(true);

    const spy = vi.spyOn(document, "removeEventListener");
    const hostSpy = vi.spyOn(env.host, "removeEventListener");

    SlashMenu.destroyed.call(env.ctx);

    expect(spy).toHaveBeenCalledWith("input", expect.any(Function));
    expect(spy).toHaveBeenCalledWith("keydown", expect.any(Function));
    expect(spy).toHaveBeenCalledWith("click", expect.any(Function));
    expect(hostSpy).toHaveBeenCalledWith("select", expect.any(Function));
    expect(hostSpy).toHaveBeenCalledWith("close", expect.any(Function));
    expect(env.menu.hasAttribute("visible")).toBe(false);

    document.body.removeChild(block);
  });
});
