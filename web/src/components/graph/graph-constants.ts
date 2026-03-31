export const NODE_COLORS: Record<string, string> = {
  source: "#6b7280",
  signal: "#6b7280",
  insight: "#3b82f6",
  decision: "#f59e0b",
  strategy: "#14b8a6",
  requirement: "#22c55e",
  design_node: "#8b5cf6",
  architecture_node: "#64748b",
  task: "#f97316",
  learning: "#10b981",
  constraint: "#ef4444",
  routine: "#6366f1",
  knowledge_entry: "#06b6d4",
  default: "#6b7280",
};

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
  contradicts: { stroke: "#ef4444", strokeDasharray: "6 4", strokeWidth: 1.5 },
  supersedes: { stroke: "#9ca3af", strokeDasharray: "3 3", strokeWidth: 1 },
  blocks: { stroke: "#f97316", strokeWidth: 2 },
  enables: { stroke: "#22c55e", strokeWidth: 2 },
  dependency: { stroke: "#94a3b8", strokeDasharray: "4 2", strokeWidth: 1 },
  constrains: { stroke: "#ef4444", strokeDasharray: "4 2", strokeWidth: 1 },
  default: { stroke: "#94a3b8", strokeWidth: 1 },
};

// Map node types to ELK layer partitions (lower = higher position)
export const LAYER_ORDER: Record<string, number> = {
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
  routine: 7,
  knowledge_entry: 1,
};

// Edge kinds that should have arrowhead markers
export const DIRECTED_EDGE_KINDS = new Set([
  "lineage",
  "blocks",
  "enables",
]);

// All filterable node types (shown in toolbar)
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
