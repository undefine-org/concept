import { FORMAT_TEXT_COMMAND, $getRoot } from "lexical";
import { $toggleLink, TOGGLE_LINK_COMMAND } from "@lexical/link";

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

/**
 * Apply or remove a link via the TOGGLE_LINK_COMMAND.
 *
 * @param {import("lexical").LexicalEditor} editor
 * @param {string} url – empty string removes the link
 */
export function setLink(editor, url) {
  editor.dispatchCommand(TOGGLE_LINK_COMMAND, url || null);
}

/**
 * Move the editor caret to the start of the root (first child, offset 0).
 * Falls back to root.select() for empty roots.
 *
 * @param {import("lexical").LexicalEditor} editor
 */
export function moveCaretToStart(editor) {
  editor.update(() => {
    const r = $getRoot();
    r.getFirstChild() ? r.selectStart() : r.select();
  });
}

/**
 * Move the editor caret to the end of the root (last child, end offset).
 * Falls back to root.select() for empty roots.
 *
 * @param {import("lexical").LexicalEditor} editor
 */
export function moveCaretToEnd(editor) {
  editor.update(() => {
    const r = $getRoot();
    r.getLastChild() ? r.selectEnd() : r.select();
  });
}
