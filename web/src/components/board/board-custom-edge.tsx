import { memo } from "react";
import { BezierEdge, type EdgeProps } from "@xyflow/react";
import { EDGE_STYLES } from "./board-constants";

function BoardCustomEdgeInner(props: EdgeProps) {
  const kind = (props.data as { kind?: string })?.kind ?? "default";
  const style = EDGE_STYLES[kind] ?? EDGE_STYLES.default;

  return <BezierEdge {...props} style={style} />;
}

export const BoardCustomEdge = memo(BoardCustomEdgeInner);
