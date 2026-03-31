import { memo } from "react";
import { Handle, Position, type NodeProps } from "@xyflow/react";
import type { BoardNode } from "@/types";
import { BOARD_NODE_WIDTH } from "./board-constants";

type BoardSourceNodeProps = NodeProps & { data: BoardNode };

function BoardSourceNodeInner({ data: node }: BoardSourceNodeProps) {
  return (
    <div
      className="rounded-xl border border-zinc-700 bg-zinc-900/80 px-4 py-3 shadow-lg backdrop-blur-sm"
      style={{ width: BOARD_NODE_WIDTH }}
    >
      <Handle type="target" position={Position.Top} className="!bg-zinc-600 !w-2 !h-2" />

      <div className="flex items-center justify-between mb-2">
        <div className="flex items-center gap-1.5">
          <span className="text-sm">📄</span>
          <span className="text-[10px] uppercase tracking-wider text-zinc-400">Source</span>
        </div>
        <span className="text-[10px] uppercase tracking-wider text-blue-400 bg-blue-500/10 px-1.5 py-0.5 rounded">
          ready
        </span>
      </div>

      <h3 className="text-sm font-medium text-white leading-tight line-clamp-2">{node.title}</h3>

      {node.body && (
        <p className="mt-1 text-xs text-zinc-400 line-clamp-2">{node.body}</p>
      )}

      <div className="mt-2">
        <span className="text-[10px] text-zinc-500">
          by {node.created_by === "human" ? "you" : node.created_by}
        </span>
      </div>

      <Handle type="source" position={Position.Bottom} className="!bg-zinc-600 !w-2 !h-2" />
    </div>
  );
}

export const BoardSourceNode = memo(BoardSourceNodeInner);
