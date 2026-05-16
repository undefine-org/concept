/**
 * Phoenix LiveView hook for handling "Ask about this" selection action.
 *
 * Listens for the 'ora-ask-selection' custom event dispatched by the
 * format toolbar and forwards it to the LiveView backend.
 */
export const AskSelection = {
  mounted() {
    this._handleAskSelection = (event) => {
      const { text, blockId, pageId } = event.detail;
      this.pushEvent("ask_selection", {
        text: text,
        block_id: blockId,
        page_id: pageId,
      });
    };
    this.el.addEventListener("ora-ask-selection", this._handleAskSelection);
  },

  destroyed() {
    this.el.removeEventListener("ora-ask-selection", this._handleAskSelection);
  },
};

export default AskSelection;
