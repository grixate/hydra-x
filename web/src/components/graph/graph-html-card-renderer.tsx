import { Component, type ErrorInfo, type ReactNode } from "react";
import { createRoot, type Root } from "react-dom/client";

import type { Graph } from "@cosmos.gl/graph";
import type { GraphDataNode, SourceReference } from "@/types";

import { TooltipProvider } from "@/components/ui/tooltip";
import { GraphCanvasCard, type GraphCanvasCardActions } from "./graph-canvas-card";
import type { CosmosGraphModel, GraphAltitude } from "./cosmos-graph-adapter";

// Each card renders in its own React root (createRoot per pool entry),
// detached from the app. An uncaught error inside the card would otherwise
// propagate up to React's recovery path and unmount the *surface*, killing
// the constellation and all chrome. The boundary below isolates failures to
// the failing card.
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
    console.warn("[GraphCanvasCard] render error contained", error, info);
  }

  render() {
    if (this.state.hasError) {
      return null;
    }
    return this.props.children;
  }
}

type TextureRecord = {
  element: HTMLDivElement;
  texture: WebGLTexture;
  width: number;
  height: number;
  dirty: boolean;
  contentKey?: string;
  root?: Root;
};

type RenderScene = {
  graph: Graph;
  model: CosmosGraphModel;
  altitude: GraphAltitude;
  selectedNodeId: string | null;
  hoveredNodeId: string | null;
  sourceRefs: SourceReference[];
  labelIndices?: number[];
};

type WebGLWithHtml = WebGL2RenderingContext & {
  texElementImage2D?: (
    target: number,
    level: number,
    internalformat: number,
    format: number,
    type: number,
    source: Element,
  ) => void;
};

const CARD_WIDTH = 400;
const CARD_HEIGHT = 280;
const CARD_POOL_SIZE = 6;
const LABEL_POOL_SIZE = 72;

export class GraphHtmlCardRenderer {
  public readonly canvas: HTMLCanvasElement;
  public readonly supported: boolean;
  public readonly unsupportedReason?: string;

  private gl: WebGLWithHtml | null = null;
  private program: WebGLProgram | null = null;
  private positionBuffer: WebGLBuffer | null = null;
  private texcoordBuffer: WebGLBuffer | null = null;
  private resolutionLocation: WebGLUniformLocation | null = null;
  private cardPool: TextureRecord[] = [];
  private labelPool: TextureRecord[] = [];
  private scene: RenderScene | null = null;
  private raf = 0;
  private actions: GraphCanvasCardActions;

  public constructor(parent: HTMLElement, actions: GraphCanvasCardActions) {
    this.actions = actions;
    this.canvas = document.createElement("canvas");
    this.canvas.setAttribute("layoutsubtree", "");
    this.canvas.className = "hydra-graph-html-canvas absolute inset-0 z-[8] h-full w-full";
    parent.appendChild(this.canvas);

    this.gl = this.canvas.getContext("webgl2", {
      alpha: true,
      antialias: true,
      premultipliedAlpha: true,
    }) as WebGLWithHtml | null;

    if (!this.gl) {
      this.supported = false;
      this.unsupportedReason = "WebGL2 is required for the graph card texture layer.";
      return;
    }

    if (typeof this.gl.texElementImage2D !== "function") {
      this.supported = false;
      this.unsupportedReason =
        "This browser does not expose html-in-canvas texElementImage2D.";
      return;
    }

    this.supported = true;
    this.program = createProgram(this.gl);
    this.positionBuffer = this.gl.createBuffer();
    this.texcoordBuffer = this.gl.createBuffer();
    this.resolutionLocation = this.gl.getUniformLocation(this.program, "u_resolution");

    this.cardPool = this.createCardPool(CARD_POOL_SIZE);
    this.labelPool = this.createLabelPool(LABEL_POOL_SIZE);
    this.canvas.addEventListener("paint", this.handlePaint);
  }

  public render(scene: RenderScene): void {
    this.scene = scene;
    if (!this.supported) return;
    this.syncCardPool();
    this.syncLabelPool();
    this.requestDraw();
  }

