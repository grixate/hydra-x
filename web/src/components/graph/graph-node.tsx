import { memo } from "react";
import { Handle, Position, type NodeProps } from "@xyflow/react";

type GraphNodeData = {
  label: string;
  nodeType: string;
  status: string;
  color: string;
  dbId: number;
};

export const GraphNodeComponent = memo(function GraphNodeComponent({
  data,
}: NodeProps) {
  const { label, nodeType, status, color } = data as GraphNodeData;
  const statusDot =
    status === "active" || status === "accepted"
      ? "bg-green-500"
      : status === "draft"
        ? "bg-yellow-500"
        : "bg-gray-400";

  return (
    <>
      <Handle type="target" position={Position.Top} className="!bg-transparent !border-0" />
      <div
        className="rounded-lg border bg-card px-3 py-2 shadow-sm transition-shadow hover:shadow-md"
        style={{ borderColor: color, borderWidth: 2 }}
      >
        <div className="flex items-center gap-1.5">
          <span className={`h-2 w-2 shrink-0 rounded-full ${statusDot}`} />
          <span className="max-w-[140px] truncate text-xs font-medium">{label}</span>
        </div>
        <span className="mt-0.5 block text-[9px] text-muted-foreground">
          {nodeType.replace(/_/g, " ")}
        </span>
      </div>
      <Handle type="source" position={Position.Bottom} className="!bg-transparent !border-0" />
    </>
  );
});
