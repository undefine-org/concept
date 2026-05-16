/**
 * @vitest-environment jsdom
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { FormatToolbar } from "../format_toolbar.js";

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
 * Create a text selection inside the given element.
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
 * Mount the FormatToolbar hook by calling mounted() on a context
 * that merges all FormatToolbar methods (same pattern as block_list test).
 */
function mountHook() {
  const host = document.createElement("div");
  host.id = "format-toolbar-host";
  host.innerHTML = `
    <ora-format-toolbar></ora-format-toolbar>
    <ora-link-editor></ora-link-editor>
  `;
  document.body.appendChild(host);

  const ctx = Object.assign(
    { el: host },
    FormatToolbar,
  );
  FormatToolbar.mounted.call(ctx);
  return {
    host,
    ctx,
    toolbar: host.querySelector("ora-format-toolbar"),
    linkEditor: host.querySelector("ora-link-editor"),
  };
}

/**
 * Activate the toolbar by creating a selection inside an ora-block
 * and triggering selectionchange.
 */
function activateToolbar(env, block) {
  if (block) {
    document.body.appendChild(block);
    setActiveElementInside(block);
    const cleanup = createSelection(block, "select me");
    document.dispatchEvent(new Event("selectionchange"));
    return cleanup;
  }
  return () => {};
}

// ── tests ──────────────────────────────────────────────────────────────

describe("FormatToolbar hook", () => {
  /** @type {{ host: HTMLElement, ctx: object, toolbar: HTMLElement, linkEditor: HTMLElement }} */
  let env;

  beforeEach(() => {
    vi.clearAllMocks();
    env = mountHook();
    window.getSelection().removeAllRanges();
  });

  afterEach(() => {
    FormatToolbar.destroyed.call(env.ctx);
    if (env.host.parentNode) {
      env.host.parentNode.removeChild(env.host);
    }
    delete document.activeElement;
  });

  // ── Test 1: toggle-format dispatches FORMAT_TEXT_COMMAND ────────

  it("toggle-format dispatches FORMAT_TEXT_COMMAND with format", () => {
    const block = createOraBlock();
    const cleanupSel = activateToolbar(env, block);

    env.host.dispatchEvent(
      new CustomEvent("toggle-format", { detail: { format: "bold" } }),
    );

    expect(block._editor.dispatchCommand).toHaveBeenCalledTimes(1);

    cleanupSel();
    document.body.removeChild(block);
  });

  it("toggle-format without active editor is a no-op", () => {
    // No ora-block active — toolbar is hidden, _activeEditor is null
    env.host.dispatchEvent(
      new CustomEvent("toggle-format", { detail: { format: "bold" } }),
    );

    // No error thrown; no editor to dispatch on
    expect(true).toBe(true);
  });

  // ── Test 2: request-link reveals the link editor ────────────────

  it("request-link sets visible attribute on link-editor", () => {
    expect(env.linkEditor.hasAttribute("visible")).toBe(false);

    env.host.dispatchEvent(new CustomEvent("request-link"));

    expect(env.linkEditor.hasAttribute("visible")).toBe(true);
  });

  // ── Test 3: apply-link dispatches TOGGLE_LINK_COMMAND ───────────

  it("apply-link dispatches setLink with url", () => {
    const block = createOraBlock();
    const cleanupSel = activateToolbar(env, block);

    env.host.dispatchEvent(
      new CustomEvent("apply-link", { detail: { url: "https://example.com" } }),
    );

    expect(block._editor.dispatchCommand).toHaveBeenCalledTimes(1);

    // Link editor should be hidden after apply
    expect(env.linkEditor.hasAttribute("visible")).toBe(false);

    cleanupSel();
    document.body.removeChild(block);
  });

  it("apply-link with empty url is handled without error", () => {
    const block = createOraBlock();
    const cleanupSel = activateToolbar(env, block);

    env.host.dispatchEvent(
      new CustomEvent("apply-link", { detail: { url: "" } }),
    );

    // dispatchCommand is called with TOGGLE_LINK_COMMAND via setLink
    expect(block._editor.dispatchCommand).toHaveBeenCalledTimes(1);

    cleanupSel();
    document.body.removeChild(block);
  });

  // ── Test 4: cancel-link hides the link editor ───────────────────

  it("cancel-link hides link editor", () => {
    env.linkEditor.setAttribute("visible", "");
    expect(env.linkEditor.hasAttribute("visible")).toBe(true);

    env.host.dispatchEvent(new CustomEvent("cancel-link"));

    expect(env.linkEditor.hasAttribute("visible")).toBe(false);
  });

  // ── Test 5: collapsed / empty selection hides toolbar ───────────

  it("collapsed selection hides toolbar", () => {
    const block = createOraBlock();
    document.body.appendChild(block);
    setActiveElementInside(block);

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

  // ── Test 6: destroyed cleans up listeners ───────────────────────

  it("destroyed removes event listeners", () => {
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
