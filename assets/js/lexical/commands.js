import { FORMAT_TEXT_COMMAND } from "lexical";
import { $toggleLink } from "@lexical/link";

/**
 * Toggle a text format on the current selection.
 *
 * @param {import("lexical").LexicalEditor} editor
 * @param {"bold"|"italic"|"underline"|"strikethrough"|"code"} format
 */
export function toggleFormat(editor, format) {
  editor.dispatchCommand(FORMAT_TEXT_COMMAND, format);
}

/**
 * Apply or remove a link on the current selection.
 *
 * @param {import("lexical").LexicalEditor} editor
 * @param {string} url – empty string removes the link
 */
export function applyLink(editor, url) {
  editor.update(() => {
    $toggleLink(url || null);
  });
}
