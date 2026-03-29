import type { StreamItem as StreamItemType } from "@/lib/api";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { NodeTypeIcon, nodeTypeLabel } from "@/components/shared/node-type-icon";
import { ConnectionChips } from "@/components/shared/connection-chip";
import { cn } from "@/lib/utils";
import { relativeLabel } from "@/lib/utils";
import { Eye, Check, X } from "lucide-react";

interface StreamItemProps {
  item: StreamItemType;
  onNavigate?: (nodeType: string, nodeId: number) => void;
  onNavigateGraph?: (nodeType: string, nodeId: number, filterType: string) => void;
  onAction?: (action: string, item: StreamItemType) => void;
}

const flagTypeLabels: Record<string, string> = {
  needs_review: "Needs review",
  contradicted: "Contradicted",
  stale: "Stale",
  orphaned: "Orphaned",
  confidence_decayed: "Confidence decayed",
};

export function StreamItem({ item, onNavigate, onNavigateGraph, onAction }: StreamItemProps) {
  const isAction = item.urgency === "action";
  const isEmerging = item.urgency === "emerging";
  const flagType = item.metadata?.flag_type as string | undefined;

  return (
    <Card
      className={cn(
        "transition-all hover:shadow-md",
        isAction && "border-l-4 border-l-orange-400",
        isEmerging && "border-l-4 border-l-slate-300",
      )}
    >
      <CardContent className="p-4 space-y-2.5">
        {/* Row 1: type + status + timestamp */}
        <div className="flex items-center justify-between gap-2">
          <div className="flex items-center gap-1.5">
            <NodeTypeIcon nodeType={item.node_type} className="h-3.5 w-3.5 text-muted-foreground" />
            <span className="text-[11px] font-medium text-muted-foreground">
              {nodeTypeLabel(item.node_type)}
            </span>
            {typeof item.metadata?.status === "string" && (
              <Badge variant="outline" className="text-[9px] px-1.5 py-0 h-4">
                {(item.metadata.status as string).replace(/_/g, " ")}
              </Badge>
            )}
            {flagType && (
              <Badge variant="destructive" className="text-[9px] px-1.5 py-0 h-4">
                {flagTypeLabels[flagType] ?? flagType}
              </Badge>
            )}
          </div>
          <span className="shrink-0 text-[11px] text-muted-foreground">
            {relativeLabel(item.timestamp)}
          </span>
        </div>

        {/* Row 2: title */}
        <p
          className="text-sm font-semibold leading-snug cursor-pointer hover:underline"
          onClick={() => onNavigate?.(item.node_type, item.node_id)}
        >
          {item.title}
        </p>

        {/* Row 3: body excerpt */}
        {item.summary && (
          <p className="text-[13px] leading-relaxed text-muted-foreground line-clamp-3">
            {item.summary}
          </p>
        )}

        {/* Row 4: connection chips */}
        {item.connections && Object.keys(item.connections).length > 0 && (
          <ConnectionChips
            connections={item.connections}
            onChipClick={(filterType) =>
              onNavigateGraph?.(item.node_type, item.node_id, filterType)
            }
          />
        )}

        {/* Row 5: actions */}
        <div
          className="flex items-center justify-between pt-1 border-t"
          onClick={(e) => e.stopPropagation()}
        >
          <Button
            variant="ghost"
            size="sm"
            className="text-xs h-7 px-2"
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
                  className="text-xs h-7 text-muted-foreground"
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
            {item.category === "requirement_created" && isAction && (
              <Button
                variant="default"
                size="sm"
                className="text-xs h-7"
                onClick={() => onAction?.("review", item)}
              >
                Review
              </Button>
            )}
            {isEmerging && (
              <Button
                variant="ghost"
                size="sm"
                className="text-xs h-7 text-muted-foreground"
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
