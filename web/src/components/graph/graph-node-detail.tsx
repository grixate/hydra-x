import { useMemo } from "react";
import type { GraphData, GraphDataNode } from "@/types";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { NODE_COLORS } from "./graph-constants";
import { X, Route, Focus, MessageSquare, Check } from "lucide-react";

interface GraphNodeDetailProps {
  node: GraphDataNode;
  graphData: GraphData;
  projectId: number;
  nodeScreenPosition: { x: number; y: number };
  containerWidth: number;
  containerHeight: number;
  onClose: () => void;
  onOpenTrail: (nodeType: string, nodeId: number) => void;
  onHighlightConnections: (nodeIds: string[]) => void;
  onChatAbout: (node: GraphDataNode) => void;
  isInChatContext?: boolean;
}

export function GraphNodeDetail({
  node,
  graphData,
  projectId,
  nodeScreenPosition,
  containerWidth,
  containerHeight,
  onClose,
  onOpenTrail,
  onHighlightConnections,
  onChatAbout,
  isInChatContext = false,
}: GraphNodeDetailProps) {
  const { upstreamNodes, downstreamNodes, connectedIds } = useMemo(() => {
    const up: GraphDataNode[] = [];
    const down: GraphDataNode[] = [];
    const ids: string[] = [];

    for (const edge of graphData.edges) {
      if (edge.source === node.id) {
        const target = graphData.nodes.find((n) => n.id === edge.target);
        if (target) {
          down.push(target);
          ids.push(target.id);
        }
      } else if (edge.target === node.id) {
        const source = graphData.nodes.find((n) => n.id === edge.source);
        if (source) {
          up.push(source);
          ids.push(source.id);
        }
      }
    }

    return { upstreamNodes: up, downstreamNodes: down, connectedIds: ids };
  }, [node.id, graphData]);

  const flags = graphData.flags.filter((f) => f.node_id === node.id);
  const color = NODE_COLORS[node.node_type] ?? NODE_COLORS.default;

  // Position: near the node, avoiding edges and chat card area (bottom-right)
  const popoverWidth = 320;
  const popoverHeight = 400;
  const chatCardRight = 420 + 32; // card width + padding

  let left: number | undefined;
  let right: number | undefined;
  let top: number;

  if (nodeScreenPosition.x < containerWidth / 2) {
    // Node is in left half → popover to the right
    left = nodeScreenPosition.x + 160;
  } else {
    // Node is in right half → popover to the left
    left = nodeScreenPosition.x - popoverWidth - 20;
  }

  // Avoid overlapping chat card in bottom-right
  if (left + popoverWidth > containerWidth - chatCardRight && nodeScreenPosition.y > containerHeight * 0.4) {
    left = Math.max(16, containerWidth - chatCardRight - popoverWidth - 16);
  }

  top = Math.max(60, Math.min(nodeScreenPosition.y - 40, containerHeight - popoverHeight - 20));

  // Group upstream by type
  const upByType = groupByType(upstreamNodes);
  const downByType = groupByType(downstreamNodes);

  return (
    <Card
      className="absolute z-[25] w-[320px] shadow-lg rounded-xl"
      style={{ left, top }}
    >
      <CardContent className="p-4">
        {/* Header */}
        <div className="flex items-start justify-between gap-2">
          <div className="flex items-center gap-2">
            <span
              className="h-3 w-3 shrink-0 rounded-full"
              style={{ backgroundColor: color }}
            />
            <span className="text-xs text-muted-foreground">
              {node.node_type.replace(/_/g, " ")}
            </span>
            <Badge
              variant={
                node.status === "active" || node.status === "accepted"
                  ? "default"
                  : "secondary"
              }
              className="text-[10px]"
            >
              {node.status}
            </Badge>
          </div>
          <Button
            variant="ghost"
            size="icon"
            className="h-5 w-5 shrink-0"
            onClick={onClose}
          >
            <X className="h-3 w-3" />
          </Button>
        </div>

        {/* Title */}
        <h3 className="mt-2 text-sm font-semibold leading-tight">
          {node.title}
        </h3>

        {/* Body */}
        {node.body && (
          <div className="mt-2 max-h-48 overflow-y-auto">
            <p className="text-xs text-muted-foreground leading-relaxed">
              {node.body}
            </p>
          </div>
        )}

        {/* Connection summary */}
        <div className="mt-3 flex items-center gap-3 text-xs">
          {node.upstream_count > 0 && (
            <button
              type="button"
              className="text-muted-foreground hover:text-foreground transition-colors"
              onClick={() =>
                onHighlightConnections(upstreamNodes.map((n) => n.id))
              }
            >
              ↑{node.upstream_count}{" "}
              {summarizeTypes(upByType)}
            </button>
          )}
          {node.downstream_count > 0 && (
            <button
              type="button"
              className="text-muted-foreground hover:text-foreground transition-colors"
              onClick={() =>
                onHighlightConnections(downstreamNodes.map((n) => n.id))
              }
            >
              ↓{node.downstream_count}{" "}
              {summarizeTypes(downByType)}
            </button>
          )}
          {node.flag_count > 0 && (
            <span className="text-amber-600">⚑{node.flag_count}</span>
          )}
        </div>

        {/* Flags */}
        {flags.length > 0 && (
          <div className="mt-2 space-y-1">
            {flags.map((flag) => (
              <div
                key={flag.id}
                className="rounded bg-destructive/10 px-2 py-1 text-[10px] text-destructive"
              >
                {flag.flag_type}: {flag.reason}
              </div>
            ))}
          </div>
        )}

        {/* Actions */}
        <div className="mt-3 flex flex-wrap gap-1.5">
          <Button
            variant="outline"
            size="sm"
            className="h-7 text-[11px]"
            onClick={() => onOpenTrail(node.node_type, node.node_id)}
          >
            <Route className="mr-1 h-3 w-3" />
            Open trail
          </Button>
          <Button
            variant={isInChatContext ? "default" : "outline"}
            size="sm"
            className="h-7 text-[11px]"
            onClick={() => onChatAbout(node)}
          >
            {isInChatContext ? (
              <>
                <Check className="mr-1 h-3 w-3" />
                In chat context
              </>
            ) : (
              <>
                <MessageSquare className="mr-1 h-3 w-3" />
                Chat about this
              </>
            )}
          </Button>
          <Button
            variant="outline"
            size="sm"
            className="h-7 text-[11px]"
            onClick={() =>
              onHighlightConnections([node.id, ...connectedIds])
            }
          >
            <Focus className="mr-1 h-3 w-3" />
            Focus
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}

function groupByType(nodes: GraphDataNode[]): Record<string, number> {
  const counts: Record<string, number> = {};
  for (const n of nodes) {
    counts[n.node_type] = (counts[n.node_type] || 0) + 1;
  }
  return counts;
}

function summarizeTypes(byType: Record<string, number>): string {
  const entries = Object.entries(byType);
  if (entries.length === 0) return "";
  if (entries.length === 1) {
    const [type, count] = entries[0];
    return type.replace(/_/g, " ") + (count > 1 ? "s" : "");
  }
  return entries
    .slice(0, 2)
    .map(([type]) => type.replace(/_/g, " "))
    .join(", ");
}
