/**
 * @vitest-environment jsdom
 *
 * Direct unit tests for toggleFormat and setLink on a real Lexical editor,
 * asserting post-conditions on editor state — not just spy-on-callee.
 */
import { describe, it, expect, beforeAll } from "vitest";
import {
  createEditor,
  $getRoot,
  $createParagraphNode,
  $createTextNode,
  ParagraphNode,
  TextNode,
  $getSelection,
  $isRangeSelection,
  $createRangeSelection,
  $setSelection,
  FORMAT_TEXT_COMMAND,
  COMMAND_PRIORITY_NORMAL,
} from "lexical";
import { registerRichText } from "@lexical/rich-text";
import { LinkNode, TOGGLE_LINK_COMMAND, $toggleLink, $isLinkNode } from "@lexical/link";
import { oraTheme } from "../theme.js";
import { toggleFormat, setLink } from "../commands.js";
import { nodes, createBlockEditor } from "../registry.js";

const BASE_NODES = [ParagraphNode, TextNode];
const LINK_NODES = [ParagraphNode, TextNode, LinkNode];

function createTestEditor(nodes = BASE_NODES) {
  const root = document.createElement("div");
  root.setAttribute("contenteditable", "true");
  document.body.appendChild(root);

  const editor = createEditor({
    namespace: "test",
    nodes,
    theme: oraTheme,
    onError: (e) => console.error("Lexical:", e),
  });

  editor.setRootElement(root);
  return { editor, root };
}

function insertParagraphWithText(editor, text) {
  editor.update(() => {
    const root = $getRoot();
    const p = $createParagraphNode();
    const t = $createTextNode(text);
    p.append(t);
    root.append(p);
    // Select the entire text
    t.select(0, text.length);
  });
}

describe("toggleFormat", () => {
  it("sets bold format bit (1) on selected text when toggling bold", () => {
    const { editor } = createTestEditor();
    const unregister = registerRichText(editor);

    insertParagraphWithText(editor, "hello");

    // Dispatch toggleFormat — this dispatches FORMAT_TEXT_COMMAND which
    // registerRichText handles via its own editor.update().
    toggleFormat(editor, "bold");

    // Use editor.update() to flush any pending microtask-ed updates
    // before reading state. update() queues and processes all pending
    // updates in the same microtask batch.
    let formatBits = 0;
    editor.update(() => {
      const root = $getRoot();
      const p = root.getFirstChild();
      expect(p).not.toBeNull();
      const textNode = p.getFirstChild();
      expect(textNode).not.toBeNull();
      formatBits = textNode.getFormat();
    });

    // Bold bit is format & 1
    expect(formatBits & 1).toBe(1);

    unregister();
  });
});

describe("setLink", () => {
  it("wraps selected text in a LinkNode and unwraps on null", () => {
    const { editor } = createTestEditor(LINK_NODES);
    const unregister = registerRichText(editor);

    // Register TOGGLE_LINK_COMMAND handler (same production path used by setLink)
    editor.registerCommand(
      TOGGLE_LINK_COMMAND,
      (payload) => {
        editor.update(() => {
          $toggleLink(payload);
        });
        return true;
      },
      COMMAND_PRIORITY_NORMAL,
    );

    insertParagraphWithText(editor, "click me");

    // Apply link — dispatches TOGGLE_LINK_COMMAND, handler calls
    // editor.update(() => $toggleLink(url))
    setLink(editor, "https://x");

    // Read state inside editor.update() to flush all pending updates
    let hasLink = false;
    let linkUrl = "";
    editor.update(() => {
      const root = $getRoot();
      const p = root.getFirstChild();
      expect(p).not.toBeNull();
      expect(p.getType()).toBe("paragraph");

      const firstChild = p.getFirstChild();
      expect(firstChild).not.toBeNull();
      hasLink = firstChild.getType() === "link";
      linkUrl = firstChild.__url || "";
    });

    expect(hasLink).toBe(true);
    expect(linkUrl).toBe("https://x");

    // Now remove the link — select within the link and call setLink(null)
    editor.update(() => {
      const root = $getRoot();
      const p = root.getFirstChild();
      const linkNode = p.getFirstChild();
      // Select inside the link
      linkNode.select(0, 1);
    });

    setLink(editor, null);

    // Assert LinkNode is gone
    let hasLinkAfter = true;
    editor.update(() => {
      const root = $getRoot();
      const p = root.getFirstChild();
      const firstChild = p.getFirstChild();
      expect(firstChild).not.toBeNull();
      hasLinkAfter = firstChild.getType() === "link";
    });

    expect(hasLinkAfter).toBe(false);

    unregister();
  });
});


describe("setLink via production registry", () => {
  it("wraps selected text in a LinkNode using production config", () => {
    // Use the SAME config as production (import from registry.js)
    const root = document.createElement("div");
    root.setAttribute("contenteditable", "true");
    document.body.appendChild(root);

    const editor = createBlockEditor(root);

    insertParagraphWithText(editor, "hello");

    // Production path: setLink dispatches TOGGLE_LINK_COMMAND.
    // At this stage registry.js does NOT include LinkNode in `nodes`
    // and does NOT register a TOGGLE_LINK_COMMAND handler, so this
    // should be a no-op and the assertion below will fail.
    setLink(editor, "https://x");

    // Read editor state — use editor.update() to flush pending microtasks
    let hasLink = false;
    let linkUrl = "";
    editor.update(() => {
      const root = $getRoot();
      const p = root.getFirstChild();
      expect(p).not.toBeNull();
      expect(p.getType()).toBe("paragraph");

      const firstChild = p.getFirstChild();
      expect(firstChild).not.toBeNull();
      hasLink = firstChild.getType() === "link";
      linkUrl = firstChild.__url || "";
    });

    expect(hasLink).toBe(true);
    expect(linkUrl).toBe("https://x");
  });
});