  public updateActions(actions: GraphCanvasCardActions): void {
    this.actions = actions;
    for (const record of this.cardPool) {
      record.contentKey = undefined;
    }
    this.syncCardPool();
    this.requestDraw();
  }

  public destroy(): void {
    cancelAnimationFrame(this.raf);
    this.canvas.removeEventListener("paint", this.handlePaint);
    for (const record of [...this.cardPool, ...this.labelPool]) {
      record.root?.unmount();
      record.element.remove();
      if (this.gl) this.gl.deleteTexture(record.texture);
    }
    this.canvas.remove();
  }

  private handlePaint = () => {
    for (const record of [...this.cardPool, ...this.labelPool]) {
      record.dirty = true;
    }
    this.draw();
  };

  private createCardPool(count: number): TextureRecord[] {
    return Array.from({ length: count }, () => {
      const element = document.createElement("div");
      element.className = "hydra-graph-card-hit-target absolute left-0 top-0";
      element.style.width = `${CARD_WIDTH}px`;
      element.style.height = `${CARD_HEIGHT}px`;
      element.style.transformOrigin = "0 0";
      this.canvas.appendChild(element);
      return {
        element,
        texture: this.createTexture(),
        width: CARD_WIDTH,
        height: CARD_HEIGHT,
        dirty: true,
        root: createRoot(element),
      };
    });
  }

  private createLabelPool(count: number): TextureRecord[] {
    return Array.from({ length: count }, () => {
      const element = document.createElement("div");
      element.className =
        "hydra-graph-label absolute left-0 top-0 max-w-[190px] truncate rounded-full border border-border/70 bg-background/90 px-2 py-1 text-[11px] font-medium text-foreground shadow-sm";
      element.style.transformOrigin = "0 0";
      element.style.width = "190px";
      element.style.height = "28px";
      element.style.display = "none";
      this.canvas.appendChild(element);
      return {
        element,
        texture: this.createTexture(),
        width: 190,
        height: 28,
        dirty: true,
      };
    });
  }

  private createTexture(): WebGLTexture {
    const gl = this.requireGl();
    const texture = gl.createTexture();
    if (!texture) throw new Error("Could not create graph card texture.");
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    return texture;
  }

  private syncCardPool(): void {
    const scene = this.scene;
    if (!scene) return;
    const selected = scene.selectedNodeId
      ? scene.model.nodes.find((node) => node.id === scene.selectedNodeId)
      : null;
    const visible = scene.altitude === "document" && selected ? [selected] : [];

    this.cardPool.forEach((record, index) => {
      const node = visible[index];
      if (!node) {
        record.element.style.display = "none";
        record.contentKey = undefined;
        return;
      }

      record.element.style.display = "block";
      const nextKey = cardContentKey(node, scene.sourceRefs);
      if (record.contentKey !== nextKey) {
        // The card pool's React roots are detached from the app tree, so
        // they don't inherit the global TooltipProvider. Wrap each card
        // root in its own provider — without this, every <Tooltip> inside
        // GraphCanvasCard throws and crashes the surface.
        // Also wrap in an error boundary so any future card-level error
        // is contained to that card and never unmounts the GraphView.
        record.root?.render(
          <CardErrorBoundary>
            <TooltipProvider delayDuration={120}>
              <GraphCanvasCard node={node} sourceRefs={scene.sourceRefs} actions={this.actions} />
            </TooltipProvider>
          </CardErrorBoundary>,
        );
        record.contentKey = nextKey;
        record.dirty = true;
      }
    });
  }

  private syncLabelPool(): void {
    const scene = this.scene;
    if (!scene) return;
    if (scene.altitude === "overview") {
      this.labelPool.forEach((record) => {
        record.element.style.display = "none";
        record.contentKey = undefined;
      });
      return;
    }

    const sampled = scene.graph.getSampledPointPositionsMap();
    const labels = Array.from(sampled.keys())
      .map((index) => scene.model.nodes[index])
      .filter((node): node is GraphDataNode => Boolean(node))
      .slice(0, LABEL_POOL_SIZE);

    this.labelPool.forEach((record, index) => {
      const node = labels[index];
      if (!node || scene.altitude === "document") {
        record.element.style.display = "none";
        record.contentKey = undefined;
        return;
      }
      const nextKey = `${node.id}:${node.title}`;
      if (record.contentKey !== nextKey) {
        record.element.textContent = node.title;
        record.contentKey = nextKey;
        record.dirty = true;
      }
      record.element.style.display = "block";
    });
  }

