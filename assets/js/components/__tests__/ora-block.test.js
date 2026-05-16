/**
 * @vitest-environment jsdom
 */
import { describe, it, expect, beforeEach } from "vitest";
import {
  createEditor,
  $getRoot,
  $createParagraphNode,
  $createTextNode,
  $createRangeSelection,
  $setSelection,
  ParagraphNode,
  TextNode,
} from "lexical";
import {
  moveCaretToStart,
  moveCaretToEnd,
  toggleFormat,
  applyLink,
} from "../../lexical/commands.js";
import { oraTheme } from "../../lexical/theme.js";
import { OraBlock } from "../ora-block.js";

const EDITOR_NODES = [ParagraphNode, TextNode];

function createTestEditor() {
  const root = document.createElement("div");
  root.setAttribute("contenteditable", "true");
  document.body.appendChild(root);

  const editor = createEditor({
    namespace: "test",
    nodes: EDITOR_NODES,
    theme: oraTheme,
    onError: (e) => console.error("Lexical:", e),
  });

  editor.setRootElement(root);
  return { editor };
}

function insertTwoParagraphs(editor) {
  editor.update(() => {
    const root = $getRoot();
    const p1 = $createParagraphNode();
    p1.append($createTextNode("First paragraph"));
    const p2 = $createParagraphNode();
    p2.append($createTextNode("Second paragraph"));
    root.append(p1, p2);
  });
}

describe("moveCaretToStart", () => {
  let editor;

  beforeEach(() => {
    const setup = createTestEditor();
    editor = setup.editor;
  });

  it("does not throw on non-empty root", () => {
    insertTwoParagraphs(editor);
    expect(() => moveCaretToStart(editor)).not.toThrow();
  });

  it("does not throw on empty root", () => {
    expect(() => moveCaretToStart(editor)).not.toThrow();
  });

  it("can be called twice in sequence without throwing", () => {
    insertTwoParagraphs(editor);
    expect(() => {
      moveCaretToStart(editor);
      moveCaretToStart(editor);
    }).not.toThrow();
  });

  it("empty root still readable after call", () => {
    moveCaretToStart(editor);
    let text = "";
    editor.getEditorState().read(() => {
      text = $getRoot().getTextContent();
    });
    expect(text).toBe("");
  });

  it("fallback root.select() on empty executes without crashing", () => {
    moveCaretToStart(editor);
    expect(() => {
      editor.getEditorState().read(() => {
        $getRoot().getTextContent();
      });
    }).not.toThrow();
  });
});

describe("moveCaretToEnd", () => {
  let editor;

  beforeEach(() => {
    const setup = createTestEditor();
    editor = setup.editor;
  });

  it("does not throw on non-empty root", () => {
    insertTwoParagraphs(editor);
    expect(() => moveCaretToEnd(editor)).not.toThrow();
  });

  it("does not throw on empty root", () => {
    expect(() => moveCaretToEnd(editor)).not.toThrow();
  });

  it("can be called twice in sequence without throwing", () => {
    insertTwoParagraphs(editor);
    expect(() => {
      moveCaretToEnd(editor);
      moveCaretToEnd(editor);
    }).not.toThrow();
  });

  it("empty root still readable after call", () => {
    moveCaretToEnd(editor);
    let text = "";
    editor.getEditorState().read(() => {
      text = $getRoot().getTextContent();
    });
    expect(text).toBe("");
  });

  it("fallback root.select() on empty executes without crashing", () => {
    moveCaretToEnd(editor);
    expect(() => {
      editor.getEditorState().read(() => {
        $getRoot().getTextContent();
      });
    }).not.toThrow();
  });
});

describe("helpers are exported", () => {
  it("exports toggleFormat and applyLink (unchanged)", () => {
    expect(typeof toggleFormat).toBe("function");
    expect(typeof applyLink).toBe("function");
  });

  it("exports moveCaretToStart and moveCaretToEnd", () => {
    expect(typeof moveCaretToStart).toBe("function");
    expect(typeof moveCaretToEnd).toBe("function");
  });
});

describe("_isAtStart / _isAtEnd", () => {
  let editor;
  let block;

  beforeEach(() => {
    const setup = createTestEditor();
    editor = setup.editor;
    block = new OraBlock();
    block._editor = editor;
  });

  function buildSingleTextNode(text) {
    editor.update(() => {
      const root = $getRoot();
      root.clear();
      const p = $createParagraphNode();
      const t = $createTextNode(text);
      p.append(t);
      root.append(p);
    }, { discrete: true });
  }

  function buildTwoTextNodes(t1, t2) {
    editor.update(() => {
      const root = $getRoot();
      root.clear();
      const p = $createParagraphNode();
      const a = $createTextNode(t1);
      const b = $createTextNode(t2);
      b.setFormat("bold"); // prevent auto-merge with same-format neighbour
      p.append(a, b);
      root.append(p);
    }, { discrete: true });
  }

  it("_isAtStart is true at offset 0", () => {
    buildSingleTextNode("hello");
    editor.update(() => {
      $getRoot().getFirstChild().getFirstChild().select(0, 0);
    }, { discrete: true });
    expect(block._isAtStart()).toBe(true);
    expect(block._isAtEnd()).toBe(false);
  });

  it("_isAtEnd is true at last offset", () => {
    buildSingleTextNode("hello");
    editor.update(() => {
      $getRoot().getFirstChild().getFirstChild().select(5, 5);
    }, { discrete: true });
    expect(block._isAtStart()).toBe(false);
    expect(block._isAtEnd()).toBe(true);
  });

  it("neither is true in the middle of a text node", () => {
    buildSingleTextNode("hello");
    editor.update(() => {
      $getRoot().getFirstChild().getFirstChild().select(2, 2);
    }, { discrete: true });
    expect(block._isAtStart()).toBe(false);
    expect(block._isAtEnd()).toBe(false);
  });

  it("works across multiple text nodes", () => {
    buildTwoTextNodes("hello", "world");
    // caret at start of first text node
    editor.update(() => {
      const p = $getRoot().getFirstChild();
      p.getFirstChild().select(0, 0);
    }, { discrete: true });
    expect(block._isAtStart()).toBe(true);
    expect(block._isAtEnd()).toBe(false);

    // caret at end of second text node
    editor.update(() => {
      const p = $getRoot().getFirstChild();
      p.getLastChild().select(5, 5);
    }, { discrete: true });
    expect(block._isAtStart()).toBe(false);
    expect(block._isAtEnd()).toBe(true);
  });

  it("_isAtEnd reflects the current text node, not the block", () => {
    buildTwoTextNodes("hello", "world");
    editor.update(() => {
      $getRoot().getFirstChild().getFirstChild().select(5, 5);
    }, { discrete: true });
    expect(block._isAtStart()).toBe(false);
    // Spec: end of *current* text node, even when more text follows.
    expect(block._isAtEnd()).toBe(true);
  });
});
