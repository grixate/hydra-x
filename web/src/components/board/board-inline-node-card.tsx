import { useState, useEffect } from "react";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { NodeTypeIcon, nodeTypeLabel } from "@/components/shared/node-type-icon";
import { NODE_COLORS } from "./board-constants";
import { api } from "@/lib/api";
import type { TrailNode } from "@/lib/api";
import { ExternalLink } from "lucide-react";

type BoardInlineNodeCardProps = {
  projectId: number;
  nodeType: string;
  nodeId: number;
  onSelectContext?: (nodeType: string, nodeId: number) => void;
};

// Cache with TTL to avoid refetching, but prevent staleness
const NODE_CACHE_TTL_MS = 5 * 60 * 1000; // 5 minutes
const nodeCache = new Map<string, { data: { node: TrailNode; upstream: number; downstream: number }; fetchedAt: number }>();

function getCachedNode(key: string) {
  const entry = nodeCache.get(key);
  if (!entry) return null;
  if (Date.now() - entry.fetchedAt > NODE_CACHE_TTL_MS) {
    nodeCache.delete(key);
    return null;
  }
  return entry.data;
}

export function BoardInlineNodeCard({
  projectId,
  nodeType,
  nodeId,
  onSelectContext,
}: BoardInlineNodeCardProps) {
  const [data, setData] = useState<{
    node: TrailNode;
    upstream: number;
    downstream: number;
  } | null>(null);
  const [error, setError] = useState(false);

  const cacheKey = `${projectId}-${nodeType}-${nodeId}`;

  useEffect(() => {
    const cached = getCachedNode(cacheKey);
    if (cached) {
      setData(cached);
      return;
    }

    let cancelled = false;

    api
      .getTrail(projectId, nodeType, nodeId)
      .then((result) => {
        if (cancelled) return;
        const entry = {
          node: result.center,
          upstream: result.upstream?.length ?? 0,
          downstream: result.downstream?.length ?? 0,
        };
        nodeCache.set(cacheKey, { data: entry, fetchedAt: Date.now() });
        setData(entry);
      })
      .catch(() => {
        if (!cancelled) setError(true);
      });

    return () => {
      cancelled = true;
    };
  }, [projectId, nodeType, nodeId, cacheKey]);

  if (error) {
    return (
      <Card className="my-2 border-dashed opacity-60">
        <CardContent className="px-4 py-3 text-xs text-muted-foreground">
          Node not found: {nodeType}#{nodeId}
        </CardContent>
      </Card>
    );
  }

  if (!data) {
    return (
      <Card className="my-2 animate-pulse">
        <CardContent className="px-4 py-3">
          <div className="h-4 w-48 rounded bg-muted" />
          <div className="mt-2 h-3 w-72 rounded bg-muted" />
        </CardContent>
      </Card>
    );
  }

  const { node, upstream, downstream } = data;
  const borderColor = NODE_COLORS[nodeType] ?? NODE_COLORS.default;

  return (
    <Card
      className="my-2 cursor-pointer transition-shadow hover:shadow-md"
      style={{ borderLeftWidth: 4, borderLeftColor: borderColor }}
      onClick={() => onSelectContext?.(nodeType, nodeId)}
    >
      <CardContent className="px-4 py-3 space-y-1.5">
        {/* Header: type + status */}
        <div className="flex items-center justify-between gap-2">
          <div className="flex items-center gap-1.5">
            <NodeTypeIcon nodeType={nodeType} className="h-3.5 w-3.5 text-muted-foreground" />
            <span className="text-[10px] font-semibold uppercase tracking-wider text-muted-foreground">
              {nodeTypeLabel(nodeType)}
            </span>
            {node.status && (
              <Badge variant="outline" className="text-[9px] px-1.5 py-0 h-4">
                {node.status}
              </Badge>
            )}
          </div>
          <button
            className="text-muted-foreground hover:text-foreground"
            title="Open trail"
            onClick={(e) => {
              e.stopPropagation();
              // Open trail in new tab
              window.open(
                `/projects/${projectId}/graph?node_type=${nodeType}&node_id=${nodeId}`,
                "_blank",
              );
            }}
          >
            <ExternalLink className="h-3 w-3" />
          </button>
        </div>

        {/* Title */}
        <p className="text-sm font-semibold leading-snug">{node.title}</p>

        {/* Body excerpt */}
        {node.body && (
          <p className="text-xs leading-relaxed text-muted-foreground line-clamp-3">
            {node.body}
          </p>
        )}

        {/* Connection summary */}
        {(upstream > 0 || downstream > 0) && (
          <div className="flex gap-3 text-[10px] text-muted-foreground">
            {upstream > 0 && <span>&uarr;{upstream} upstream</span>}
            {downstream > 0 && <span>&darr;{downstream} downstream</span>}
          </div>
        )}
      </CardContent>
    </Card>
  );
}