  private requestDraw(): void {
    cancelAnimationFrame(this.raf);
    this.raf = requestAnimationFrame(() => this.draw());
  }

  private draw(): void {
    const scene = this.scene;
    const gl = this.gl;
    if (!scene || !gl || !this.program) return;

    this.resize();
    gl.viewport(0, 0, this.canvas.width, this.canvas.height);
    gl.clearColor(0, 0, 0, 0);
    gl.clear(gl.COLOR_BUFFER_BIT);
    gl.enable(gl.BLEND);
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
    gl.useProgram(this.program);
    gl.uniform2f(this.resolutionLocation, this.canvas.width, this.canvas.height);

    this.drawLabels(scene);
    this.drawCards(scene);
  }

  private drawLabels(scene: RenderScene): void {
    if (scene.altitude === "overview" || scene.altitude === "document") return;
    const sampled = scene.graph.getSampledPointPositionsMap();
    let poolIndex = 0;
    for (const [nodeIndex, spacePosition] of sampled) {
      if (poolIndex >= this.labelPool.length) break;
      const node = scene.model.nodes[nodeIndex];
      if (!node) continue;
      const record = this.labelPool[poolIndex++];
      const [x, y] = scene.graph.spaceToScreenPosition(spacePosition);
      const { left, top } = this.clampRect(x + 12, y - 14, record.width, record.height);
      this.positionHitTarget(record, left, top);
      this.uploadAndDraw(record, left, top);
    }
  }

  private drawCards(scene: RenderScene): void {
    if (scene.altitude !== "document" || !scene.selectedNodeId) return;
    const index = scene.model.nodeIndexById.get(scene.selectedNodeId);
    if (index === undefined) return;
    const node = scene.model.nodes[index];
    if (!node) return;

    const tracked = scene.graph.getTrackedPointPositionsMap();
    const spacePosition = tracked.get(index) ?? [0, 0];
    const [x, y] = scene.graph.spaceToScreenPosition(spacePosition);
    const record = this.cardPool[0];
    const preferredLeft = x + 22 + CARD_WIDTH > this.canvas.clientWidth ? x - CARD_WIDTH - 22 : x + 22;
    const { left, top } = this.clampRect(preferredLeft, y - CARD_HEIGHT / 2, CARD_WIDTH, CARD_HEIGHT);
    this.positionHitTarget(record, left, top);
    this.uploadAndDraw(record, left, top);
  }

  private clampRect(left: number, top: number, width: number, height: number): { left: number; top: number } {
    const margin = 8;
    const maxLeft = Math.max(margin, this.canvas.clientWidth - width - margin);
    const maxTop = Math.max(margin, this.canvas.clientHeight - height - margin);
    return {
      left: Math.min(maxLeft, Math.max(margin, left)),
      top: Math.min(maxTop, Math.max(margin, top)),
    };
  }

  private positionHitTarget(record: TextureRecord, left: number, top: number): void {
    record.element.style.transform = `translate3d(${left}px, ${top}px, 0)`;
  }

  private uploadAndDraw(record: TextureRecord, left: number, top: number): void {
    const gl = this.requireGl();
    gl.bindTexture(gl.TEXTURE_2D, record.texture);
    if (record.dirty) {
      gl.texElementImage2D?.(
        gl.TEXTURE_2D,
        0,
        gl.RGBA,
        gl.RGBA,
        gl.UNSIGNED_BYTE,
        record.element,
      );
      record.dirty = false;
    }
    this.drawQuad(record.texture, left, top, record.width, record.height);
  }

