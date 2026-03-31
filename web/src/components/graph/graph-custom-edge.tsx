import { memo } from "react";
import { BaseEdge, getBezierPath, type EdgeProps } from "@xyflow/react";
import { EDGE_STYLES, DIRECTED_EDGE_KINDS } from "./graph-constants";

interface GraphEdgeData {
  kind: string;
  weight: number;
}

export const GraphCustomEdge = memo(function GraphCustomEdge(
  props: EdgeProps,
) {
  const {
    sourceX,
    sourceY,
    targetX,
    targetY,
    sourcePosition,
    targetPosition,
    data,
    selected,
  } = props;
  const d = data as unknown as GraphEdgeData | undefined;
  const kind = d?.kind ?? "default";
  const style = EDGE_STYLES[kind] ?? EDGE_STYLES.default;

  const [edgePath] = getBezierPath({
    sourceX,
    sourceY,
    targetX,
    targetY,
    sourcePosition,
    targetPosition,
  });

  return (
    <BaseEdge
      path={edgePath}
      style={{
        stroke: selected ? "hsl(var(--primary))" : style.stroke,
        strokeWidth: selected ? style.strokeWidth + 1 : style.strokeWidth,
        strokeDasharray: style.strokeDasharray,
        cursor: "pointer",
      }}
      markerEnd={
        DIRECTED_EDGE_KINDS.has(kind) ? "url(#arrow-marker)" : undefined
      }
    />
  );
});
