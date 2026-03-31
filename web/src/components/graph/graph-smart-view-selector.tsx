import { cn } from "@/lib/utils";
import type { SmartView } from "./graph-smart-views";
import { Zap, BarChart3, GitBranch, Clock, AlertTriangle, Link2, Globe } from "lucide-react";

const VIEWS: Array<{
  id: SmartView | null;
  label: string;
  description: string;
  icon: typeof Zap;
}> = [
  {
    id: "next_actions",
    label: "Next actions",
    description: "Where to focus effort",
    icon: Zap,
  },
  {
    id: "coverage",
    label: "Coverage",
    description: "Evidence strength map",
    icon: BarChart3,
  },
  {
    id: "flow",
    label: "Flow",
    description: "Lineage completeness",
    icon: GitBranch,
  },
  {
    id: "stale",
    label: "Stale",
    description: "Needs refreshing",
    icon: Clock,
  },
  {
    id: "contradictions",
    label: "Contradictions",
    description: "Conflicting nodes",
    icon: AlertTriangle,
  },
  {
    id: "orphans",
    label: "Orphans",
    description: "Missing connections",
    icon: Link2,
  },
  {
    id: null,
    label: "All nodes",
    description: "Full graph, no filter",
    icon: Globe,
  },
];

interface GraphSmartViewSelectorProps {
  active: SmartView | null;
  onChange: (view: SmartView | null) => void;
  nodeCount: number;
}

export function GraphSmartViewSelector({
  active,
  onChange,
  nodeCount,
}: GraphSmartViewSelectorProps) {
  return (
    <div className="flex flex-col gap-1 pointer-events-auto">
      {VIEWS.map((view) => {
        const isActive = view.id === active;
        const Icon = view.icon;

        return (
          <button
            key={view.id ?? "all"}
            type="button"
            onClick={() => onChange(view.id)}
            className={cn(
              "flex w-[200px] items-start gap-2.5 rounded-lg border px-3 py-2 text-left transition-all",
              isActive
                ? "bg-primary text-primary-foreground border-primary shadow-md"
                : "bg-background/80 backdrop-blur-sm border-border hover:bg-muted/80",
            )}
          >
            <Icon
              className={cn(
                "mt-0.5 h-3.5 w-3.5 shrink-0",
                isActive ? "text-primary-foreground" : "text-muted-foreground",
              )}
            />
            <div className="min-w-0">
              <div className="text-[13px] font-medium leading-tight">
                {view.label}
              </div>
              <div
                className={cn(
                  "text-[11px] leading-tight",
                  isActive
                    ? "text-primary-foreground/80"
                    : "text-muted-foreground",
                )}
              >
                {view.description}
              </div>
            </div>
          </button>
        );
      })}
    </div>
  );
}
