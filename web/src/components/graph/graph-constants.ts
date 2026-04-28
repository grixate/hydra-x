// Graph Optimization spec §6 — restrained five-family palette plus three
// semantic state tones. Hex values chosen for equal perceptual weight
// against a neutral background; tweak via the prototype pass in §11.
//
// Five type families:
//   Anchor      (Vision)         — warm, distinctive
//   Structural  (Strategy/Dec.)  — cool, deliberate
//   Evidence    (Insight/Source) — lighter, supporting
//   Output      (Req/Des/Arch)   — neutral-forward, grounded
//   Outcome     (Outcome/Learn.) — warm again, closes loop
//
// Three semantic state tones, applied orthogonally:
//   coherence tension (amber)
//   agent activity    (cool)
//   staleness         (desaturated)

// ---- Family palette -------------------------------------------------

export const FAMILY_COLORS = {
  anchor: "#b4541f", // warm terracotta — roots
  structural: "#0f5a7a", // deep teal — skeleton
  evidence: "#7c8bad", // soft steel — supporting
  output: "#3f4a5c", // grounded slate — the what
  outcome: "#9a5d2a", // warm amber — closes the loop
} as const;

export const STATE_TONES = {
  tension: "#d97706", // amber-leaning contradictions
  activity: "#3b6cb8", // cool blue — agent working
  staleness: "#9ca3af", // desaturated — drift
  wip: "#a78bfa", // purple — work-in-progress
} as const;

// Legacy API (NODE_COLORS[node_type]) kept so existing components keep
// working. New components should prefer familyFor/colorFor/toneFor.
export const NODE_COLORS: Record<string, string> = {
  // Anchor
  vision: FAMILY_COLORS.anchor,
  // Structural
  strategy: FAMILY_COLORS.structural,
  decision: FAMILY_COLORS.structural,
  constraint: "#ef4444",
  // Evidence
  insight: FAMILY_COLORS.evidence,
  source: FAMILY_COLORS.evidence,
  source_ref: FAMILY_COLORS.evidence,
  signal: FAMILY_COLORS.evidence,
  excerpt: "#a8b3c9",
  // Library entities (spec §5.2 — visual distinction)
  topic: "#7c5cd1",
  author: "#0e8a6c",
  publication: "#7e6a4f",
  // Output
  requirement: FAMILY_COLORS.output,
  design_node: FAMILY_COLORS.output,
  architecture_node: FAMILY_COLORS.output,
  task: FAMILY_COLORS.output,
  routine: FAMILY_COLORS.output,
  knowledge_entry: FAMILY_COLORS.output,
  // Outcome
  outcome: FAMILY_COLORS.outcome,
  learning: FAMILY_COLORS.outcome,
  default: FAMILY_COLORS.output,
};

export type NodeFamily = "anchor" | "structural" | "evidence" | "output" | "outcome";

export function familyFor(nodeType: string): NodeFamily {
  switch (nodeType) {
    case "vision":
      return "anchor";
    case "strategy":
    case "decision":
    case "constraint":
      return "structural";
    case "insight":
    case "source":
    case "source_ref":
    case "signal":
      return "evidence";
    case "outcome":
    case "learning":
      return "outcome";
    default:
      return "output";
  }
}

export function colorFor(nodeType: string): string {
  return NODE_COLORS[nodeType] ?? NODE_COLORS.default;
}

// Size hints by family (overview zoom §6)
export const FAMILY_SIZE_WEIGHT: Record<NodeFamily, number> = {
  anchor: 1.25,
  structural: 1.1,
  evidence: 0.9,
  output: 1.0,
  outcome: 1.05,
};

// ---- Edges ----------------------------------------------------------

export const EDGE_STYLES: Record<
  string,
  {
    stroke: string;
    strokeDasharray?: string;
    strokeWidth: number;
    animated?: boolean;
  }
