import type Sigma from "sigma";
import type Graph from "graphology";

export type SigmaGroup = {
  key: string;
  label: string;
  color: string;
  nodeKeys: string[];
};

type Pt = { x: number; y: number };

// Andrew's monotone chain convex hull. O(n log n).
function convexHull(points: Pt[]): Pt[] {
  if (points.length <= 1) return points.slice();
  const pts = points.slice().sort((a, b) => (a.x === b.x ? a.y - b.y : a.x - b.x));
  const cross = (o: Pt, a: Pt, b: Pt) =>
    (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
  const lower: Pt[] = [];
  for (const p of pts) {
    while (lower.length >= 2 && cross(lower[lower.length - 2], lower[lower.length - 1], p) <= 0)
      lower.pop();
    lower.push(p);
  }
  const upper: Pt[] = [];
  for (let i = pts.length - 1; i >= 0; i--) {
    const p = pts[i];
    while (upper.length >= 2 && cross(upper[upper.length - 2], upper[upper.length - 1], p) <= 0)
      upper.pop();
    upper.push(p);
  }
  upper.pop();
  lower.pop();
  return lower.concat(upper);
}

function expandHull(hull: Pt[], padding: number): Pt[] {
  if (hull.length === 0) return hull;
  let cx = 0;
  let cy = 0;
  for (const p of hull) {
    cx += p.x;
    cy += p.y;
  }
  cx /= hull.length;
  cy /= hull.length;
  return hull.map((p) => {
    const dx = p.x - cx;
    const dy = p.y - cy;
    const len = Math.hypot(dx, dy) || 1;
    return { x: p.x + (dx / len) * padding, y: p.y + (dy / len) * padding };
  });
}

function drawRoundedPath(ctx: CanvasRenderingContext2D, hull: Pt[], radius: number) {
  if (hull.length < 2) return;
  ctx.beginPath();
  for (let i = 0; i < hull.length; i++) {
    const a = hull[i];
    const b = hull[(i + 1) % hull.length];
    const c = hull[(i + 2) % hull.length];
    if (i === 0) ctx.moveTo((a.x + b.x) / 2, (a.y + b.y) / 2);
    ctx.arcTo(b.x, b.y, (b.x + c.x) / 2, (b.y + c.y) / 2, radius);
  }
  ctx.closePath();
}

export class GroupOverlay {
  private canvas: HTMLCanvasElement;
  private ctx: CanvasRenderingContext2D;
  private dpr: number;
  private groups: SigmaGroup[] = [];
  private cleanup: () => void;

  constructor(private sigma: Sigma, private graph: Graph) {
    const container = sigma.getContainer();
    this.canvas = document.createElement("canvas");
    this.canvas.style.position = "absolute";
    this.canvas.style.inset = "0";
    this.canvas.style.pointerEvents = "none";
    this.canvas.style.zIndex = "0";
    container.prepend(this.canvas);
    this.ctx = this.canvas.getContext("2d")!;
    this.dpr = window.devicePixelRatio || 1;
    this.resize();

    const onResize = () => this.resize();
    const onAfter = () => this.draw();
    window.addEventListener("resize", onResize);
    sigma.on("afterRender", onAfter);
    sigma.on("resize", onResize);

    this.cleanup = () => {
      window.removeEventListener("resize", onResize);
      sigma.off("afterRender", onAfter);
      sigma.off("resize", onResize);
      this.canvas.remove();
    };
  }

  setGroups(groups: SigmaGroup[]) {
    this.groups = groups;
    this.draw();
  }

  destroy() {
    this.cleanup();
  }

  private resize() {
    const container = this.sigma.getContainer();
    const w = container.clientWidth;
    const h = container.clientHeight;
    this.canvas.width = w * this.dpr;
    this.canvas.height = h * this.dpr;
    this.canvas.style.width = `${w}px`;
    this.canvas.style.height = `${h}px`;
    this.ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
    this.draw();
  }

  private draw() {
    const ctx = this.ctx;
    const w = this.canvas.width / this.dpr;
    const h = this.canvas.height / this.dpr;
    ctx.clearRect(0, 0, w, h);

    for (const group of this.groups) {
      const positions: Pt[] = [];
      for (const key of group.nodeKeys) {
        if (!this.graph.hasNode(key)) continue;
        const x = this.graph.getNodeAttribute(key, "x") as number;
        const y = this.graph.getNodeAttribute(key, "y") as number;
        const screen = this.sigma.graphToViewport({ x, y });
        positions.push(screen);
      }
      if (positions.length < 1) continue;

      let hull: Pt[];
      if (positions.length === 1) {
        const p = positions[0];
        const r = 60;
        hull = [
          { x: p.x - r, y: p.y - r },
          { x: p.x + r, y: p.y - r },
          { x: p.x + r, y: p.y + r },
          { x: p.x - r, y: p.y + r },
        ];
      } else if (positions.length === 2) {
        const [a, b] = positions;
        const dx = b.x - a.x;
        const dy = b.y - a.y;
        const len = Math.hypot(dx, dy) || 1;
        const nx = (-dy / len) * 50;
        const ny = (dx / len) * 50;
        hull = [
          { x: a.x + nx, y: a.y + ny },
          { x: b.x + nx, y: b.y + ny },
          { x: b.x - nx, y: b.y - ny },
          { x: a.x - nx, y: a.y - ny },
        ];
      } else {
        hull = expandHull(convexHull(positions), 50);
      }

      drawRoundedPath(ctx, hull, 20);
      ctx.fillStyle = `${group.color}14`;
      ctx.fill();
      ctx.strokeStyle = `${group.color}40`;
      ctx.lineWidth = 1;
      ctx.stroke();

      // Label at top of hull
      const top = hull.reduce((acc, p) => (p.y < acc.y ? p : acc), hull[0]);
      const label = `${group.label} (${group.nodeKeys.length})`;
      ctx.font = "600 11px system-ui, -apple-system, sans-serif";
      const metrics = ctx.measureText(label);
      const padX = 8;
      const padY = 4;
      const lw = metrics.width + padX * 2;
      const lh = 18;
      const lx = top.x - lw / 2;
      const ly = top.y - lh - 4;
      ctx.fillStyle = "rgba(255,255,255,0.95)";
      ctx.strokeStyle = `${group.color}66`;
      ctx.lineWidth = 1;
      ctx.beginPath();
      const r = 9;
      ctx.moveTo(lx + r, ly);
      ctx.arcTo(lx + lw, ly, lx + lw, ly + lh, r);
      ctx.arcTo(lx + lw, ly + lh, lx, ly + lh, r);
      ctx.arcTo(lx, ly + lh, lx, ly, r);
      ctx.arcTo(lx, ly, lx + lw, ly, r);
      ctx.closePath();
      ctx.fill();
      ctx.stroke();
      ctx.fillStyle = group.color;
      ctx.fillText(label, lx + padX, ly + lh - padY - 1);
    }
  }
}
