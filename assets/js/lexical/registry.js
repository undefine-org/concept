import { createEditor, ParagraphNode, TextNode, LineBreakNode, COMMAND_PRIORITY_LOW } from "lexical";
import {
  HeadingNode,
  QuoteNode,
  registerRichText,
} from "@lexical/rich-text";
import { LinkNode, TOGGLE_LINK_COMMAND, $toggleLink } from "@lexical/link";
import { mergeRegister } from "@lexical/utils";
import { oraTheme } from "./theme.js";

export const nodes = [ParagraphNode, HeadingNode, QuoteNode, TextNode, LineBreakNode, LinkNode];

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
  // Also wire link toggle so TOGGLE_LINK_COMMAND actually mutates state.
  const unregister = mergeRegister(
    registerRichText(editor),
    editor.registerCommand(
      TOGGLE_LINK_COMMAND,
      (url) => {
        editor.update(() => {
          $toggleLink(url);
        });
        return true;
      },
      COMMAND_PRIORITY_LOW,
    ),
  );
  editor._oraUnregister = unregister;
  return editor;
}

export { ParagraphNode, HeadingNode, QuoteNode, TextNode, LineBreakNode, LinkNode, mergeRegister };
