/**
 * GraphVisualization hook for the Product Graph LiveView.
 * Renders nodes in a swimlane layout grouped by type.
 * Falls back to server-rendered HTML if this hook doesn't load.
 */
const GraphVisualization = {
  mounted() {
    this.renderGraph()
    this.handleEvent && this.handleEvent("graph_updated", () => this.renderGraph())
  },

  updated() {
    this.renderGraph()
  },

  renderGraph() {
    const container = this.el
    const fallback = container.querySelector("#graph-fallback")

    // Parse data from attributes
    let nodes, edges
    try {
      nodes = JSON.parse(container.dataset.nodes || "[]")
      edges = JSON.parse(container.dataset.edges || "[]")
    } catch (e) {
      console.warn("GraphVisualization: could not parse data", e)
      return
    }

    // If no nodes, let the fallback show
    if (nodes.length === 0) {
      if (fallback) fallback.style.display = ""
      return
    }

    // For now, use the server-rendered fallback layout.
    // A future iteration can replace this with D3/ELK visualization.
    if (fallback) {
      fallback.style.display = ""
    }
  }
}

export default GraphVisualization
