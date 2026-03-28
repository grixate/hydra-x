import type { StreamItem as StreamItemType } from "@/lib/api";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";

interface StreamItemProps {
  item: StreamItemType;
  onNavigate?: (nodeType: string, nodeId: number) => void;
}

const categoryIcons: Record<string, string> = {
  flag: "!",
  decision_gate: "?",
  insight_created: "+",
  task_ready: ">",
  contradiction: "x",
  agent_finding: "*",
  status_change: "~",
  simulation_complete: "#",
};

export function StreamItem({ item, onNavigate }: StreamItemProps) {
  return (
    <Card
      className={cn(
        "cursor-pointer transition-colors hover:border-accent",
        item.urgency === "action" && "border-l-2 border-l-accent",
      )}
      onClick={() => onNavigate?.(item.node_type, item.node_id)}
    >
      <CardContent className="flex items-start gap-3 p-3">
        <span className="mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded bg-ink/5 text-[10px] font-bold text-ink-soft">
          {categoryIcons[item.category] ?? "."}
        </span>
        <div className="min-w-0 flex-1">
          <p className="text-sm font-medium leading-tight">{item.title}</p>
          <p className="mt-0.5 text-xs text-ink-soft line-clamp-1">
            {item.summary}
          </p>
        </div>
        <Badge
          variant={item.urgency === "action" ? "default" : "secondary"}
          className="shrink-0 text-[9px]"
        >
          {item.node_type}
        </Badge>
      </CardContent>
    </Card>
  );
}
