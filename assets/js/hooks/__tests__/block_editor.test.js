/**
 * @vitest-environment jsdom
 *
 * BUG-035 Phase A: server's focus_block_caret push races the new block's
 * BlockEditor hook mount. If the event arrives before the hook attaches,
 * the focus signal is lost. The fix introduces a module-level pending-focus
 * map; any hook receiving a focus_block_caret event for a block-id that
 * isn't its own stashes the payload, and any newly-mounted hook consumes
 * a pending entry for its own block-id.
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { BlockEditor } from "../block_editor.js";

function createOraBlockStub(id) {
  const el = document.createElement("ora-block");
  el.setAttribute("block-id", id);
  el.focusStart = vi.fn();
  el.focusEnd = vi.fn();
  el.applyRemote = vi.fn();
  el.setReadOnly = vi.fn();
  document.body.appendChild(el);
  return el;
}

function createCtx(el) {
  const handlers = {};
  const ctx = {
    el,
    pushEvent: vi.fn(),
    handleEvent: vi.fn((name, cb) => {
      handlers[name] = cb;
    }),
    __handlers: handlers,
  };
  Object.assign(ctx, BlockEditor);
  return ctx;
}

describe("BlockEditor pending-focus queue (BUG-035)", () => {
  afterEach(() => {
    document.body.innerHTML = "";
  });

  it("stashes focus_block_caret for a foreign block-id and consumes on mount", () => {
    // ── Arrange ──────────────────────────────────────────────────────
    // Mount a hook on alpha. Its handleEvent registration captures the
    // focus_block_caret handler so we can invoke it manually with a
    // foreign block-id ("beta") that doesn't have a hook yet.
    const alphaEl = createOraBlockStub("alpha");
    const alphaCtx = createCtx(alphaEl);
    alphaCtx.mounted();

    const focusCaretHandler = alphaCtx.__handlers["focus_block_caret"];
    expect(focusCaretHandler).toBeTypeOf("function");

    // Server pushes focus_block_caret for "beta" — but no hook is mounted
    // on a beta block yet. Alpha's hook receives the event (LiveView pushes
    // to every hook); since block_id !== "alpha" it must stash the payload.
    focusCaretHandler({ block_id: "beta", position: "start" });

    // alpha's focusStart must NOT have been called (it isn't beta).
    expect(alphaEl.focusStart).not.toHaveBeenCalled();

    // ── Act ──────────────────────────────────────────────────────────
    // Now beta block lands in the DOM and BlockEditor mounts on it. The
    // hook must check the pending-focus queue and apply the stashed
    // payload (position: "start" → focusStart).
    const betaEl = createOraBlockStub("beta");
    const betaCtx = createCtx(betaEl);
    betaCtx.mounted();

    // ── Assert ───────────────────────────────────────────────────────
    expect(betaEl.focusStart).toHaveBeenCalledOnce();
    expect(betaEl.focusEnd).not.toHaveBeenCalled();
  });

  it("consumes pending focus with position 'end' via focusEnd on mount", () => {
    const alphaEl = createOraBlockStub("alpha");
    const alphaCtx = createCtx(alphaEl);
    alphaCtx.mounted();

    alphaCtx.__handlers["focus_block_caret"]({
      block_id: "gamma",
      position: "end",
    });

    const gammaEl = createOraBlockStub("gamma");
    const gammaCtx = createCtx(gammaEl);
    gammaCtx.mounted();

    expect(gammaEl.focusEnd).toHaveBeenCalledOnce();
    expect(gammaEl.focusStart).not.toHaveBeenCalled();
  });

  it("pending focus is consumed once (later mount of same id sees nothing)", () => {
    const alphaEl = createOraBlockStub("alpha");
    const alphaCtx = createCtx(alphaEl);
    alphaCtx.mounted();

    alphaCtx.__handlers["focus_block_caret"]({
      block_id: "delta",
      position: "start",
    });

    const deltaEl = createOraBlockStub("delta");
    const deltaCtx = createCtx(deltaEl);
    deltaCtx.mounted();

    expect(deltaEl.focusStart).toHaveBeenCalledOnce();

    // Same block-id later (e.g. re-mount after LiveView patch) must not
    // re-fire focus — the pending entry was consumed.
    document.body.removeChild(deltaEl);
    const deltaEl2 = createOraBlockStub("delta");
    const deltaCtx2 = createCtx(deltaEl2);
    deltaCtx2.mounted();

    expect(deltaEl2.focusStart).not.toHaveBeenCalled();
  });
});
