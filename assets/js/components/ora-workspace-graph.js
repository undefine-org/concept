import { forceSimulation, forceLink, forceManyBody, forceCenter } from "d3-force";
import { select } from "d3-selection";
import { zoom } from "d3-zoom";

/**
 * Plain custom element (no Lit) — light-DOM, manages its own SVG.
 * Lit's incremental render was silently no-op'ing in this codebase's
 * bundle; manual DOM management is simpler and bulletproof for a single
 * full-canvas D3 visualization.
 */
export class OraWorkspaceGraph extends HTMLElement {
  static get observedAttributes() {
    return ["data"];
  }

  constructor() {
    super();
    this._graphData = { nodes: [], edges: [], communities: [] };
    this._simulation = null;
  }

  connectedCallback() {
    if (!this._dom) this._ensureDom();
    this._parseAndDraw();
  }

  disconnectedCallback() {
    if (this._simulation) {
      this._simulation.stop();
      this._simulation = null;
    }
  }

  attributeChangedCallback(name, oldVal, newVal) {
    if (name === "data" && oldVal !== newVal) {
      if (!this._dom) this._ensureDom();
      this._parseAndDraw();
    }
  }

  _ensureDom() {
    while (this.firstChild) this.removeChild(this.firstChild);
    const wrap = document.createElement("div");
    wrap.className = "relative w-full h-full overflow-hidden";
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.setAttribute("class", "w-full h-full block");
    wrap.appendChild(svg);
    this.appendChild(wrap);
    this._emptyState = document.createElement("div");
    this._emptyState.className =
      "absolute inset-0 flex items-center justify-center text-notion-text-light pointer-events-none";
    this._emptyState.textContent = "";
    wrap.appendChild(this._emptyState);
    this._dom = true;
  }

  _parseAndDraw() {
    try {
      const parsed = JSON.parse(this.getAttribute("data") || "{}");
      this._graphData = {
        nodes: parsed.nodes || [],
        edges: parsed.edges || [],
        communities: parsed.communities || [],
      };
    } catch {
      this._graphData = { nodes: [], edges: [], communities: [] };
    }
    if (this._graphData.nodes.length === 0) {
      if (this._emptyState) this._emptyState.textContent = "Add pages to see the graph";
      return;
    }
    if (this._emptyState) this._emptyState.textContent = "";
    this._drawGraph();
  }

  _drawGraph() {
    const svgEl = this.querySelector("svg");
    if (!svgEl) return;

    if (this._simulation) {
      this._simulation.stop();
      this._simulation = null;
    }

    const width = svgEl.clientWidth || 800;
    const height = svgEl.clientHeight || 600;

    const svg = select(svgEl);
    svg.selectAll("*").remove();

    const g = svg.append("g");

    const zoomBehavior = zoom()
      .scaleExtent([0.1, 4])
      .on("zoom", (event) => {
        g.attr("transform", event.transform);
      });

    svg.call(zoomBehavior);

    const nodes = this._graphData.nodes.map((n) => ({ ...n }));
    const edges = this._graphData.edges.map((e) => ({ ...e }));

    const nodeById = new Map(nodes.map((n) => [n.id, n]));
    edges.forEach((e) => {
      e.source = nodeById.get(e.source) ?? e.source;
      e.target = nodeById.get(e.target) ?? e.target;
    });

    const degree = new Map();
    nodes.forEach((n) => degree.set(n.id, 0));
    edges.forEach((e) => {
      const s = typeof e.source === "object" ? e.source.id : e.source;
      const t = typeof e.target === "object" ? e.target.id : e.target;
      if (s) degree.set(s, (degree.get(s) || 0) + 1);
      if (t) degree.set(t, (degree.get(t) || 0) + 1);
    });

    const link = g
      .append("g")
      .attr("stroke", "#cbd5e1")
      .attr("stroke-opacity", 0.6)
      .selectAll("line")
      .data(edges)
      .join("line")
      .attr("stroke-width", 1.5);

    const nodeGroup = g
      .append("g")
      .selectAll("g.ora-node")
      .data(nodes)
      .join("g")
      .attr("class", "ora-node")
      .style("cursor", "pointer")
      .on("click", (event, d) => {
        event.stopPropagation();
        this.dispatchEvent(
          new CustomEvent("ora-graph-node-select", {
            detail: { pageId: d.id },
            bubbles: true,
          })
        );
      });

    const node = nodeGroup
      .append("circle")
      .attr("r", (d) => {
        const deg = degree.get(d.id) || 0;
        return Math.min(Math.max(8, deg * 1.5 + 6), 16);
      })
      .attr("fill", (d) => {
        if (d.community_id == null) return "#94a3b8";
        return `hsl(${(d.community_id * 137.508) % 360}, 70%, 55%)`;
      })
      .attr("stroke", "#fff")
      .attr("stroke-width", 2);

    nodeGroup
      .append("text")
      .attr("x", 14)
      .attr("y", 4)
      .attr("font-size", "11px")
      .attr("font-family", "system-ui, sans-serif")
      .attr("fill", "#374151")
      .style("pointer-events", "none")
      .text((d) => d.label || "");

    node.append("title").text((d) => d.label || d.id);

    this._simulation = forceSimulation(nodes)
      .force("link", forceLink(edges).id((d) => d.id).distance(80))
      .force("charge", forceManyBody().strength(-200))
      .force("center", forceCenter(width / 2, height / 2));

    this._simulation.on("tick", () => {
      link
        .attr("x1", (d) => d.source.x)
        .attr("y1", (d) => d.source.y)
        .attr("x2", (d) => d.target.x)
        .attr("y2", (d) => d.target.y);
      nodeGroup.attr("transform", (d) => `translate(${d.x}, ${d.y})`);
    });
  }

}

if (!customElements.get("ora-workspace-graph")) {
  customElements.define("ora-workspace-graph", OraWorkspaceGraph);
}
