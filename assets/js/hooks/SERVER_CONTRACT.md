# Server Contract — Page Editor JS Hooks

This document lists every client → server event emitted by the hooks in this directory, along with payload schemas, so the `PageEditorLive` module can wire matching `handle_event/3` clauses.

---

## `BlockList` hook (`phx-hook="BlockList"` on the block list `<ul>`)

| Event | Payload | Description |
|---|---|---|
| `reorder_block` | `%{block_id: string, prev_id: string \| nil, next_id: string \| nil}` | Fired after a SortableJS drag ends. `prev_id` / `next_id` are the sibling block IDs (or `nil` if at the edge). |

---

## `BlockKeyboard` hook (`phx-hook="BlockKeyboard"` on `<ora-block>`)

| Event | Payload | Description |
|---|---|---|
| `nav_block` | `%{direction: "up" \| "down", block_id: string}` | Arrow-up / arrow-down inside a block. Server should move focus to the previous / next block. |
| `insert_paragraph_below` | `%{block_id: string}` | Enter pressed at the end of a block. Server should create a new empty paragraph below this block. |
| `delete_block_merge` | `%{block_id: string}` | Backspace pressed at the start of a block. Server should merge or delete this block. |

### Server → client events (pushed via `push_event/3`)

The server can push the following events to the `BlockKeyboard` hook:

| Event | Payload | Description |
|---|---|---|
| `focus_block_caret` | `%{block_id: string, position: "start" \| "end"}` | Requests the block with `block_id` to move its caret to `start` or `end`. The hook delegates to `element.focusStart()` / `element.focusEnd()` (provided by the `<ora-block>` custom element). |

---

## `GlobalKeys` hook (`phx-hook="GlobalKeys"` on `<body>`)

| Event | Payload | Description |
|---|---|---|
| `open_command_palette` | `%{}` | Cmd-K / Ctrl-K pressed. |
| `close_command_palette` | `%{}` | Escape pressed while the palette is open. |

### Server → client events

The server should push the following event so the hook knows whether to forward `Escape`:

| Event | Payload | Description |
|---|---|---|
| `palette_state` | `%{open: boolean}` | Set `open: true` when the palette is mounted / shown, and `open: false` when it is hidden / removed. |

---

## Custom element events (bubbling, no LiveView hook required)

The following custom events bubble up from the Lit components and should be handled by `phx-click` or `phx-window-click` bindings, or captured in a parent hook (`BlockEditor`):

| Source | Event | Detail | Description |
|---|---|---|---|
| `<ora-block-handle>` | `add-below` | `{}` | `+` button clicked — insert a block below. |
| `<ora-block-handle>` | `open-menu` | `{}` | `⋮⋮` button clicked — open block action menu. |
| `<ora-slash-menu>` | `select` | `%{type: string}` | User chose a block type from the slash menu. |
| `<ora-slash-menu>` | `close` | `{}` | User dismissed the slash menu (Esc). |
| `<ora-format-toolbar>` | `toggle-format` | `%{format: string}` | Bold / italic / underline / strikethrough / code toggled. |
| `<ora-format-toolbar>` | `request-link` | `{}` | Link button clicked — show link editor popover. |
| `<ora-link-editor>` | `apply-link` | `%{url: string}` | Link applied or removed (`url: ""`). |
