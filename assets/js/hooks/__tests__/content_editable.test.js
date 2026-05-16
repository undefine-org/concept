/**
 * @vitest-environment jsdom
 *
 * BUG-023 Phase A: when a user clears a title by typing/selecting all and
 * leaving only whitespace, the contenteditable's `innerText` is a string
 * of spaces. The hook currently pushes that raw value, so the server-side
 * empty-title placeholder logic (`title == ""`) never triggers. The hook
 * must trim before pushing so a whitespace-only edit results in an empty
 * server value.
 */
import { describe, it, expect, vi, afterEach } from "vitest";
import ContentEditable from "../content_editable.js";

function createCtx(el) {
  const ctx = {
    el,
    pushEventTo: vi.fn(),
  };
  Object.assign(ctx, ContentEditable);
  return ctx;
}

describe("ContentEditable trims title on blur (BUG-023)", () => {
  afterEach(() => {
    document.body.innerHTML = "";
  });

  it("pushes empty value when innerText is whitespace-only", () => {
    const el = document.createElement("div");
    el.setAttribute("contenteditable", "true");
    document.body.appendChild(el);
    el.innerText = "   ";

    const ctx = createCtx(el);
    ctx.mounted();

    el.dispatchEvent(new Event("blur"));

    expect(ctx.pushEventTo).toHaveBeenCalledTimes(1);
    expect(ctx.pushEventTo).toHaveBeenCalledWith(el, "save_title", { value: "" });
  });

  it("strips surrounding whitespace but preserves inner spaces", () => {
    const el = document.createElement("div");
    el.setAttribute("contenteditable", "true");
    document.body.appendChild(el);
    el.innerText = "  hello world  ";

    const ctx = createCtx(el);
    ctx.mounted();

    el.dispatchEvent(new Event("blur"));

    expect(ctx.pushEventTo).toHaveBeenCalledWith(el, "save_title", {
      value: "hello world",
    });
  });
});
