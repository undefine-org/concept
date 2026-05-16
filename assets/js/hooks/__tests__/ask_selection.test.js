/**
 * @vitest-environment jsdom
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { AskSelection } from "../ask_selection.js";

describe("AskSelection hook", () => {
  let el;
  let ctx;

  beforeEach(() => {
    el = document.createElement("div");
    el.id = "test-container";
    document.body.appendChild(el);

    ctx = {
      el: el,
      pushEvent: vi.fn(),
    };

    AskSelection.mounted.call(ctx);
  });

  afterEach(() => {
    if (ctx && AskSelection.destroyed) {
      AskSelection.destroyed.call(ctx);
    }
    if (el.parentNode) {
      el.parentNode.removeChild(el);
    }
  });

  it("ora-ask-selection event triggers pushEvent", () => {
    const event = new CustomEvent("ora-ask-selection", {
      detail: {
        text: "test excerpt",
        blockId: "block-123",
        pageId: "page-456",
      },
      bubbles: true,
    });

    el.dispatchEvent(event);

    expect(ctx.pushEvent).toHaveBeenCalledTimes(1);
    expect(ctx.pushEvent).toHaveBeenCalledWith("ask_selection", {
      text: "test excerpt",
      block_id: "block-123",
      page_id: "page-456",
    });
  });

  it("ora-ask-selection with undefined blockId/pageId still pushes event", () => {
    const event = new CustomEvent("ora-ask-selection", {
      detail: {
        text: "test excerpt",
        blockId: undefined,
        pageId: undefined,
      },
      bubbles: true,
    });

    el.dispatchEvent(event);

    expect(ctx.pushEvent).toHaveBeenCalledTimes(1);
    expect(ctx.pushEvent).toHaveBeenCalledWith("ask_selection", {
      text: "test excerpt",
      block_id: undefined,
      page_id: undefined,
    });
  });

  it("destroyed removes event listener", () => {
    const spyRemove = vi.spyOn(el, "removeEventListener");

    AskSelection.destroyed.call(ctx);

    expect(spyRemove).toHaveBeenCalledWith(
      "ora-ask-selection",
      expect.any(Function)
    );
  });
});
