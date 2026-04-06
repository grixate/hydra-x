import { useState, useEffect } from "react";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { NodeTypeIcon, nodeTypeLabel } from "@/components/shared/node-type-icon";
import { NODE_COLORS } from "./board-constants";
import { api, type TrailNode, type TrailChainNode } from "@/lib/api";
import { ArrowDown } from "lucide-react";

type BoardInlineTrailProps = {
  projectId: number;
  nodeType: string;
  nodeId: number;
};

type TrailData = {
  center: TrailNode;
  upstream: TrailChainNode[];
  downstream: TrailChainNode[];
};

export function BoardInlineTrail({ projectId, nodeType, nodeId }: BoardInlineTrailProps) {
  const [data, setData] = useState<TrailData | null>(null);
  const [error, setError] = useState(false);

  useEffect(() => {
    let cancelled = false;

    api
      .getTrail(projectId, nodeType, nodeId)
      .then((result) => {
        if (cancelled) return;
        setData({
          center: result.center,
          upstream: result.upstream ?? [],
          downstream: result.downstream ?? [],
        });
      })
      .catch(() => {
        if (!cancelled) setError(true);
      });

    return () => {
      cancelled = true;
    };
  }, [projectId, nodeType, nodeId]);

  if (error) {
    return (
      <Card className="my-2 border-dashed opacity-60">
        <CardContent className="px-4 py-3 text-xs text-muted-foreground">
          Trail not found: {nodeType}#{nodeId}
        </CardContent>
      </Card>
    );
  }

  if (!data) {
    return (
      <Card className="my-2 animate-pulse">
        <CardContent className="px-4 py-3">
          <div className="h-4 w-48 rounded bg-muted" />
          <div className="mt-2 h-20 w-full rounded bg-muted" />
        </CardContent>
      </Card>
    );
  }

  // Build chain: upstream → center → downstream
  const chain: Array<{ type: string; id: number; title: string; status: string; kind?: string }> = [];

  // Upstream (reversed so root is at top)
  for (const node of [...data.upstream].reverse()) {
    chain.push({
      type: node.node_type,
      id: node.node_id,
      title: node.title,
      status: node.status,
      kind: node.edge_kind,
    });
  }

  // Center
  chain.push({
    type: data.center.node_type,
    id: data.center.node_id,
    title: data.center.title,
    status: data.center.status,
  });

  // Downstream
  for (const node of data.downstream) {
    chain.push({
      type: node.node_type,
      id: node.node_id,
      title: node.title,
      status: node.status,
      kind: node.edge_kind,
    });
  }

  const centerIdx = data.upstream.length;

  return (
    <div className="my-3 space-y-0">
      {chain.map((node, i) => {
        const isCenter = i === centerIdx;
        const borderColor = NODE_COLORS[node.type] ?? NODE_COLORS.default;

        return (
          <div key={`${node.type}-${node.id}-${i}`}>
            {/* Connecting line */}
            {i > 0 && (
              <div className="flex items-center justify-center py-0.5">
                <ArrowDown className="h-3 w-3 text-muted-foreground/50" />
              </div>
            )}

            {/* Node chip */}
            <div
              className={`flex items-center gap-2 rounded-lg border px-3 py-2 text-xs ${
                isCenter ? "bg-muted/80 ring-1 ring-ring/20" : ""
              }`}
              style={{ borderLeftWidth: 3, borderLeftColor: borderColor }}
            >
              <NodeTypeIcon nodeType={node.type} className="h-3 w-3 text-muted-foreground shrink-0" />
              <span className="font-medium truncate">{node.title}</span>
              <Badge variant="outline" className="text-[8px] px-1 py-0 h-3.5 ml-auto shrink-0">
                {node.status}
              </Badge>
            </div>
          </div>
        );
      })}
    </div>
  );
}
