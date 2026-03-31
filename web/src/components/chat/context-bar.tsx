import type { GraphDataNode } from "@/types";
import { NODE_COLORS } from "@/components/graph/graph-constants";
import { X } from "lucide-react";
import { cn } from "@/lib/utils";

interface ChatContextBarProps {
  /** Nodes explicitly added to chat context (persistent) */
  nodes: GraphDataNode[];
  /** Node currently being previewed (temporary, shown as muted indicator) */
  previewNode?: GraphDataNode | null;
  onClear: () => void;
  onRemove?: (nodeId: string) => void;
}

export function ChatContextBar({
  nodes,
  previewNode,
  onClear,
  onRemove,
}: ChatContextBarProps) {
  const hasContext = nodes.length > 0;
  const hasPreview = previewNode && !nodes.some((n) => n.id === previewNode.id);

  if (!hasContext && !hasPreview) return null;

  const shown = nodes.slice(0, 5);
  const extra = nodes.length - shown.length;

  return (
    <div className="flex items-center gap-1.5 border-b border-border/50 bg-muted/30 px-4 py-2">
      <div className="flex flex-1 flex-wrap items-center gap-1.5 overflow-hidden">
        {/* Temporary preview indicator */}
        {hasPreview && previewNode && (
          <div className="flex items-center gap-1 rounded-full border border-dashed px-2 py-0.5 min-w-0 opacity-60">
            <span
              className="h-1.5 w-1.5 shrink-0 rounded-full"
              style={{
                backgroundColor:
                  NODE_COLORS[previewNode.node_type] ?? NODE_COLORS.default,
              }}
            />
            <span className="truncate text-[11px] text-muted-foreground max-w-[120px]">
              {previewNode.title}
            </span>
          </div>
        )}

        {/* Persistent context nodes */}
        {shown.map((node) => (
          <div
            key={node.id}
            className="flex items-center gap-1 rounded-full bg-background/80 border px-2 py-0.5 min-w-0"
          >
            <span
              className="h-1.5 w-1.5 shrink-0 rounded-full"
              style={{
                backgroundColor:
                  NODE_COLORS[node.node_type] ?? NODE_COLORS.default,
              }}
            />
            <span className="truncate text-[11px] text-foreground max-w-[120px]">
              {node.title}
            </span>
            {onRemove && (
              <button
                type="button"
                onClick={() => onRemove(node.id)}
                className="shrink-0 rounded-full p-0.5 text-muted-foreground hover:text-foreground transition-colors"
              >
                <X className="h-2.5 w-2.5" />
              </button>
            )}
          </div>
        ))}
        {extra > 0 && (
          <span className="shrink-0 text-[11px] text-muted-foreground">
            +{extra} more
          </span>
        )}
      </div>
      {hasContext && (
        <button
          type="button"
          onClick={onClear}
          className="shrink-0 rounded p-0.5 text-muted-foreground hover:bg-muted hover:text-foreground transition-colors"
          title="Clear all"
        >
          <X className="h-3.5 w-3.5" />
        </button>
      )}
    </div>
  );
}
