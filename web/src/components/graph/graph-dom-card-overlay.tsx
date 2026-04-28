import { Component, type ErrorInfo, type ReactNode } from "react";
import { createRoot, type Root } from "react-dom/client";

import type { Graph } from "@cosmos.gl/graph";
import type { GraphDataNode, SourceReference } from "@/types";

import { TooltipProvider } from "@/components/ui/tooltip";
import { GraphCanvasCard, type GraphCanvasCardActions } from "./graph-canvas-card";
import type { CosmosGraphModel, GraphAltitude } from "./cosmos-graph-adapter";

// Constellation §5.1 — DOM overlay fallback for the document/neighbourhood
// altitude card layer. No WebGL2 context, no texElementImage2D, no GPU
// texture pool. Just absolutely-positioned DOM elements re-positioned on
// each render. This is the default — the html-in-canvas WebGL2 path is
// opt-in only because it can OOM the GPU process on real-world hardware
// when the constellation is dense.
//
// Interface mirrors GraphHtmlCardRenderer so GraphView can pick either.

const CARD_WIDTH = 400;
const LABEL_POOL_SIZE = 60;

type RenderScene = {
  graph: Graph;
  model: CosmosGraphModel;
  altitude: GraphAltitude;
  selectedNodeId: string | null;
  hoveredNodeId: string | null;
  sourceRefs: SourceReference[];
  // Indices of nodes that should render a label. Computed by graph-view
  // (top-N most connected at neighbourhood altitude + hovered/selected
  // + their neighbours). Positions for these come from Cosmograph's
  // tracked-points map.
  labelIndices?: number[];
};

class CardErrorBoundary extends Component<
  { children: ReactNode },
  { hasError: boolean }
> {
  constructor(props: { children: ReactNode }) {
    super(props);
    this.state = { hasError: false };
  }

  static getDerivedStateFromError() {
    return { hasError: true };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.warn("[GraphDomCardOverlay] card render error contained", error, info);
  }

  render() {
    if (this.state.hasError) return null;
    return this.props.children;
  }
}

export class GraphDomCardOverlay {
  public readonly supported = true;
  public readonly unsupportedReason: string | undefined;

  private readonly container: HTMLDivElement;
  private readonly cardHost: HTMLDivElement;
  private readonly cardRoot: Root;
  private readonly labelPool: HTMLDivElement[];

  private actions: GraphCanvasCardActions;
  private scene: RenderScene | null = null;
  private currentCardKey: string | undefined;
  private raf = 0;

  public constructor(parent: HTMLElement, actions: GraphCanvasCardActions) {
    this.actions = actions;

    this.container = document.createElement("div");
    this.container.className = "hydra-graph-dom-overlay pointer-events-none absolute inset-0 z-[8]";
    parent.appendChild(this.container);

    this.cardHost = document.createElement("div");
    this.cardHost.className = "absolute left-0 top-0 pointer-events-auto";
    this.cardHost.style.width = `${CARD_WIDTH}px`;
    this.cardHost.style.transformOrigin = "0 0";
    this.cardHost.style.display = "none";
    this.container.appendChild(this.cardHost);
    this.cardRoot = createRoot(this.cardHost);

    this.labelPool = Array.from({ length: LABEL_POOL_SIZE }, () => {
      const label = document.createElement("div");
      label.className =
        "hydra-graph-label absolute left-0 top-0 max-w-[200px] truncate rounded-full border border-border/70 bg-background/90 px-2 py-1 text-[11px] font-medium text-foreground shadow-sm pointer-events-none";
      label.style.transformOrigin = "0 0";
      label.style.display = "none";
      this.container.appendChild(label);
      return label;
    });
  }

  public render(scene: RenderScene): void {
    this.scene = scene;
    this.requestDraw();
  }

  public updateActions(actions: GraphCanvasCardActions): void {
    this.actions = actions;
    this.currentCardKey = undefined;
    this.requestDraw();
  }

  public destroy(): void {
    cancelAnimationFrame(this.raf);
    try {
      this.cardRoot.unmount();
    } catch {
      // already unmounted
    }
    this.container.remove();
  }

