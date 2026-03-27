/**
 * SimGraphHook — D3.js force-directed graph for simulation visualization.
 *
 * Renders agents and entities as an interactive network graph.
 * Receives real-time updates from the LiveView server via push_event.
 *
 * Visual encoding:
 * - Agent nodes: circles, colored by FSM state
 * - Entity nodes: rounded rectangles
 * - Links: width from weight, color from sentiment
 * - Event pulses: expanding ring animations
 */

const STATE_COLORS = {
  idle: "#B4B2A9",
  observing: "#5DCAA5",
  deliberating: "#AFA9EC",
  reacting: "#F0997B",
  acting: "#FAC775",
  negotiating: "#85B7EB",
  recovering: "#E57373",
};

const SENTIMENT_COLORS = {
  positive: "#4CAF50",
  negative: "#F44336",
  neutral: "#9E9E9E",
};

const SimGraphHook = {
  mounted() {
    this.initGraph();
    this.handleEvent("tick_update", (delta) => this.applyDelta(delta));
  },

  initGraph() {
    const el = this.el;
    const width = el.clientWidth || 900;
    const height = 400;

    // Parse initial data
    try {
      this.nodes = JSON.parse(el.dataset.initialNodes || "[]");
      this.links = JSON.parse(el.dataset.initialLinks || "[]");
    } catch {
      this.nodes = [];
      this.links = [];
    }

    // Create SVG
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.setAttribute("width", "100%");
    svg.setAttribute("viewBox", `0 0 ${width} ${height}`);
    svg.style.background = "transparent";
    el.appendChild(svg);

    this.svg = svg;
    this.width = width;
    this.height = height;

    // Create container group
    const g = document.createElementNS("http://www.w3.org/2000/svg", "g");
    svg.appendChild(g);
    this.g = g;

    // Show placeholder if no data
    if (this.nodes.length === 0) {
      const text = document.createElementNS(
        "http://www.w3.org/2000/svg",
        "text"
      );
      text.setAttribute("x", width / 2);
      text.setAttribute("y", height / 2);
      text.setAttribute("text-anchor", "middle");
      text.setAttribute("fill", "#71717a");
      text.setAttribute("font-size", "14");
      text.textContent = "Simulation graph will appear when running";
      g.appendChild(text);
      this.placeholder = text;
    }

    // D3 will be loaded lazily if available
    this.d3Ready = typeof d3 !== "undefined";
    if (this.d3Ready) {
      this.initD3();
    }
  },

  initD3() {
    if (!d3) return;

    this.simulation = d3
      .forceSimulation(this.nodes)
      .force(
        "link",
        d3
          .forceLink(this.links)
          .id((d) => d.id)
          .distance(80)
      )
      .force("charge", d3.forceManyBody().strength(-200))
      .force("center", d3.forceCenter(this.width / 2, this.height / 2))
      .force(
        "collision",
        d3.forceCollide().radius((d) => (d.radius || 20) + 4)
      )
      .on("tick", () => this.render());
  },

  applyDelta(delta) {
    // Remove placeholder
    if (this.placeholder) {
      this.placeholder.remove();
      this.placeholder = null;
    }

    // Update node states
    for (const upd of delta.node_updates || []) {
      const node = this.nodes.find((n) => n.id === upd.id);
      if (node) {
        node.state = upd.state;
        node.modifier = upd.modifier;
      }
    }

    // Update edge weights
    for (const upd of delta.edge_updates || []) {
      const link = this.links.find(
        (l) =>
          (l.source.id || l.source) === upd.from &&
          (l.target.id || l.target) === upd.to
      );
      if (link) {
        link.weight = upd.weight;
        link.sentiment = upd.sentiment;
      }
    }

    // Add new edges
    for (const edge of delta.new_edges || []) {
      this.links.push({
        source: edge.from,
        target: edge.to,
        weight: edge.weight,
        sentiment: edge.sentiment,
      });
    }

    // Remove edges
    for (const rem of delta.removed_edges || []) {
      this.links = this.links.filter(
        (l) =>
          !(
            (l.source.id || l.source) === rem.from &&
            (l.target.id || l.target) === rem.to
          )
      );
    }

    // Re-render (simple SVG if D3 not loaded)
    if (this.d3Ready && this.simulation) {
      this.simulation.nodes(this.nodes);
      this.simulation.force("link").links(this.links);
      this.simulation.alpha(0.3).restart();
    } else {
      this.renderSimple();
    }

    // Update tick counter display
    this.updateTickDisplay(delta);
  },

  render() {
    // D3 tick render — update positions
    // This is called by d3.forceSimulation on each tick
    const g = d3.select(this.g);

    // Links
    const linkSel = g.selectAll("line.link").data(this.links);
    linkSel
      .enter()
      .append("line")
      .attr("class", "link")
      .merge(linkSel)
      .attr("x1", (d) => d.source.x)
      .attr("y1", (d) => d.source.y)
      .attr("x2", (d) => d.target.x)
      .attr("y2", (d) => d.target.y)
      .attr("stroke", (d) => SENTIMENT_COLORS[d.sentiment] || "#666")
      .attr("stroke-width", (d) => Math.max(1, (d.weight || 0.5) * 4));
    linkSel.exit().remove();

    // Nodes
    const nodeSel = g.selectAll("circle.node").data(this.nodes);
    nodeSel
      .enter()
      .append("circle")
      .attr("class", "node")
      .attr("r", (d) => d.radius || 15)
      .attr("cursor", "pointer")
      .on("click", (event, d) => {
        this.pushEvent("select_agent", { id: d.id });
      })
      .merge(nodeSel)
      .attr("cx", (d) => d.x)
      .attr("cy", (d) => d.y)
      .attr("fill", (d) => STATE_COLORS[d.state] || STATE_COLORS.idle)
      .attr("stroke", (d) => (d.modifier ? "#fff" : "none"))
      .attr("stroke-width", (d) => (d.modifier ? 2 : 0));
    nodeSel.exit().remove();

    // Labels
    const labelSel = g.selectAll("text.label").data(this.nodes);
    labelSel
      .enter()
      .append("text")
      .attr("class", "label")
      .attr("text-anchor", "middle")
      .attr("fill", "#ccc")
      .attr("font-size", "10")
      .merge(labelSel)
      .attr("x", (d) => d.x)
      .attr("y", (d) => d.y + (d.radius || 15) + 12)
      .text((d) => d.label || d.id);
    labelSel.exit().remove();
  },

  renderSimple() {
    // Fallback SVG rendering without D3
    while (this.g.firstChild) this.g.removeChild(this.g.firstChild);

    const text = document.createElementNS(
      "http://www.w3.org/2000/svg",
      "text"
    );
    text.setAttribute("x", this.width / 2);
    text.setAttribute("y", 30);
    text.setAttribute("text-anchor", "middle");
    text.setAttribute("fill", "#a1a1aa");
    text.setAttribute("font-size", "12");
    text.textContent = `${this.nodes.length} agents, ${this.links.length} relationships`;
    this.g.appendChild(text);
  },

  updateTickDisplay(delta) {
    // Update any tick counter elements
    const tickEl = this.el.querySelector("[data-tick]");
    if (tickEl) {
      tickEl.textContent = `Tick ${delta.tick}`;
    }
  },
};

export default SimGraphHook;
