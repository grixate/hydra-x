import { memo } from "react";
import { Handle, Position, useStore, type NodeProps, type ReactFlowState } from "@xyflow/react";
import type { GraphDataNode } from "@/types";
import { cn } from "@/lib/utils";
import { FileText } from "lucide-react";

interface GraphNodeData extends GraphDataNode {
  color: string;
  dimmed?: boolean;
  highlighted?: boolean;
  multiSelected?: boolean;
  previewing?: boolean;
  contradiction_severity?: "high" | "medium" | "low" | null;
  contradiction_count?: number;
  // Graph-Opt spec §10: WIP styling (draft/proposed/forming)
  wip?: boolean;
  // Graph-Opt spec §7: temporary pulse state (contradiction/agent activity)
  pulse?: "tension" | "activity" | null;
  // Lineage View §8: "in-lineage" vs. "off-chain"
  inLineage?: boolean;
}

const SIMPLIFY_ZOOM = 0.4;
const zoomTierSelector = (s: ReactFlowState) => s.transform[2] < SIMPLIFY_ZOOM;

export const GraphCustomNode = memo(
  function GraphCustomNode({ data }: NodeProps) {
    const d = data as unknown as GraphNodeData;
    const isSimplified = useStore(zoomTierSelector);

    // Simplified (overview zoom) — color/shape/size only per spec §6
    if (isSimplified) {
      return (
        <>
          <Handle
            type="target"
            position={Position.Top}
            className="!w-2 !h-2 !bg-transparent !border-0"
          />
          <div
            className={cn(
              "flex h-full w-full items-center rounded-lg border bg-card px-3 shadow-sm transition-opacity",
              d.dimmed && "opacity-[0.15]",
              d.highlighted && "ring-2 ring-primary",
              d.previewing && "ring-2 ring-primary",
              d.multiSelected && "ring-2 ring-primary/70",
              d.wip && "border-dashed opacity-70",
            )}
            style={{
              borderLeftColor: d.color,
              borderLeftWidth: 3,
            }}
          >
            <span className="truncate text-[12px] font-medium">{d.title}</span>
          </div>
          <Handle
            type="source"
            position={Position.Bottom}
            className="!w-2 !h-2 !bg-transparent !border-0"
          />
        </>
      );
    }

    const statusLabel =
      d.status === "active" || d.status === "accepted"
        ? "active"
        : d.status ?? "draft";

    const refCount = d.source_reference_count ?? 0;

    return (
      <>
        <Handle
          type="target"
          position={Position.Top}
          className="!w-2 !h-2 !bg-transparent !border-0 hover:!bg-primary hover:!border-2 hover:!border-background !transition-all"
        />
        <div
          className={cn(
            "rounded-xl bg-card px-3 py-2.5 transition-all",
            d.dimmed && "opacity-[0.15]",
            d.highlighted && "ring-2 ring-primary shadow-md",
            d.previewing && "ring-2 ring-primary",
            d.multiSelected && "ring-2 ring-primary/70",
            // Lineage View — off-chain nodes atmospheric
            d.inLineage === false && "opacity-[0.15]",
            // WIP styling — dashed, translucent, slightly desaturated
            d.wip && "graph-wip opacity-80",
            // Pulse for state-change (§7)
            d.pulse === "tension" && "graph-pulse-tension",
            d.pulse === "activity" && "graph-pulse-activity",
          )}
          style={{
            boxShadow:
              d.flag_count > 0
                ? `inset 4px 0 0 0 #f59e0b, inset 0 0 0 2px ${d.color}`
                : `inset 0 0 0 2px ${d.color}`,
          }}
        >
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

          <p className="mt-1 text-[13px] font-semibold leading-tight line-clamp-2">
            {d.title}
          </p>

          {d.body && (
            <p className="mt-1 text-[11px] leading-snug text-muted-foreground line-clamp-2">
              {d.body}
            </p>
          )}

          <div className="mt-1.5 flex items-center gap-2.5 text-[10px] text-muted-foreground">
            <span title="Upstream connections">↑{d.upstream_count}</span>
            <span title="Downstream connections">↓{d.downstream_count}</span>
            {refCount > 0 && (
              <span
                className="inline-flex items-center gap-0.5 text-[10px] text-sky-700/80 dark:text-sky-300/80"
                title={`${refCount} Library source${refCount === 1 ? "" : "s"} referenced`}
              >
                <FileText className="h-2.5 w-2.5" />
                {refCount}
              </span>
            )}
            {d.flag_count > 0 && (
              <span className="text-amber-600" title="Open flags">
                ⚑{d.flag_count}
              </span>
            )}
            {d.contradiction_severity ? (
              <span
                className={cn(
                  d.contradiction_severity === "high" ? "text-rose-600" : "text-amber-600",
                )}
                title={`${d.contradiction_count ?? 1} contradiction${
                  (d.contradiction_count ?? 1) === 1 ? "" : "s"
                } (${d.contradiction_severity})`}
              >
                ⚠{d.contradiction_count && d.contradiction_count > 1 ? d.contradiction_count : ""}
              </span>
            ) : null}
            {d.wip && (
              <span className="text-purple-600 dark:text-purple-400" title="Work in progress">
                ◉ draft
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
  },
  arePropsEqual,
);

function arePropsEqual(prev: NodeProps, next: NodeProps): boolean {
  if (prev.id !== next.id) return false;
  if (prev.selected !== next.selected) return false;
  const a = prev.data as unknown as GraphNodeData;
  const b = next.data as unknown as GraphNodeData;
  return (
    a.title === b.title &&
    a.body === b.body &&
    a.status === b.status &&
    a.node_type === b.node_type &&
    a.color === b.color &&
    a.upstream_count === b.upstream_count &&
    a.downstream_count === b.downstream_count &&
    a.flag_count === b.flag_count &&
    a.source_reference_count === b.source_reference_count &&
    a.contradiction_severity === b.contradiction_severity &&
    a.contradiction_count === b.contradiction_count &&
    a.dimmed === b.dimmed &&
    a.highlighted === b.highlighted &&
    a.multiSelected === b.multiSelected &&
    a.previewing === b.previewing &&
    a.wip === b.wip &&
    a.pulse === b.pulse &&
    a.inLineage === b.inLineage
  );
}