> = {
  lineage: { stroke: "#94a3b8", strokeWidth: 1.5 },
  supports: { stroke: "#94a3b8", strokeWidth: 1 },
  contradicts: { stroke: STATE_TONES.tension, strokeDasharray: "6 4", strokeWidth: 1.5 },
  supersedes: { stroke: "#9ca3af", strokeDasharray: "3 3", strokeWidth: 1 },
  blocks: { stroke: "#f97316", strokeWidth: 2 },
  enables: { stroke: "#22c55e", strokeWidth: 2 },
  dependency: { stroke: "#94a3b8", strokeDasharray: "4 2", strokeWidth: 1 },
  constrains: { stroke: STATE_TONES.tension, strokeDasharray: "4 2", strokeWidth: 1 },
  default: { stroke: "#94a3b8", strokeWidth: 1 },
};

// Map node types to ELK layer partitions (lower = higher position)
export const LAYER_ORDER: Record<string, number> = {
  vision: -1,
  source: 0,
  signal: 0,
  constraint: 1,
  insight: 2,
  decision: 3,
  strategy: 3,
  requirement: 4,
  design_node: 5,
  architecture_node: 5,
  task: 6,
  learning: 7,
  outcome: 7,
  routine: 7,
  knowledge_entry: 1,
};

// Edge kinds that should have arrowhead markers
export const DIRECTED_EDGE_KINDS = new Set([
  "lineage",
  "blocks",
  "enables",
]);

// Status grouping — colors and labels
export const STATUS_COLORS: Record<string, string> = {
  draft: "#f59e0b",
  pending: "#f59e0b",
  active: "#22c55e",
  accepted: "#22c55e",
  archived: "#94a3b8",
  superseded: "#94a3b8",
  done: "#10b981",
  default: "#6b7280",
};

export function statusGroupKey(status: string): string {
  if (status === "active" || status === "accepted") return "active";
  if (status === "draft" || status === "pending") return "draft";
  if (status === "archived" || status === "superseded") return "archived";
  if (status === "done") return "done";
  return status || "other";
}

export function prettyLabel(value: string): string {
  return value
    .replace(/_/g, " ")
    .replace(/\b\w/g, (c) => c.toUpperCase());
}

// All filterable node types (shown in toolbar). Sources are filterable
// mostly so users can opt back in when inspecting promoted sources; default
// graph data already hides non-promoted sources at the API level.
export const FILTERABLE_NODE_TYPES = [
  "source",
  "insight",
  "decision",
  "strategy",
  "requirement",
  "design_node",
  "architecture_node",
  "task",
  "learning",
  "constraint",
];

// Library spec §5.1 — node types visible by default in the Library lens.
// Authors/publications/excerpts are toggleable; sources + topics are the
// primary structure.
export const LIBRARY_FILTERABLE_NODE_TYPES = [
  "source",
  "topic",
  "excerpt",
  "author",
  "publication",
];

// Library spec §5.1 — what's visible by default before the user touches
// any filter chips. Excerpts/authors/publications start hidden; the user
// toggles them on when relevant. Sources + topics carry the primary signal.
export const LIBRARY_DEFAULT_VISIBLE_TYPES = ["source", "topic"];

// ---- Motion tokens --------------------------------------------------
// Spec §7: motion vocabulary with consistent timings across all surfaces.
// Tune in the prototype pass but commit these as defaults.
export const MOTION = {
  // Arrival / departure
  ARRIVAL_MS: 250,
  DEPARTURE_MS: 250,
  EDGE_DRAW_MS: 400,
  // Focus / selection
  FOCUS_MS: 400,
  // Restructure (signature composed-view animation)
  RESTRUCTURE_DIM_MS: 200,
  RESTRUCTURE_MOVE_MS: 800,
  // State changes
  STATE_PULSE_MS: 600,
  // WIP forming animation
  WIP_FORM_MS: 800,
  // Hover tooltip reveal
  HOVER_DELAY_MS: 400,
  // Easing (used via CSS cubic-bezier strings)
  EASE_OUT: "cubic-bezier(0.2, 0.8, 0.2, 1)",
  EASE_IN_OUT: "cubic-bezier(0.4, 0.0, 0.2, 1)",
  // Spec §4 O4: if more than N nodes need to move, skip the animation and
  // snap — crossing this threshold kicks the "subtle indicator" code path.
  RESTRUCTURE_SKIP_THRESHOLD: 500,
  // Stagger wave size when animating bulk moves (O4).
  STAGGER_BATCH: 20,
  STAGGER_INTERVAL_MS: 50,
} as const;
