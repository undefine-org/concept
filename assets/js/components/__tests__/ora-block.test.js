/**
 * @vitest-environment jsdom
 */
import { describe, it, expect, beforeEach } from "vitest";
import { createEditor, $getRoot, $createParagraphNode, $createTextNode, ParagraphNode, TextNode } from "lexical";
import {
  moveCaretToStart,
  moveCaretToEnd,
  toggleFormat,
  applyLink,
} from "../../lexical/commands.js";
import { oraTheme } from "../../lexical/theme.js";

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
