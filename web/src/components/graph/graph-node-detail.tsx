import { useEffect, useMemo, useState } from "react";
import type { GraphData, GraphDataNode, SourceReference } from "@/types";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { NODE_COLORS } from "./graph-constants";
import { api } from "@/lib/api";
import {
  Check,
  Compass,
  FileText,
  Focus,
  GitBranch,
  MessageSquare,
  Route,
  X,
} from "lucide-react";

interface GraphNodeDetailProps {
  node: GraphDataNode;
  graphData: GraphData;
  projectId: number;
  nodeScreenPosition: { x: number; y: number };
  containerWidth: number;
  containerHeight: number;
  onClose: () => void;
  onOpenTrail: (nodeType: string, nodeId: number) => void;
  onOpenWhy: (nodeType: string, nodeId: number) => void;
  onHighlightConnections: (nodeIds: string[]) => void;
  onChatAbout: (node: GraphDataNode) => void;
  onShowLineage?: (nodeId: string) => void;
  onOpenSource?: (sourceId: number) => void;
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
  onOpenWhy,
  onHighlightConnections,
  onChatAbout,
  onShowLineage,
  onOpenSource,
  isInChatContext = false,
}: GraphNodeDetailProps) {
  // Source-as-Data §6 — surface source references for the selected node.
  const [sourceRefs, setSourceRefs] = useState<SourceReference[]>([]);

  useEffect(() => {
    let cancelled = false;
    // Only fetch when there's at least one reference to show (cheap early-out).
    if ((node.source_reference_count ?? 0) === 0) {
      setSourceRefs([]);
      return;
    }
    api
      .getNodeSourceReferences(projectId, node.node_type, node.node_id)
      .then((refs) => {
        if (!cancelled) setSourceRefs(refs);
      })
      .catch(() => {
        if (!cancelled) setSourceRefs([]);
      });
    return () => {
      cancelled = true;
    };
  }, [projectId, node.node_type, node.node_id, node.source_reference_count]);
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
            variant="outline"
            size="sm"
            className="h-6 shrink-0 gap-1 px-2 text-[10px]"
            onClick={() => onOpenWhy(node.node_type, node.node_id)}
            aria-label="Explain why this exists"
          >
            <Compass className="h-3 w-3" />
            Why?
          </Button>
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

        {/* Sources — Source-as-Data §6. Shows Library sources referenced by
            this node. Click a source to open it in the Library. */}
        {sourceRefs.length > 0 && (
          <div className="mt-3 rounded-md border bg-muted/30 p-2">
            <div className="mb-1.5 flex items-center gap-1.5 text-[10px] font-semibold uppercase tracking-wide text-muted-foreground">
              <FileText className="h-3 w-3" />
              Sources ({sourceRefs.length})
            </div>
            <div className="space-y-1">
              {sourceRefs.slice(0, 5).map((ref) => (
                <button
                  key={ref.id}
                  type="button"
                  onClick={() => onOpenSource?.(ref.source_id)}
                  className="flex w-full items-start gap-1.5 rounded px-1.5 py-1 text-left text-[11px] hover:bg-muted"
                  title={ref.excerpt ?? undefined}
                >
                  <FileText className="mt-0.5 h-3 w-3 shrink-0 text-muted-foreground" />
                  <div className="min-w-0 flex-1">
                    <p className="truncate font-medium">{ref.source?.title ?? `Source #${ref.source_id}`}</p>
                    <p className="text-[9px] text-muted-foreground">
                      {ref.relationship.replace(/_/g, " ")}
                      {ref.confidence ? ` · ${ref.confidence}` : ""}
                    </p>
                  </div>
                </button>
              ))}
              {sourceRefs.length > 5 && (
                <p className="px-1.5 py-0.5 text-[10px] text-muted-foreground">
                  +{sourceRefs.length - 5} more
                </p>
              )}
            </div>
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
          {onShowLineage && (
            <Button
              variant="outline"
              size="sm"
              className="h-7 text-[11px]"
              onClick={() => onShowLineage(node.id)}
              title="Enter Lineage View (keyboard: L)"
            >
              <GitBranch className="mr-1 h-3 w-3" />
              Lineage
            </Button>
          )}
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
