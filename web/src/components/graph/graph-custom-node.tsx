import { memo } from "react";
import { Handle, Position, type NodeProps } from "@xyflow/react";
import type { GraphDataNode } from "@/types";
import { cn } from "@/lib/utils";

interface GraphNodeData extends GraphDataNode {
  color: string;
  dimmed?: boolean;
  highlighted?: boolean;
  multiSelected?: boolean;
  previewing?: boolean;
}

export const GraphCustomNode = memo(function GraphCustomNode({
  data,
}: NodeProps) {
  const d = data as unknown as GraphNodeData;

  const statusLabel =
    d.status === "active" || d.status === "accepted"
      ? "active"
      : d.status ?? "draft";

  return (
    <>
      <Handle
        type="target"
        position={Position.Top}
        className="!w-2 !h-2 !bg-transparent !border-0 hover:!bg-primary hover:!border-2 hover:!border-background !transition-all"
      />
      <div
        className={cn(
          "rounded-xl border bg-card px-3 py-2.5 shadow-sm transition-all",
          d.dimmed && "opacity-[0.15]",
          d.highlighted && "ring-2 ring-primary shadow-md",
          d.previewing && "ring-2 ring-primary",
          d.multiSelected && "ring-2 ring-primary/70",
          (d.status === "draft" || d.status === "pending") && "border-dashed",
          d.flag_count > 0 && "border-l-2 border-l-amber-500",
        )}
        style={{ borderColor: d.flag_count > 0 ? undefined : d.color }}
      >
        {/* Header: type dot + label | status */}
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-1.5">
            <span
              className="h-2 w-2 shrink-0 rounded-full"
              style={{ backgroundColor: d.color }}
            />
            <span className="text-[11px] text-muted-foreground">
              {d.node_type.replace(/_/g, " ")}
            </span>
          </div>
          <span className="text-[10px] text-muted-foreground">
            {statusLabel}
          </span>
        </div>

        {/* Title */}
        <p className="mt-1 text-[13px] font-semibold leading-tight line-clamp-2">
          {d.title}
        </p>

        {/* Body excerpt */}
        {d.body && (
          <p className="mt-1 text-[11px] leading-snug text-muted-foreground line-clamp-2">
            {d.body}
          </p>
        )}

        {/* Footer: connection indicators */}
        <div className="mt-1.5 flex items-center gap-2.5 text-[10px] text-muted-foreground">
          <span title="Upstream connections">↑{d.upstream_count}</span>
          <span title="Downstream connections">↓{d.downstream_count}</span>
          {d.flag_count > 0 && (
            <span className="text-amber-600" title="Open flags">
              ⚑{d.flag_count}
            </span>
          )}
        </div>
      </div>
      <Handle
        type="source"
        position={Position.Bottom}
        className="!w-2 !h-2 !bg-transparent !border-0 hover:!bg-primary hover:!border-2 hover:!border-background !transition-all"
      />
    </>
  );
});