  private requestDraw(): void {
    cancelAnimationFrame(this.raf);
    this.raf = requestAnimationFrame(() => this.draw());
  }

  private draw(): void {
    const scene = this.scene;
    if (!scene) return;

    this.drawLabels(scene);
    this.drawCard(scene);
  }

  private drawLabels(scene: RenderScene): void {
    // Document altitude: card replaces labels.
    if (scene.altitude === "document") {
      for (const el of this.labelPool) el.style.display = "none";
      return;
    }

    // Predictable algorithm (graph-view computes the index set):
    //   - top-N most connected nodes at neighbourhood altitude
    //   - hovered/selected node + 1-degree neighbours at any altitude
    //   - nothing at overview altitude with no hover/select
    const indices = scene.labelIndices ?? [];
    if (indices.length === 0) {
      for (const el of this.labelPool) el.style.display = "none";
      return;
    }

    const tracked = scene.graph.getTrackedPointPositionsMap();
    let poolIdx = 0;

    for (const nodeIndex of indices) {
      if (poolIdx >= this.labelPool.length) break;
      const node = scene.model.nodes[nodeIndex];
      const spacePos = tracked.get(nodeIndex);
      if (!node || !spacePos) continue;

      const el = this.labelPool[poolIdx++];
      if (!el) continue;
      const [x, y] = scene.graph.spaceToScreenPosition(spacePos);
      el.textContent = node.title;
      el.style.transform = `translate3d(${Math.round(x + 12)}px, ${Math.round(y - 14)}px, 0)`;
      el.style.display = "block";
    }
    for (; poolIdx < this.labelPool.length; poolIdx++) {
      this.labelPool[poolIdx].style.display = "none";
    }
  }

  private drawCard(scene: RenderScene): void {
    if (scene.altitude !== "document" || !scene.selectedNodeId) {
      this.cardHost.style.display = "none";
      this.currentCardKey = undefined;
      return;
    }

    const index = scene.model.nodeIndexById.get(scene.selectedNodeId);
    if (index === undefined) {
      this.cardHost.style.display = "none";
      return;
    }
    const node = scene.model.nodes[index];
    if (!node) {
      this.cardHost.style.display = "none";
      return;
    }

    const tracked = scene.graph.getTrackedPointPositionsMap();
    const spacePos = tracked.get(index) ?? [0, 0];
    const [x, y] = scene.graph.spaceToScreenPosition(spacePos);

    const containerRect = this.container.getBoundingClientRect();
    const cardHeight = this.cardHost.offsetHeight || 280;
    const margin = 8;
    const preferredLeft =
      x + 22 + CARD_WIDTH > containerRect.width ? x - CARD_WIDTH - 22 : x + 22;
    const left = Math.min(
      Math.max(margin, preferredLeft),
      Math.max(margin, containerRect.width - CARD_WIDTH - margin),
    );
    const top = Math.min(
      Math.max(margin, y - cardHeight / 2),
      Math.max(margin, containerRect.height - cardHeight - margin),
    );

    this.cardHost.style.transform = `translate3d(${Math.round(left)}px, ${Math.round(top)}px, 0)`;
    this.cardHost.style.display = "block";

    const nextKey = cardKey(node, scene.sourceRefs);
    if (this.currentCardKey !== nextKey) {
      this.cardRoot.render(
        <CardErrorBoundary>
          <TooltipProvider delayDuration={120}>
            <GraphCanvasCard node={node} sourceRefs={scene.sourceRefs} actions={this.actions} />
          </TooltipProvider>
        </CardErrorBoundary>,
      );
      this.currentCardKey = nextKey;
    }
  }
}

function cardKey(node: GraphDataNode, sourceRefs: SourceReference[]): string {
  const refs =
    sourceRefs.length > 0
      ? sourceRefs.map((r) => `${r.id}:${r.confidence ?? "x"}`).join("|")
      : `n${node.source_reference_count ?? 0}`;
  return [
    node.id,
    node.title,
    node.body,
    node.status,
    node.flag_count,
    node.upstream_count,
    node.downstream_count,
    refs,
  ].join("::");
}
