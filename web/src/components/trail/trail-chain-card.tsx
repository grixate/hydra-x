import { motion } from "motion/react";
import type { TrailChainNode } from "@/lib/api";
import { Badge } from "@/components/ui/badge";
import { NodeTypeIcon, nodeTypeLabel } from "@/components/shared/node-type-icon";
import { NODE_COLORS } from "@/components/graph/graph-constants";
import { cn, relativeLabel } from "@/lib/utils";

interface TrailChainCardProps {
  node: TrailChainNode;
  index?: number;
  onClick: (nodeType: string, nodeId: number) => void;
}

export function TrailChainCard({ node, index = 0, onClick }: TrailChainCardProps) {
  const isDraft = node.status === "draft";
  const dotColor = NODE_COLORS[node.node_type] ?? NODE_COLORS.default;

  // Build connection footer parts
  const connections: string[] = [];
  if (node.upstream_count != null && node.upstream_count > 0) {
    connections.push(`↑ ${node.upstream_count}`);
  }
  if (node.downstream_count != null && node.downstream_count > 0) {
    connections.push(`↓ ${node.downstream_count}`);
  }

  return (
    <motion.div
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{
        duration: 0.3,
        delay: index * 0.06,
        ease: [0.25, 0.46, 0.45, 0.94],
      }}
      className={cn(
        "rounded-xl border bg-card px-5 py-4 space-y-2 cursor-pointer transition-colors hover:bg-muted/30",
        isDraft && "border-dashed",
      )}
      onClick={() => onClick(node.node_type, node.node_id)}
    >
      {/* Header: icon + type + status + date */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <div
            className="h-2 w-2 shrink-0 rounded-full"
            style={{ backgroundColor: dotColor }}
          />
          <NodeTypeIcon nodeType={node.node_type} className="h-3.5 w-3.5 text-muted-foreground" />
          <span className="text-xs text-muted-foreground">
            {nodeTypeLabel(node.node_type)}
          </span>
          {node.status && (
            <Badge variant="outline" className="text-[9px] px-1.5 py-0 h-4">
              {node.status.replace(/_/g, " ")}
            </Badge>
          )}
        </div>
        {node.updated_at && (
          <span className="text-xs text-muted-foreground">
            {relativeLabel(node.updated_at)}
          </span>
        )}
      </div>

      {/* Title */}
      <p className="text-sm font-medium leading-snug">
        {node.title || `${node.node_type}#${node.node_id}`}
      </p>

      {/* Body excerpt */}
      {node.summary && (
        <p className="text-sm text-muted-foreground line-clamp-3 leading-relaxed">
          {node.summary}
        </p>
      )}

      {/* Connection footer */}
      {connections.length > 0 && (
        <p className="text-xs text-muted-foreground pt-1">
          {connections.join("    ")}
        </p>
      )}
    </motion.div>
  );
}
