/**
 * Phoenix LiveView hook for AI answer blocks.
 *
 * Wires custom events from ora-ai-block Lit component to LiveView backend,
 * and forwards streaming tokens from LiveView back to the component.
 */
export const AIBlock = {
  mounted() {
    this._handleEvaluate = this._onEvaluate.bind(this);
    this._handleRefresh = this._onRefresh.bind(this);
    this._handleRetry = this._onRetry.bind(this);

    this.el.addEventListener("ora-ai-evaluate", this._handleEvaluate);
    this.el.addEventListener("ora-ai-refresh", this._handleRefresh);
    this.el.addEventListener("ora-ai-retry", this._handleRetry);
  },

  _onEvaluate(event) {
    const { blockId, prompt, scope, profile } = event.detail;
    
    this.pushEventTo(`#ai-${blockId}`, "evaluate_ai", {
      prompt: prompt,
      scope: scope,
      profile: profile,
    });
  },

  _onRefresh(event) {
    const { blockId, prompt, scope, profile } = event.detail;
    
    this.pushEventTo(`#ai-${blockId}`, "evaluate_ai", {
      prompt: prompt,
      scope: scope,
      profile: profile,
    });
  },

  _onRetry(event) {
    const { blockId, prompt, scope, profile } = event.detail;
    
    this.pushEventTo(`#ai-${blockId}`, "evaluate_ai", {
      prompt: prompt,
      scope: scope,
      profile: profile,
    });
  },

  destroyed() {
    this.el.removeEventListener("ora-ai-evaluate", this._handleEvaluate);
    this.el.removeEventListener("ora-ai-refresh", this._handleRefresh);
    this.el.removeEventListener("ora-ai-retry", this._handleRetry);
  },
};

export default AIBlock;
