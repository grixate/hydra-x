import {
  FileStack,
  Telescope,
  Scale,
  Compass,
  ListChecks,
  PenTool,
  Blocks,
  CheckSquare,
  GraduationCap,
  Timer,
  Lock,
  BookOpen,
  HelpCircle,
} from "lucide-react";
import type { LucideIcon } from "lucide-react";

const iconMap: Record<string, LucideIcon> = {
  signal: FileStack,
  source: FileStack,
  insight: Telescope,
  decision: Scale,
  strategy: Compass,
  requirement: ListChecks,
  design_node: PenTool,
  architecture_node: Blocks,
  task: CheckSquare,
  learning: GraduationCap,
  routine: Timer,
  constraint: Lock,
  knowledge_entry: BookOpen,
};

interface NodeTypeIconProps {
  nodeType: string;
  className?: string;
  size?: number;
}

export function NodeTypeIcon({
  nodeType,
  className = "h-4 w-4",
  size,
}: NodeTypeIconProps) {
  const Icon = iconMap[nodeType] ?? HelpCircle;
  return <Icon className={className} size={size} />;
}

export function nodeTypeLabel(nodeType: string): string {
  const labels: Record<string, string> = {
    signal: "Signal",
    source: "Source",
    insight: "Insight",
    decision: "Decision",
    strategy: "Strategy",
    requirement: "Requirement",
    design_node: "Design",
    architecture_node: "Architecture",
    task: "Task",
    learning: "Learning",
    routine: "Routine",
    constraint: "Constraint",
    knowledge_entry: "Knowledge",
  };
  return labels[nodeType] ?? nodeType;
}
