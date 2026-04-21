import { memo } from "react";
import { Handle, Position, type NodeProps } from "@xyflow/react";
import type { BoardNode } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { BOARD_NODE_WIDTH, AGENT_ICONS } from "./board-constants";

type BoardSourceNodeProps = NodeProps & { data: BoardNode };

function BoardSourceNodeInner({ data: node }: BoardSourceNodeProps) {
  const meta = node.metadata ?? {};
  const processingStatus = (meta.processing_status as string) ?? "ready";
  const progress = (meta.progress as number) ?? 0;
  const filename = (meta.filename as string) ?? node.title;
  const insightCount = (meta.insight_count as number) ?? 0;
  const decisionCount = (meta.decision_count as number) ?? 0;
  const chunkCount = (meta.chunk_count as number) ?? 0;
  const pageCount = (meta.page_count as number) ?? 0;
  const agentWorking = (meta.agent_working as string) ?? null;
  const findingsPreview = (meta.findings_preview as string) ?? null;
  const errorMessage = (meta.error as string) ?? null;

  const isUploading = processingStatus === "uploading";
  const isProcessing = processingStatus === "processing" || processingStatus === "extracting" || processingStatus === "analyzing";
  const isReady = processingStatus === "ready" || processingStatus === "completed";
  const isFailed = processingStatus === "failed";

  const statusLabel = isFailed ? "failed" : isUploading ? "uploading" : isProcessing ? "processing" : "ready";
  const statusText = isUploading
    ? "Uploading"
    : processingStatus === "extracting"
      ? "Extracting text..."
      : agentWorking
        ? `${AGENT_ICONS[agentWorking] ?? "🤖"} ${agentWorking} analyzing...`
        : isProcessing
          ? progress >= 80
            ? "Creating insights..."
            : "Processing..."
          : null;

  // Build file info line
  const infoParts: string[] = [];
  if (meta.file_type) infoParts.push(String(meta.file_type).toUpperCase());
  if (pageCount > 0) infoParts.push(`${pageCount} pages`);
  if (chunkCount > 0) infoParts.push(`${chunkCount} chunks`);
  const fileInfo = infoParts.length > 0 ? infoParts.join(" · ") : null;

  // Build outcome line
  const outcomes: string[] = [];
  if (insightCount > 0) outcomes.push(`${insightCount} insight${insightCount !== 1 ? "s" : ""}`);
  if (decisionCount > 0) outcomes.push(`${decisionCount} decision${decisionCount !== 1 ? "s" : ""} proposed`);

  return (
    <div
      className={`rounded-xl border bg-card px-4 py-3 shadow-sm ${isFailed ? "border-destructive/40" : ""}`}
      style={{ width: BOARD_NODE_WIDTH }}
    >
      <Handle type="target" position={Position.Top} className="!bg-muted-foreground !w-2 !h-2" />

      {/* Header */}
      <div className="flex items-center justify-between mb-2">
        <div className="flex items-center gap-1.5">
          <span className="text-sm">📄</span>
          <span className="text-[10px] uppercase tracking-wider text-muted-foreground">Source</span>
        </div>
        <Badge
          variant={isFailed ? "destructive" : isReady ? "default" : "secondary"}
          className="text-[9px] px-1.5 py-0 h-4"
        >
          {statusLabel}
        </Badge>
      </div>

      {/* Title */}
      <h3 className="text-sm font-medium leading-tight line-clamp-2">{node.title}</h3>

      {/* File info */}
      {fileInfo && (
        <p className="mt-1 text-[10px] text-muted-foreground">{fileInfo}</p>
      )}

      {/* Progress bar + status (uploading/processing) */}
      {(isUploading || isProcessing) && (
        <div className="mt-2 space-y-1">
          <div className="h-1 w-full rounded-full bg-muted">
            <div
              className="h-1 rounded-full bg-primary transition-all duration-500"
              style={{ width: `${Math.max(progress, 5)}%` }}
            />
          </div>
          <div className="flex items-center gap-1.5 text-[10px] text-muted-foreground">
            {agentWorking && (
              <span className="inline-flex items-center gap-1">
                <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-primary" />
              </span>
            )}
            <span>{statusText}</span>
          </div>
          {findingsPreview && (
            <p className="text-[10px] text-muted-foreground italic">{findingsPreview}</p>
          )}
        </div>
      )}

      {/* Outcome line (complete) */}
      {isReady && outcomes.length > 0 && (
        <div className="mt-2 flex items-center gap-1.5 text-xs text-muted-foreground">
          <span>→</span>
          <span>{outcomes.join(" · ")}</span>
        </div>
      )}

      {/* Body excerpt (ready, no outcomes) */}
      {isReady && outcomes.length === 0 && node.body && (
        <p className="mt-1 text-xs text-muted-foreground line-clamp-2">{node.body}</p>
      )}

      {/* Error state */}
      {isFailed && (
        <div className="mt-2 space-y-1.5">
          <p className="text-[10px] text-destructive">{errorMessage || "Processing failed"}</p>
          <div className="flex gap-1.5">
            <Button variant="outline" size="sm" className="h-5 text-[10px] px-2">Retry</Button>
            <Button variant="ghost" size="sm" className="h-5 text-[10px] px-2 text-muted-foreground">Remove</Button>
          </div>
        </div>
      )}

      {/* Creator */}
      <div className="mt-2">
        <span className="text-[10px] text-muted-foreground">
          by {node.created_by === "human" ? "you" : node.created_by}
        </span>
      </div>

      <Handle type="source" position={Position.Bottom} className="!bg-muted-foreground !w-2 !h-2" />
    </div>
  );
}

export const BoardSourceNode = memo(BoardSourceNodeInner);