  private drawQuad(texture: WebGLTexture, left: number, top: number, width: number, height: number): void {
    const gl = this.requireGl();
    const dpr = window.devicePixelRatio || 1;
    const x = left * dpr;
    const y = top * dpr;
    const w = width * dpr;
    const h = height * dpr;

    const positions = new Float32Array([
      x, y,
      x + w, y,
      x, y + h,
      x, y + h,
      x + w, y,
      x + w, y + h,
    ]);
    const texcoords = new Float32Array([
      0, 0,
      1, 0,
      0, 1,
      0, 1,
      1, 0,
      1, 1,
    ]);

    const positionLocation = gl.getAttribLocation(this.program!, "a_position");
    const texcoordLocation = gl.getAttribLocation(this.program!, "a_texcoord");

    gl.bindBuffer(gl.ARRAY_BUFFER, this.positionBuffer);
    gl.bufferData(gl.ARRAY_BUFFER, positions, gl.DYNAMIC_DRAW);
    gl.enableVertexAttribArray(positionLocation);
    gl.vertexAttribPointer(positionLocation, 2, gl.FLOAT, false, 0, 0);

    gl.bindBuffer(gl.ARRAY_BUFFER, this.texcoordBuffer);
    gl.bufferData(gl.ARRAY_BUFFER, texcoords, gl.STATIC_DRAW);
    gl.enableVertexAttribArray(texcoordLocation);
    gl.vertexAttribPointer(texcoordLocation, 2, gl.FLOAT, false, 0, 0);

    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.drawArrays(gl.TRIANGLES, 0, 6);
  }

  private resize(): void {
    const dpr = window.devicePixelRatio || 1;
    const rect = this.canvas.getBoundingClientRect();
    const width = Math.max(1, Math.round(rect.width * dpr));
    const height = Math.max(1, Math.round(rect.height * dpr));
    if (this.canvas.width !== width || this.canvas.height !== height) {
      this.canvas.width = width;
      this.canvas.height = height;
    }
  }

  private requireGl(): WebGLWithHtml {
    if (!this.gl) throw new Error("Graph html-in-canvas renderer is not initialized.");
    return this.gl;
  }
}

function createProgram(gl: WebGL2RenderingContext): WebGLProgram {
  const vertex = compileShader(
    gl,
    gl.VERTEX_SHADER,
    `#version 300 es
    in vec2 a_position;
    in vec2 a_texcoord;
    uniform vec2 u_resolution;
    out vec2 v_texcoord;
    void main() {
      vec2 zeroToOne = a_position / u_resolution;
      vec2 clipSpace = zeroToOne * 2.0 - 1.0;
      gl_Position = vec4(clipSpace * vec2(1.0, -1.0), 0.0, 1.0);
      v_texcoord = a_texcoord;
    }`,
  );
  const fragment = compileShader(
    gl,
    gl.FRAGMENT_SHADER,
    `#version 300 es
    precision highp float;
    uniform sampler2D u_texture;
    in vec2 v_texcoord;
    out vec4 outColor;
    void main() {
      outColor = texture(u_texture, v_texcoord);
    }`,
  );
  const program = gl.createProgram();
  if (!program) throw new Error("Could not create graph html canvas program.");
  gl.attachShader(program, vertex);
  gl.attachShader(program, fragment);
  gl.linkProgram(program);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    throw new Error(gl.getProgramInfoLog(program) ?? "Could not link graph html canvas program.");
  }
  return program;
}

function compileShader(gl: WebGL2RenderingContext, type: number, source: string): WebGLShader {
  const shader = gl.createShader(type);
  if (!shader) throw new Error("Could not create graph html canvas shader.");
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    throw new Error(gl.getShaderInfoLog(shader) ?? "Could not compile graph html canvas shader.");
  }
  return shader;
}

function cardContentKey(node: GraphDataNode, sourceRefs: SourceReference[]): string {
  const refsKey =
    sourceRefs.length > 0
      ? sourceRefs
          .map((ref) => `${ref.id}:${ref.confidence ?? "none"}:${ref.source?.title ?? ""}`)
          .join("|")
      : `fallback:${node.source_reference_count ?? 0}`;

  return [
    node.id,
    node.title,
    node.body,
    node.node_type,
    node.status,
    node.flag_count,
    node.upstream_count,
    node.downstream_count,
    node.updated_at ?? "",
    refsKey,
  ].join("::");
}
