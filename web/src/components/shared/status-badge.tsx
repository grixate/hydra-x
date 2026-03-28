import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";

const statusStyles: Record<string, string> = {
  active: "bg-emerald-100 text-emerald-800",
  accepted: "bg-emerald-100 text-emerald-800",
  done: "bg-emerald-100 text-emerald-800",
  draft: "bg-zinc-100 text-zinc-600",
  backlog: "bg-zinc-100 text-zinc-600",
  pending: "bg-amber-100 text-amber-800",
  pending_review: "bg-amber-100 text-amber-800",
  ready: "bg-sky-100 text-sky-800",
  in_progress: "bg-yellow-100 text-yellow-800",
  review: "bg-orange-100 text-orange-800",
  superseded: "bg-zinc-100 text-zinc-400 line-through",
  archived: "bg-zinc-100 text-zinc-400",
  suspended: "bg-zinc-100 text-zinc-400",
  paused: "bg-zinc-100 text-zinc-500",
};

const priorityStyles: Record<string, string> = {
  critical: "bg-red-100 text-red-800",
  high: "bg-orange-100 text-orange-800",
  medium: "bg-zinc-100 text-zinc-600",
  low: "bg-zinc-50 text-zinc-400",
};

interface StatusBadgeProps {
  status: string;
  className?: string;
}

export function StatusBadge({ status, className }: StatusBadgeProps) {
  return (
    <Badge
      variant="secondary"
      className={cn(
        "text-[9px] font-medium",
        statusStyles[status],
        className,
      )}
    >
      {status.replace(/_/g, " ")}
    </Badge>
  );
}

interface PriorityBadgeProps {
  priority: string;
  className?: string;
}

export function PriorityBadge({ priority, className }: PriorityBadgeProps) {
  return (
    <Badge
      variant="secondary"
      className={cn(
        "text-[9px] font-medium",
        priorityStyles[priority],
        className,
      )}
    >
      {priority}
    </Badge>
  );
}
