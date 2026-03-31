import { NODE_COLORS, EDGE_STYLES } from "@/components/graph/graph-constants";

export { NODE_COLORS, EDGE_STYLES };

export const REACTION_MARKS = {
  agree: { icon: "✓", label: "Agree" },
  question: { icon: "?", label: "Question" },
  flag: { icon: "⚑", label: "Flag" },
  star: { icon: "★", label: "Star" },
} as const;

export type ReactionType = keyof typeof REACTION_MARKS;

export const BOARD_NODE_WIDTH = 320;
export const BOARD_NODE_HEIGHT = 140;

export const NODE_TYPE_LABELS: Record<string, string> = {
  insight: "Insight",
  decision: "Decision",
  strategy: "Strategy",
  requirement: "Requirement",
  design_node: "Design",
  architecture_node: "Architecture",
  task: "Task",
  learning: "Learning",
  source_ref: "Source",
};

export const AGENT_ICONS: Record<string, string> = {
  researcher: "🔬",
  strategist: "🎯",
  architect: "🏗️",
  designer: "🎨",
  memory_agent: "🧠",
};

export const PRESENCE_COLORS = [
  "#3b82f6",
  "#ef4444",
  "#22c55e",
  "#f59e0b",
  "#8b5cf6",
  "#ec4899",
  "#14b8a6",
  "#f97316",
];
