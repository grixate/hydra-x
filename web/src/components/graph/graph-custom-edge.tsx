import { memo } from "react";
import {
  BaseEdge,
  getBezierPath,
  getStraightPath,
  useStore,
  type EdgeProps,
  type ReactFlowState,
} from "@xyflow/react";
import { EDGE_STYLES, DIRECTED_EDGE_KINDS } from "./graph-constants";

interface GraphEdgeData {
  kind: string;
  weight: number;
  faded?: boolean;
  fresh?: boolean;
  // WIP styling — dotted edges for draft/proposed links (§10).
  wip?: boolean;
  // Spec §4 O3: edge bundling — multiplicity indicator.
  bundleCount?: number;
  // Lineage View §8: emphasize in-chain edges.
  inLineage?: boolean;
}

// Graph-Opt §4 O3: at far zoom use straight lines (cheaper than computed
// bezier). Threshold matches the node simplification tier for consistency.
//
// IMPORTANT: subscribing to zoom directly would re-render every edge on
// every frame during pan/zoom. Map to a boolean so Zustand only notifies
// when the tier crosses the threshold.
const STRAIGHT_ZOOM = 0.45;
const simplifiedSelector = (s: ReactFlowState) => s.transform[2] < STRAIGHT_ZOOM;

function areEdgePropsEqual(prev: EdgeProps, next: EdgeProps): boolean {
  if (prev.id !== next.id) return false;
  if (prev.selected !== next.selected) return false;
  if (
    prev.sourceX !== next.sourceX ||
    prev.sourceY !== next.sourceY ||
    prev.targetX !== next.targetX ||
    prev.targetY !== next.targetY ||
    prev.sourcePosition !== next.sourcePosition ||
    prev.targetPosition !== next.targetPosition
  )
    return false;
  const a = prev.data as GraphEdgeData | undefined;
  const b = next.data as GraphEdgeData | undefined;
  return (
    a?.kind === b?.kind &&
    a?.faded === b?.faded &&
    a?.fresh === b?.fresh &&
    a?.weight === b?.weight &&
    a?.wip === b?.wip &&
    a?.bundleCount === b?.bundleCount &&
    a?.inLineage === b?.inLineage
  );
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
  const simplified = useStore(simplifiedSelector);
  const d = data as unknown as GraphEdgeData | undefined;
  const kind = d?.kind ?? "default";
  const style = EDGE_STYLES[kind] ?? EDGE_STYLES.default;

  const [edgePath, midX, midY] = simplified
    ? getStraightPath({ sourceX, sourceY, targetX, targetY })
    : getBezierPath({
        sourceX,
        sourceY,
        targetX,
        targetY,
        sourcePosition,
        targetPosition,
      });

  // Lineage emphasis: in-chain edges brighten. Off-chain fade.
  const lineageFade = d?.inLineage === false;

  const strokeWidth = selected
    ? style.strokeWidth + 1
    : d?.faded || lineageFade
      ? Math.min(style.strokeWidth, 0.5)
      : (d?.bundleCount ?? 1) > 1
        ? Math.min(style.strokeWidth + 0.5, 3)
        : style.strokeWidth;

  const opacity = selected ? 1 : d?.faded || lineageFade ? 0.25 : undefined;

  const dash = d?.wip ? "2 3" : style.strokeDasharray;

  return (
    <>
      <BaseEdge
        path={edgePath}
        style={{
          stroke: selected ? "hsl(var(--primary))" : style.stroke,
          strokeWidth,
          strokeDasharray: dash,
          opacity,
          cursor: "pointer",
        }}
        markerEnd={
          DIRECTED_EDGE_KINDS.has(kind) ? "url(#arrow-marker)" : undefined
        }
        data-fresh={d?.fresh ? "true" : undefined}
      />
      {(d?.bundleCount ?? 1) > 1 && !simplified && (
        <text
          x={midX}
          y={midY}
          className="text-[9px] fill-muted-foreground"
          textAnchor="middle"
          dy="-4"
          pointerEvents="none"
        >
          ×{d?.bundleCount}
        </text>
      )}
    </>
  );
}, areEdgePropsEqual);
