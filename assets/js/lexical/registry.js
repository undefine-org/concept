import { createEditor, ParagraphNode, TextNode, LineBreakNode } from "lexical";
import {
  HeadingNode,
  QuoteNode,
  registerRichText,
} from "@lexical/rich-text";
import { mergeRegister } from "@lexical/utils";
import { oraTheme } from "./theme.js";

const nodes = [ParagraphNode, HeadingNode, QuoteNode, TextNode, LineBreakNode];

/**
 * Create a Lexical editor configured for an Ora block.
 * Registers rich-text input handlers so beforeinput / paste / drag work.
 */
export function createBlockEditor(rootElement, editable = true) {
  const editor = createEditor({
    namespace: "ora",
    nodes,
    theme: oraTheme,
    onError: (e) => console.error("Lexical:", e),
    editable,
  });

  editor.setRootElement(rootElement);
  rootElement.setAttribute("contenteditable", String(editable));
  rootElement.setAttribute("role", "textbox");
  rootElement.setAttribute("aria-multiline", "true");

  // Wire input/paste/IME/drag handlers — without this Lexical is read-only.
  const unregister = registerRichText(editor);
  editor._oraUnregister = unregister;
  return editor;
}

export { ParagraphNode, HeadingNode, QuoteNode, TextNode, LineBreakNode, mergeRegister };
