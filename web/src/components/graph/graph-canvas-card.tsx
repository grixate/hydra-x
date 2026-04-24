import { Check, GitBranch, MessageSquare, MoreHorizontal, Route, ShieldAlert } from "lucide-react";

import type { GraphDataNode, SourceReference } from "@/types";
import { relativeLabel } from "@/lib/utils";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Separator } from "@/components/ui/separator";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";

import { colorForNode } from "./cosmos-graph-adapter";

export type GraphCanvasCardActions = {
  onAccept: (node: GraphDataNode) => void;
  onChallenge: (node: GraphDataNode) => void;
  onShowLineage: (node: GraphDataNode) => void;
  onOpenTrail: (node: GraphDataNode) => void;
  onChatAbout: (node: GraphDataNode) => void;
};

type GraphCanvasCardProps = {
  node: GraphDataNode;
  sourceRefs: SourceReference[];
  actions: GraphCanvasCardActions;
};

export function GraphCanvasCard({ node, sourceRefs, actions }: GraphCanvasCardProps) {
  const color = colorForNode(node);
  const sourceCount = sourceRefs.length || node.source_reference_count || 0;

  return (
    <Card className="w-[360px] gap-0 overflow-hidden rounded-lg border bg-card/95 py-0 shadow-2xl shadow-black/15 backdrop-blur">
      <CardContent className="p-4">
        <div className="flex items-center gap-2">
          <Badge
            variant="secondary"
            className="h-5 rounded-full px-2 text-[10px] uppercase tracking-[0.08em]"
          >
            {node.node_type.replace(/_/g, " ")}
          </Badge>
          <span className="text-xs text-muted-foreground">
            {sourceCount >= 10 ? "thick evidence" : sourceCount >= 3 ? "emerging evidence" : "thin evidence"}
          </span>
          <span className="ml-auto inline-flex items-center gap-1" aria-hidden="true">
            {Array.from({ length: 5 }).map((_, index) => (
              <span
                key={index}
                className="h-1.5 w-1.5 rounded-full"
                style={{ backgroundColor: index < Math.min(5, sourceCount) ? color : "#CECBF6" }}
              />
            ))}
          </span>
        </div>

        <p className="mt-3 text-[15px] font-semibold leading-snug text-foreground">
          {node.title}
        </p>

        {node.body ? (
          <p className="mt-2 line-clamp-2 text-xs leading-relaxed text-muted-foreground">
            {node.body}
          </p>
        ) : null}

        <div className="mt-3 flex flex-wrap items-center gap-2 text-[11px] text-muted-foreground">
          <span className="inline-flex items-center gap-1">
            <span className="h-1.5 w-1.5 rounded-full" style={{ backgroundColor: color }} />
            {sourceCount} source{sourceCount === 1 ? "" : "s"}
          </span>
          <span>up {node.upstream_count}</span>
          <span>down {node.downstream_count}</span>
          <span>{relativeLabel(node.updated_at)}</span>
          {node.flag_count > 0 ? (
            <span className="inline-flex items-center gap-1 text-amber-600">
              <ShieldAlert className="h-3 w-3" />
              {node.flag_count}
            </span>
          ) : null}
        </div>

        <Separator className="my-3" />

        <div className="space-y-2">
          <div className="text-[10px] font-medium uppercase tracking-[0.12em] text-muted-foreground">
            Evidence chain
          </div>
          <EvidenceRibbon node={node} sourceRefs={sourceRefs} />
        </div>

        <div className="mt-4 flex flex-wrap items-center gap-1.5">
          <Button size="xs" onClick={() => actions.onAccept(node)}>
            <Check className="h-3 w-3" />
            Accept
          </Button>
          <Button size="xs" variant="outline" onClick={() => actions.onChallenge(node)}>
            Challenge
          </Button>
          <Tooltip delayDuration={120}>
            <TooltipTrigger asChild>
              <Button size="icon-xs" variant="outline" onClick={() => actions.onShowLineage(node)}>
                <GitBranch className="h-3 w-3" />
              </Button>
            </TooltipTrigger>
            <TooltipContent>Show lineage</TooltipContent>
          </Tooltip>
          <Tooltip delayDuration={120}>
            <TooltipTrigger asChild>
              <Button size="icon-xs" variant="outline" onClick={() => actions.onOpenTrail(node)}>
                <Route className="h-3 w-3" />
              </Button>
            </TooltipTrigger>
            <TooltipContent>Open trail</TooltipContent>
          </Tooltip>
          <Tooltip delayDuration={120}>
            <TooltipTrigger asChild>
              <Button size="icon-xs" variant="outline" onClick={() => actions.onChatAbout(node)}>
                <MessageSquare className="h-3 w-3" />
              </Button>
            </TooltipTrigger>
            <TooltipContent>Chat about this node</TooltipContent>
          </Tooltip>
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button size="icon-xs" variant="ghost" className="ml-auto">
                <MoreHorizontal className="h-3 w-3" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              <DropdownMenuItem onClick={() => actions.onOpenTrail(node)}>Open trail</DropdownMenuItem>
              <DropdownMenuItem onClick={() => actions.onShowLineage(node)}>Show lineage</DropdownMenuItem>
              <DropdownMenuSeparator />
              <DropdownMenuItem onClick={() => actions.onChallenge(node)}>Challenge</DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </div>
      </CardContent>
    </Card>
  );
}

function EvidenceRibbon({
  node,
  sourceRefs,
}: {
  node: GraphDataNode;
  sourceRefs: SourceReference[];
}) {
  const count = Math.max(sourceRefs.length, node.source_reference_count ?? 0, 1);
  const segments: Array<{
    id: number;
    confidence?: "high" | "medium" | "low" | null;
    source?: { title?: string | null } | null;
  }> =
    sourceRefs.length > 0
      ? sourceRefs
      : Array.from({ length: Math.min(count, 8) }).map((_, index) => ({
          id: index,
          confidence: index < count / 2 ? "high" : index < count * 0.75 ? "medium" : "low",
          source: null,
          relationship: "supports",
        }));

  return (
    <div className="flex h-7 items-stretch gap-1">
      {segments.slice(0, 10).map((source, index) => (
        <Tooltip key={`${source.id}-${index}`} delayDuration={100}>
          <TooltipTrigger asChild>
            <span
              className="min-w-3 flex-1 rounded-[3px]"
              style={{ backgroundColor: colorForConfidence(source.confidence) }}
            />
          </TooltipTrigger>
          <TooltipContent>
            {source.source?.title ?? `Evidence ${index + 1}`} · {source.confidence ?? "medium"}
          </TooltipContent>
        </Tooltip>
      ))}
    </div>
  );
}

function colorForConfidence(confidence?: "high" | "medium" | "low" | null): string {
  if (confidence === "high") return "#534AB7";
  if (confidence === "low") return "#AFA9EC";
  return "#7F77DD";
}
