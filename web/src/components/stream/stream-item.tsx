import type { StreamItem as StreamItemType } from "@/lib/api";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { NodeTypeIcon, nodeTypeLabel } from "@/components/shared/node-type-icon";
import { StatusBadge } from "@/components/shared/status-badge";
import { cn } from "@/lib/utils";
import { relativeLabel } from "@/lib/utils";
import { Eye, Check, X, AlertTriangle } from "lucide-react";

interface StreamItemProps {
  item: StreamItemType;
  onNavigate?: (nodeType: string, nodeId: number) => void;
  onAction?: (action: string, item: StreamItemType) => void;
}

export function StreamItem({ item, onNavigate, onAction }: StreamItemProps) {
  const isAction = item.urgency === "action";
  const isEmerging = item.urgency === "emerging";

  return (
    <Card
      className={cn(
        "cursor-pointer transition-all hover:shadow-md",
        isAction && "border-l-4 border-l-orange-400",
        isEmerging && "opacity-80",
      )}
      onClick={() => onNavigate?.(item.node_type, item.node_id)}
    >
      <CardContent className="p-4 space-y-3">
        {/* Header: type icon + label + status + time */}
        <div className="flex items-center justify-between gap-2">
          <div className="flex items-center gap-2">
            <NodeTypeIcon nodeType={item.node_type} className="h-4 w-4 text-muted-foreground" />
            <span className="text-xs text-muted-foreground">
              {nodeTypeLabel(item.node_type)}
            </span>
            {typeof item.metadata?.status === "string" && (
              <StatusBadge status={item.metadata.status} />
            )}
          </div>
          <span className="text-xs text-muted-foreground">
            {relativeLabel(item.timestamp)}
          </span>
        </div>

        {/* Title */}
        <p className="text-sm font-semibold leading-snug">{item.title}</p>

        {/* Body excerpt */}
        {item.summary && (
          <p className="text-sm text-muted-foreground line-clamp-2">
            {item.summary}
          </p>
        )}

        {/* Action row */}
        <div
          className="flex items-center justify-between pt-1"
          onClick={(e) => e.stopPropagation()}
        >
          <Button
            variant="ghost"
            size="sm"
            className="text-xs h-7"
            onClick={() => onNavigate?.(item.node_type, item.node_id)}
          >
            <Eye className="mr-1 h-3 w-3" />
            View trail
          </Button>

          <div className="flex gap-1">
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
            {item.category === "insight_created" && isAction && (
              <>
                <Button
                  variant="default"
                  size="sm"
                  className="text-xs h-7"
                  onClick={() => onAction?.("accept", item)}
                >
                  <Check className="mr-1 h-3 w-3" /> Accept
                </Button>
                <Button
                  variant="ghost"
                  size="sm"
                  className="text-xs h-7"
                  onClick={() => onAction?.("reject", item)}
                >
                  <X className="h-3 w-3" />
                </Button>
              </>
            )}
            {item.category === "decision_gate" && (
              <Button
                variant="default"
                size="sm"
                className="text-xs h-7"
                onClick={() => onAction?.("approve", item)}
              >
                <Check className="mr-1 h-3 w-3" /> Approve
              </Button>
            )}
            {isEmerging && (
              <Button
                variant="ghost"
                size="sm"
                className="text-xs h-7"
                onClick={() => onAction?.("dismiss", item)}
              >
                Dismiss
              </Button>
            )}
          </div>
        </div>
      </CardContent>
    </Card>
  );
}
