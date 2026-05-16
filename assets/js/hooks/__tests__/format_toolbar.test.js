/**
 * @vitest-environment jsdom
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { FormatToolbar } from "../format_toolbar.js";
import * as Commands from "../../lexical/commands.js";

// ── helpers ────────────────────────────────────────────────────────────

/**
 * Create an ora-block with a mock Lexical editor that has a spy on
 * dispatchCommand.
 */
function createOraBlock() {
  const el = document.createElement("ora-block");
  el._editor = {
    dispatchCommand: vi.fn(),
    focus: vi.fn(),
  };
  return el;
}

/**
 * Set document.activeElement to a descendant of the given ora-block
 * so that _resolveOraBlock finds it.
 */
function setActiveElementInside(oraBlock) {
  const inner = document.createElement("span");
  inner.setAttribute("data-test", "inner");
  oraBlock.appendChild(inner);
  Object.defineProperty(document, "activeElement", {
    configurable: true,
    get: () => inner,
  });
}

/**
 * Create a text selection inside the given element with the given text.
 * Returns a function to clean up the selection.
 */
function createSelection(container, text) {
  const textNode = document.createTextNode(text);
  container.appendChild(textNode);
  const range = document.createRange();
  range.setStart(textNode, 0);
  range.setEnd(textNode, text.length);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(range);
  return () => {
    sel.removeAllRanges();
    container.removeChild(textNode);
  };
}

/**
 * Mount the FormatToolbar hook by calling mounted() on a context object.
 */
function mountHook() {
  const host = document.createElement("div");
  host.id = "format-toolbar-host";
  host.innerHTML = `
    <ora-format-toolbar></ora-format-toolbar>
    <ora-link-editor></ora-link-editor>
  `;
  document.body.appendChild(host);

  const ctx = { el: host };
  FormatToolbar.mounted.call(ctx);
  return { host, ctx, toolbar: host.querySelector("ora-format-toolbar"), linkEditor: host.querySelector("ora-link-editor") };
}

// ── tests ──────────────────────────────────────────────────────────────

describe("FormatToolbar hook", () => {
  /** @type {{ host: HTMLElement, ctx: object, toolbar: HTMLElement, linkEditor: HTMLElement }} */
  let env;

  beforeEach(() => {
    vi.clearAllMocks();
    vi.spyOn(Commands, "toggleFormat");
    vi.spyOn(Commands, "setLink");

    env = mountHook();
    // Clear any initial selection crud
    window.getSelection().removeAllRanges();
  });

  afterEach(() => {
    FormatToolbar.destroyed.call(env.ctx);
    if (env.host.parentNode) {
      env.host.parentNode.removeChild(env.host);
    }

    // Restore document.activeElement
    delete document.activeElement;
  });

  // ── Test 1: toggle-format dispatches FORMAT_TEXT_COMMAND ─────────

  it("toggle-format dispatches FORMAT_TEXT_COMMAND with format", () => {
    const block = createOraBlock();
    document.body.appendChild(block);
    setActiveElementInside(block);

    const cleanupSel = createSelection(block, "hello world");

    // Trigger selectionchange to register the active editor
    document.dispatchEvent(new Event("selectionchange"));

    // Dispatch toggle-format
    env.host.dispatchEvent(
      new CustomEvent("toggle-format", { detail: { format: "bold" } }),
    );

    expect(Commands.toggleFormat).toHaveBeenCalledWith(
      block._editor,
      "bold",
    );

    cleanupSel();
    document.body.removeChild(block);
  });

  it("toggle-format without active editor is a no-op", () => {
    // No ora-block active
    env.host.dispatchEvent(
      new CustomEvent("toggle-format", { detail: { format: "bold" } }),
    );

    expect(Commands.toggleFormat).not.toHaveBeenCalled();
  });

  // ── Test 2: request-link reveals the link editor ─────────────────

  it("request-link sets visible attribute on link-editor", () => {
    expect(env.linkEditor.hasAttribute("visible")).toBe(false);

    env.host.dispatchEvent(new CustomEvent("request-link"));

    expect(env.linkEditor.hasAttribute("visible")).toBe(true);
  });

  // ── Test 3: apply-link dispatches TOGGLE_LINK_COMMAND ────────────

  it("apply-link dispatches setLink with url", () => {
    const block = createOraBlock();
    document.body.appendChild(block);
    setActiveElementInside(block);

    const cleanupSel = createSelection(block, "click me");

    // Trigger selectionchange
    document.dispatchEvent(new Event("selectionchange"));

    // Dispatch apply-link
    env.host.dispatchEvent(
      new CustomEvent("apply-link", { detail: { url: "https://example.com" } }),
    );

    expect(Commands.setLink).toHaveBeenCalledWith(
      block._editor,
      "https://example.com",
    );

    // Link editor should be hidden after apply
    expect(env.linkEditor.hasAttribute("visible")).toBe(false);

    cleanupSel();
    document.body.removeChild(block);
  });

  it("apply-link with empty url passes null to setLink", () => {
    const block = createOraBlock();
    document.body.appendChild(block);
    setActiveElementInside(block);

    const cleanupSel = createSelection(block, "link text");

    document.dispatchEvent(new Event("selectionchange"));

    env.host.dispatchEvent(
      new CustomEvent("apply-link", { detail: { url: "" } }),
    );

    expect(Commands.setLink).toHaveBeenCalledWith(block._editor, "");

    cleanupSel();
    document.body.removeChild(block);
  });

  // ── Test 4: cancel-link hides the link editor ────────────────────

  it("cancel-link hides link editor", () => {
    env.linkEditor.setAttribute("visible", "");
    expect(env.linkEditor.hasAttribute("visible")).toBe(true);

    env.host.dispatchEvent(new CustomEvent("cancel-link"));

    expect(env.linkEditor.hasAttribute("visible")).toBe(false);
  });

  // ── Test 5: empty / collapsed selection hides toolbar ────────────

  it("collapsed selection hides toolbar", () => {
    const block = createOraBlock();
    document.body.appendChild(block);
    setActiveElementInside(block);

    // Create a collapsed selection (caret, not range selection)
    const textNode = document.createTextNode("text");
    block.appendChild(textNode);
    const range = document.createRange();
    range.setStart(textNode, 0);
    range.collapse(true);
    const sel = window.getSelection();
    sel.removeAllRanges();
    sel.addRange(range);

    document.dispatchEvent(new Event("selectionchange"));

    expect(env.toolbar.hasAttribute("visible")).toBe(false);

    sel.removeAllRanges();
    block.removeChild(textNode);
    document.body.removeChild(block);
  });

  // ── Test 6: destroyed cleans up listeners ────────────────────────

  it("destroyed removes event listeners", () => {
    // Spy on removeEventListener
    const spyRemove = vi.spyOn(document, "removeEventListener");
    const hostSpyRemove = vi.spyOn(env.host, "removeEventListener");

    FormatToolbar.destroyed.call(env.ctx);

    expect(spyRemove).toHaveBeenCalledWith(
      "selectionchange",
      expect.any(Function),
    );
    expect(hostSpyRemove).toHaveBeenCalledWith(
      "toggle-format",
      expect.any(Function),
    );
    expect(hostSpyRemove).toHaveBeenCalledWith(
      "request-link",
      expect.any(Function),
    );
    expect(hostSpyRemove).toHaveBeenCalledWith(
      "apply-link",
      expect.any(Function),
    );
    expect(hostSpyRemove).toHaveBeenCalledWith(
      "cancel-link",
      expect.any(Function),
    );
  });
});
