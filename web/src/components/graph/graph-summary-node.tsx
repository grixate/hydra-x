import { memo } from "react";
import type { NodeProps } from "@xyflow/react";
import { ChevronDown } from "lucide-react";
import { useLayoutControls } from "./graph-layout-controls";
import { prettyLabel } from "./graph-constants";

interface SummaryNodeData {
  groupKey: string;
  label: string;
  color: string;
  count: number;
  statusBreakdown: Record<string, number>;
  topTitle: string | null;
  topConnections: number;
  lastUpdated: string;
}

function relativeTime(iso: string): string {
  if (!iso) return "";
  const then = new Date(iso).getTime();
  if (Number.isNaN(then)) return "";
  const diff = Date.now() - then;
  const m = Math.floor(diff / 60000);
  if (m < 1) return "just now";
  if (m < 60) return `${m}m ago`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h ago`;
  const d = Math.floor(h / 24);
  return `${d}d ago`;
}

function areSummaryPropsEqual(prev: NodeProps, next: NodeProps): boolean {
  if (prev.id !== next.id) return false;
  const a = prev.data as unknown as SummaryNodeData;
  const b = next.data as unknown as SummaryNodeData;
  return (
    a.groupKey === b.groupKey &&
    a.label === b.label &&
    a.color === b.color &&
    a.count === b.count &&
    a.topTitle === b.topTitle &&
    a.topConnections === b.topConnections &&
    a.lastUpdated === b.lastUpdated &&
    shallowEqualRecord(a.statusBreakdown, b.statusBreakdown)
  );
}

function shallowEqualRecord(
  a: Record<string, number> | null | undefined,
  b: Record<string, number> | null | undefined,
): boolean {
  if (a === b) return true;
  if (!a || !b) return false;
  const ak = Object.keys(a);
  const bk = Object.keys(b);
  if (ak.length !== bk.length) return false;
  for (const k of ak) if (a[k] !== b[k]) return false;
  return true;
}

export const GraphSummaryNode = memo(function GraphSummaryNode({
  data,
}: NodeProps) {
  const d = data as unknown as SummaryNodeData;
  const { toggleGroup } = useLayoutControls();

  const breakdown = Object.entries(d.statusBreakdown)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 3)
    .map(([k, v]) => `${v} ${prettyLabel(k).toLowerCase()}`)
    .join(" · ");

  return (
    <div
      className="flex h-full w-full flex-col rounded-xl border bg-card px-4 py-3 shadow-sm"
      style={{ borderColor: `${d.color}55` }}
    >
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <span
            className="h-2 w-2 rounded-full"
            style={{ backgroundColor: d.color }}
          />
          <span className="text-[12px] font-semibold">{d.label}</span>
        </div>
        <span className="text-[11px] text-muted-foreground">{d.count}</span>
      </div>

      {breakdown && (
        <p className="mt-1.5 text-[11px] text-muted-foreground">{breakdown}</p>
      )}

      {d.lastUpdated && (
        <p className="text-[10px] text-muted-foreground/70">
          Updated {relativeTime(d.lastUpdated)}
        </p>
      )}

      {d.topTitle && (
        <p className="mt-1.5 line-clamp-2 text-[11px] leading-snug">
          <span className="text-muted-foreground">Top: </span>
          {d.topTitle}
          {d.topConnections > 0 && (
            <span className="text-muted-foreground"> (+{d.topConnections})</span>
          )}
        </p>
      )}

      <button
        type="button"
        onClick={(e) => {
          e.stopPropagation();
          toggleGroup(d.groupKey);
        }}
        className="mt-auto flex items-center justify-end gap-1 self-end text-[11px] font-medium text-primary hover:underline"
      >
        Expand <ChevronDown className="h-3 w-3" />
      </button>
    </div>
  );
}, areSummaryPropsEqual);
