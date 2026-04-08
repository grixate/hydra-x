import { motion } from "motion/react";
import type { StreamItem } from "@/lib/api";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { nodeTypeLabel } from "@/components/shared/node-type-icon";
import { NODE_COLORS } from "@/components/graph/graph-constants";
import { cn, relativeLabel } from "@/lib/utils";
import { Check, X, Eye } from "lucide-react";

interface StreamActionCardProps {
  item: StreamItem;
  index?: number;
  onNavigate?: (nodeType: string, nodeId: number) => void;
  onAction?: (action: string, item: StreamItem) => void;
}

function borderAccent(item: StreamItem): string {
  if (item.category === "flag" && item.metadata?.flag_type === "contradicted") {
    return "border-l-destructive";
  }
  if (item.category === "decision_gate") {
    return "border-l-amber-500";
  }
  return "border-l-primary";
}

export function StreamActionCard({ item, index = 0, onNavigate, onAction }: StreamActionCardProps) {
  const dotColor = NODE_COLORS[item.node_type] ?? NODE_COLORS.default;
  const status = item.metadata?.status as string | undefined;

  return (
    <motion.div
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: -8 }}
      transition={{
        duration: 0.35,
        delay: index * 0.08,
        ease: [0.25, 0.46, 0.45, 0.94],
      }}
      className={cn(
        "rounded-xl border border-l-3 bg-card p-5 space-y-3",
        borderAccent(item),
      )}
    >
      {/* Header: dot + type + status + time */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <div
            className="h-2 w-2 shrink-0 rounded-full"
            style={{ backgroundColor: dotColor }}
          />
          <span className="text-xs text-muted-foreground">
            {nodeTypeLabel(item.node_type)}
          </span>
          {status && (
            <Badge variant="outline" className="text-[9px] px-1.5 py-0 h-4">
              {status.replace(/_/g, " ")}
            </Badge>
          )}
        </div>
        <span className="text-xs text-muted-foreground">
          {relativeLabel(item.timestamp)}
        </span>
      </div>

      {/* Title */}
      <p
        className="text-base font-medium leading-snug cursor-pointer hover:underline"
        onClick={() => onNavigate?.(item.node_type, item.node_id)}
      >
        {item.title}
      </p>

      {/* Narrative */}
      {item.narrative && (
        <p className="text-sm text-muted-foreground leading-relaxed">
          {item.narrative}
        </p>
      )}

      {/* Actions */}
      <div className="flex items-center justify-end gap-2 pt-1">
        <Button
          variant="ghost"
          size="sm"
          className="text-xs h-7 px-2"
          onClick={() => onNavigate?.(item.node_type, item.node_id)}
        >
          <Eye className="mr-1 h-3 w-3" />
          Open trail
        </Button>

        {item.category === "flag" && (
          <Button
            variant="outline"
            size="sm"
            className="text-xs h-7"
            onClick={() => onAction?.("acknowledge", item)}
          >
            Acknowledge
          </Button>
        )}

        {item.category === "insight_created" && (
          <>
            <Button
              variant="ghost"
              size="sm"
              className="text-xs h-7 text-muted-foreground"
              onClick={() => onAction?.("reject", item)}
            >
              <X className="h-3 w-3" />
            </Button>
            <Button
              variant="default"
              size="sm"
              className="text-xs h-7"
              onClick={() => onAction?.("accept", item)}
            >
              <Check className="mr-1 h-3 w-3" /> Accept
            </Button>
          </>
        )}

        {item.category === "decision_gate" && (
          <>
            <Button
              variant="ghost"
              size="sm"
              className="text-xs h-7 text-muted-foreground"
              onClick={() => onAction?.("reject", item)}
            >
              <X className="h-3 w-3" />
            </Button>
            <Button
              variant="default"
              size="sm"
              className="text-xs h-7"
              onClick={() => onAction?.("approve", item)}
            >
              <Check className="mr-1 h-3 w-3" /> Approve
            </Button>
          </>
        )}

        {item.category === "requirement_created" && (
          <Button
            variant="default"
            size="sm"
            className="text-xs h-7"
            onClick={() => onAction?.("review", item)}
          >
            Review
          </Button>
        )}

        {item.category === "simulation_proposed" && (
          <>
            <Button
              variant="ghost"
              size="sm"
              className="text-xs h-7 text-muted-foreground"
              onClick={() => onAction?.("reject", item)}
            >
              <X className="h-3 w-3" />
            </Button>
            <Button
              variant="default"
              size="sm"
              className="text-xs h-7"
              onClick={() => onAction?.("approve", item)}
            >
              <Check className="mr-1 h-3 w-3" /> Approve
            </Button>
          </>
        )}

        {item.category === "knowledge_proposed" && (
          <>
            <Button
              variant="ghost"
              size="sm"
              className="text-xs h-7 text-muted-foreground"
              onClick={() => onAction?.("reject", item)}
            >
              <X className="h-3 w-3" />
            </Button>
            <Button
              variant="default"
              size="sm"
              className="text-xs h-7"
              onClick={() => onAction?.("accept", item)}
            >
              <Check className="mr-1 h-3 w-3" /> Accept
            </Button>
          </>
        )}
      </div>
    </motion.div>
  );
}
