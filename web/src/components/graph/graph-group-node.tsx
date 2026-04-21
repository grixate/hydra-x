import { memo } from "react";
import type { NodeProps } from "@xyflow/react";

interface GroupNodeData {
  label: string;
  color: string;
  count: number;
}

function areGroupPropsEqual(prev: NodeProps, next: NodeProps): boolean {
  if (prev.id !== next.id) return false;
  const a = prev.data as unknown as GroupNodeData;
  const b = next.data as unknown as GroupNodeData;
  return a.label === b.label && a.color === b.color && a.count === b.count;
}

export const GraphGroupNode = memo(function GraphGroupNode({
  data,
}: NodeProps) {
  const d = data as unknown as GroupNodeData;
  return (
    <div
      className="relative h-full w-full rounded-2xl"
      style={{
        backgroundColor: `${d.color}0D`,
        border: `1px solid ${d.color}26`,
      }}
    >
      <div className="absolute -top-3 left-4 flex items-center gap-2">
        <div
          className="flex items-center gap-1.5 rounded-full border bg-background px-2.5 py-0.5 shadow-sm"
        >
          <span
            className="h-1.5 w-1.5 rounded-full"
            style={{ backgroundColor: d.color }}
          />
          <span className="text-[10px] font-semibold uppercase tracking-widest text-muted-foreground">
            {d.label}
          </span>
          <span className="text-[10px] text-muted-foreground/70">
            {d.count}
          </span>
        </div>
      </div>
    </div>
  );
}, areGroupPropsEqual);
