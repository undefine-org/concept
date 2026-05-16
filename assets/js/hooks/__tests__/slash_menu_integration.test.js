/**
 * @vitest-environment jsdom
 *
 * BUG-033 Phase A+B integration tests.
 *
 * These use a real Lexical editor + real ora-block (no mock of
 * the Lexical module) so they exercise the actual Lexical pipeline
 * (registerTextContentListener, editor.update, $getRoot(), etc.).
 */
import { describe, it, expect, vi, afterEach } from "vitest";
import { $getRoot, $getSelection } from "lexical";
import { SlashMenu } from "../slash_menu.js";
import "../../components/ora-block.js";
import "../../components/ora-slash-menu.js";
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
  el.innerHTML = '<div data-editor contenteditable="true"></div>';
  return el;
}

async function ensureEditor(el) {
  await el.updateComplete;
  if (!el._editor) {
    const root = el.querySelector("[data-editor]");
    el._editor = createBlockEditor(root, true);
    const state = parseInitial(el._editor, el.getAttribute("initial-content"));
    if (state) el._editor.setEditorState(state);
  }
  return el._editor;
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

describe("SlashMenu integration with Lexical pipeline", () => {
  afterEach(() => {
    document.body.innerHTML = "";
  });

  // ── Defect 3: input detection via Lexical pipeline (document-level misses) ──

  it("opens menu when '/' is inserted via editor.update()", async () => {
    const block = createBlock("b1", "");
    document.body.appendChild(block);
    const editor = await ensureEditor(block);

    const env = mountHook();

    // Focus the block so the hook registers the text-content listener.
    block.dispatchEvent(
      new CustomEvent("ora-block-focus", {
        detail: { blockId: "b1" },
        bubbles: true,
      })
    );

    // Simulate user typing '/' via Lexical's insertText (no DOM input event).
    editor.update(() => {
      const root = $getRoot();
      let para = root.getFirstChild();
      if (!para) {
        const { $createParagraphNode } = require("lexical");
        para = $createParagraphNode();
        root.append(para);
      }
      para.selectEnd();
      const sel = $getSelection();
      sel.insertText("/");
    });

    await flush();

    expect(env.menu.hasAttribute("visible")).toBe(true);
    expect(env.ctx._open).toBe(true);
  });

  // ── Defect 2: trigger deletion is ineffective in real browser ──────────

  it("removes '/' and filter from source editor on select", async () => {
    const block = createBlock("b1", "foo");
    document.body.appendChild(block);
    const editor = await ensureEditor(block);

    const env = mountHook();
    block.dispatchEvent(
      new CustomEvent("ora-block-focus", {
        detail: { blockId: "b1" },
        bubbles: true,
      })
    );

    // Insert "/h1" via Lexical
    editor.update(() => {
      const para = $getRoot().getFirstChild();
      para.selectEnd();
      $getSelection().insertText("/h1");
    });
    await flush();

    // Simulate the hook state as if trigger was detected (pre-slash length = 3)
    env.ctx._activeEditor = editor;
    env.ctx._activeBlockId = "b1";
    env.ctx._triggerPreLength = 3;
    env.ctx._open = true;
    env.menu.setAttribute("visible", "");

    // Dispatch select
    env.host.dispatchEvent(
      new CustomEvent("select", {
        detail: { type: "heading_1" },
        bubbles: true,
        composed: true,
      })
    );

    await flush();

    let text;
    editor.getEditorState().read(() => {
      text = $getRoot().getTextContent();
    });

    expect(text).toBe("foo");
    expect(env.pushEvent).toHaveBeenCalledWith("insert_block_below", {
      block_id: "b1",
      type: "heading_1",
    });
  });
});
