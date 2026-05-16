/**
 * @vitest-environment jsdom
 *
 * Integration test for BUG-030: ArrowUp regression.
 *
 * The bug is in OraBlock.focusEnd() ordering:
 *   moveCaretToEnd(this._editor)  BEFORE  this._editor.focus()
 *
 * In a real browser, Lexical's focus() → $commitPendingUpdates →
 * updateDOMSelection updates the DOM selection, which fires
 * selectionchange → onSelectionChange reads DOM selection and
 * overwrites the internal selection (stale DOM selection from the
 * previous block). The fix reverses the order: focus() first, then
 * moveCaretToEnd(), so the programmatic selection change comes AFTER
 * any DOM-sourced restoration.
 *
 * NB: jsdom does not fire selectionchange from editor.focus(), so
 * the DOM-override path is absent. This test validates the structural
 * behavior (handler wiring, focusEnd selection position) and serves
 * as a regression harness when run in a real browser environment.
 */
import { describe, it, expect, vi, afterEach } from "vitest";
import { $createRangeSelection, $getRoot, $getSelection, $isRangeSelection, $setSelection } from "lexical";
import "../ora-block.js";
import { createBlockEditor } from "../../lexical/registry.js";
import { parseInitial } from "../../lexical/state.js";

const flush = () => new Promise((r) => setTimeout(r, 0));

function createBlock(id, text) {
  const json = JSON.stringify({
    root: {
      type: "root",
      children: [
        {
          type: "paragraph",
          children: [
            {
              type: "text",
              text,
              format: 0,
              detail: 0,
              mode: "normal",
              style: "",
              version: 1,
            },
          ],
          direction: "ltr",
          format: "",
          indent: 0,
          version: 1,
        },
      ],
      direction: "ltr",
      format: "",
      indent: 0,
      version: 1,
    },
  });

  const el = document.createElement("ora-block");
  el.setAttribute("block-id", id);
  el.setAttribute("initial-content", json);
  el.innerHTML =
    '<div data-editor contenteditable="true" role="textbox" aria-multiline="true" class="ora-block">' +
    text +
    "</div>";
  return el;
}

describe("ora-block arrow-up integration", () => {
  afterEach(() => {
    document.body.innerHTML = "";
  });

  it("focusEnd selection is at root end after arrow-up navigation", async () => {
    // ── Arrange ──────────────────────────────────────────────────────
    const alpha = createBlock("alpha", "alpha");
    const beta = createBlock("beta", "beta");
    document.body.append(alpha, beta);

    await alpha.updateComplete;
    await beta.updateComplete;

    // Ensure both blocks have a Lexical editor.
    for (const el of [alpha, beta]) {
      if (!el._editor) {
        const root = el.querySelector("[data-editor]");
        if (root) {
          el._editor = createBlockEditor(root, true);
          const state = parseInitial(
            el._editor,
            el.getAttribute("initial-content"),
          );
          if (state) el._editor.setEditorState(state);
        }
      }
    }

    expect(alpha._editor).toBeTruthy();
    expect(beta._editor).toBeTruthy();

    // Wire the mock server handler: when beta fires ora-block-arrow-up,
    // focus end of the alpha block.
    const handler = vi.fn(() => {
      const a = document.querySelector('[block-id="alpha"]');
      if (a && a.focusEnd) a.focusEnd();
    });
    beta.addEventListener("ora-block-arrow-up", handler);

    // ── Act ──────────────────────────────────────────────────────────
    // Simulate ArrowUp by dispatching the custom event the keydown
    // handler would fire (bypassing jsdom's flaky _isAtStart selection).
    beta.dispatchEvent(
      new CustomEvent("ora-block-arrow-up", { bubbles: true }),
    );

    // Let deferred editor updates (from moveCaretToEnd + editor.focus)
    // commit before asserting.
    await flush();

    // ── Assert ───────────────────────────────────────────────────────
    // Selection is at root end in alpha's editor.
    // In a real browser this assertion would catch the bug when
    // focus() restoreSelectionFromDOM overwrites the end-of-root
    // selection set by moveCaretToEnd.
    const ed = alpha._editor;
    let atEnd = false;
    ed.getEditorState().read(() => {
      const sel = $getSelection();
      if ($isRangeSelection(sel)) {
        const node = sel.anchor.getNode();
        atEnd = sel.anchor.offset === node.getTextContentSize();
      }
    });
    expect(atEnd).toBe(true);

    // The arrow-up event was dispatched and handled.
    expect(handler).toHaveBeenCalledOnce();
  });
  it("fires ora-block-arrow-up when ArrowUp pressed at offset 0", async () => {
    // ── Arrange ──────────────────────────────────────────────────────
    const el = createBlock("gamma", "hello");
    document.body.append(el);
    await el.updateComplete;

    if (!el._editor) {
      const root = el.querySelector("[data-editor]");
      if (root) {
        el._editor = createBlockEditor(root, true);
        const state = parseInitial(el._editor, el.getAttribute("initial-content"));
        if (state) el._editor.setEditorState(state);
      }
    }

    expect(el._editor).toBeTruthy();

    // Place caret at offset 0 of the text node via Lexical API.
    el._editor.update(() => {
      const textNode = $getRoot().getFirstChild().getFirstChild();
      const selection = $createRangeSelection();
      selection.anchor.set(textNode.getKey(), 0, "text");
      selection.focus.set(textNode.getKey(), 0, "text");
      $setSelection(selection);
    });
    // Let the update commit.
    await flush();

    const arrowUpFired = vi.fn();
    el.addEventListener("ora-block-arrow-up", arrowUpFired);

    // ── Act ──────────────────────────────────────────────────────────
    const editorRoot = el.querySelector("[data-editor]");
    editorRoot.dispatchEvent(
      new KeyboardEvent("keydown", { key: "ArrowUp", bubbles: true }),
    );

    // ── Assert ───────────────────────────────────────────────────────
    expect(arrowUpFired).toHaveBeenCalledOnce();
  });
});
