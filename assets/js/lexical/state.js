/**
 * Parse a JSON string (or object) into a Lexical EditorState.
 *
 * @param {import("lexical").LexicalEditor} editor
 * @param {string|object} json
 * @returns {import("lexical").EditorState|null}
 */
export function parseInitial(editor, json) {
  try {
    const parsed = typeof json === "string" ? JSON.parse(json) : json;
    return editor.parseEditorState(parsed);
  } catch (e) {
    console.warn("Failed to parse initial Lexical state:", e);
    return null;
  }
}

/**
 * Serialize the current editor state to a plain JSON object.
 *
 * @param {import("lexical").LexicalEditor} editor
 * @returns {object}
 */
export function serialize(editor) {
  return editor.getEditorState().toJSON();
}
