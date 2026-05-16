import { LitElement, html } from "lit";
import { forceSimulation, forceLink, forceManyBody, forceCenter } from "d3-force";
import { select } from "d3-selection";
import { zoom } from "d3-zoom";

export class OraWorkspaceGraph extends LitElement {
  static properties = {
    data: { type: String },
    workspaceSlug: { type: String, attribute: "workspace-slug" },
  };

  constructor() {
    super();
    this.data = "{}";
    this.workspaceSlug = "";
    this._graphData = { nodes: [], edges: [], communities: [] };
    this._simulation = null;
  }

  createRenderRoot() {
    return this;
  }

  willUpdate(changed) {
    if (changed.has("data")) {
      try {
        const parsed = JSON.parse(this.data || "{}");
        this._graphData = {
          nodes: parsed.nodes || [],
          edges: parsed.edges || [],
          communities: parsed.communities || [],
        };
      } catch {
        this._graphData = { nodes: [], edges: [], communities: [] };
      }
    }
  }

  updated() {
    if (!this._graphData.nodes.length) return;
    this._drawGraph();
  }

  disconnectedCallback() {
    super.disconnectedCallback();
    if (this._simulation) {
      this._simulation.stop();
      this._simulation = null;
    }
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

    const node = g
      .append("g")
      .selectAll("circle")
      .data(nodes)
      .join("circle")
      .attr("r", (d) => {
        const deg = degree.get(d.id) || 0;
        return Math.min(Math.max(4, deg * 1.5 + 3), 10);
      })
      .attr("fill", (d) => {
        if (d.community_id == null) return "#94a3b8";
        return `hsl(${(d.community_id * 137.508) % 360}, 70%, 55%)`;
      })
      .attr("stroke", "#fff")
      .attr("stroke-width", 1.5)
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
      node.attr("cx", (d) => d.x).attr("cy", (d) => d.y);
    });
  }

  render() {
    if (!this._graphData.nodes.length) {
      return html`
        <div class="flex items-center justify-center h-full text-notion-text-light">
          Add pages to see the graph
        </div>
      `;
    }

    return html`
      <div class="relative w-full h-full overflow-hidden">
        <svg class="w-full h-full block"></svg>
      </div>
    `;
  }
}

if (!customElements.get("ora-workspace-graph")) {
  customElements.define("ora-workspace-graph", OraWorkspaceGraph);
}
