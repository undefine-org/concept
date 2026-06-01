import BlockList from "./block_list.js";
import FormatToolbar from "./format_toolbar.js";
import SlashMenu from "./slash_menu.js";
import { BlockEditor } from "./block_editor.js";
import AskSelection from "./ask_selection.js";
import OraBlock from "./ora_block.js";
import { LiveCitationRail } from "./live_citation_rail.js";

import ContentEditable from "./content_editable.js";
import EmojiPicker from "./emoji_picker.js";
import GlobalKeys from "./global_keys.js";
import TaskBoard from "./task_board.js";
import FocusTrap from "./focus_trap.js";
import ScrollToBottom from "./scroll_to_bottom.js";

const Hooks = {
  BlockList,
  FormatToolbar,
  SlashMenu,
  BlockEditor,
  AskSelection,
  OraBlock,
  LiveCitationRail,

  ContentEditable,
  EmojiPicker,
  GlobalKeys,
  TaskBoard,
  FocusTrap,
  ScrollToBottom,
};

export default Hooks;
