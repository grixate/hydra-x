import { memo } from "react";
import { Handle, Position, type NodeProps } from "@xyflow/react";
import type { BoardNode } from "@/types";
import { NODE_COLORS, REACTION_MARKS, NODE_TYPE_LABELS, BOARD_NODE_WIDTH } from "./board-constants";
import type { ReactionType } from "./board-constants";

type BoardCustomNodeProps = NodeProps & { data: BoardNode };

function BoardCustomNodeInner({ data: node }: BoardCustomNodeProps) {
  const color = NODE_COLORS[node.node_type] ?? NODE_COLORS.default;
  const typeLabel = NODE_TYPE_LABELS[node.node_type] ?? node.node_type;
  const reactions = node.metadata?.reactions;

  const borderClass =
    node.status === "promoted"
      ? "border-green-500 bg-green-500/5"
      : node.status === "discarded"
        ? "border-zinc-600 bg-zinc-800/50 opacity-60"
        : "border-zinc-700 bg-zinc-900/80";

  return (
    <div
      className={`rounded-xl border px-4 py-3 shadow-lg backdrop-blur-sm ${borderClass}`}
      style={{ width: BOARD_NODE_WIDTH }}
    >
      <Handle type="target" position={Position.Top} className="!bg-zinc-600 !w-2 !h-2" />

      {/* Header: type + status */}
      <div className="flex items-center justify-between mb-2">
        <div className="flex items-center gap-1.5">
          <span className="w-2 h-2 rounded-full" style={{ backgroundColor: color }} />
          <span className="text-[10px] uppercase tracking-wider text-zinc-400">{typeLabel}</span>
        </div>
        <span
          className={`text-[10px] uppercase tracking-wider px-1.5 py-0.5 rounded ${
            node.status === "promoted"
              ? "text-green-400 bg-green-500/10"
              : node.status === "discarded"
                ? "text-zinc-500 bg-zinc-700/50"
                : "text-amber-400 bg-amber-500/10"
          }`}
        >
          {node.status === "promoted" ? "✓ promoted" : node.status}
        </span>
      </div>

      {/* Title */}
      <h3 className="text-sm font-medium text-white leading-tight line-clamp-2">{node.title}</h3>

      {/* Body excerpt */}
      {node.body && (
        <p className="mt-1 text-xs text-zinc-400 line-clamp-2 leading-relaxed">{node.body}</p>
      )}

      {/* Footer: creator + reactions */}
      <div className="mt-2 flex items-center justify-between">
        <span className="text-[10px] text-zinc-500">
          by {node.created_by === "human" ? "you" : node.created_by}
        </span>
        {reactions && (
          <div className="flex gap-2">
            {(Object.keys(REACTION_MARKS) as ReactionType[]).map((key) => {
              const count = reactions[key]?.length ?? 0;
              if (count === 0) return null;
              return (
                <span key={key} className="text-[10px] text-zinc-400" title={`${REACTION_MARKS[key].label}: ${count}`}>
                  {REACTION_MARKS[key].icon}{count}
                </span>
              );
            })}
          </div>
        )}
      </div>

      <Handle type="source" position={Position.Bottom} className="!bg-zinc-600 !w-2 !h-2" />
    </div>
  );
}

export const BoardCustomNode = memo(BoardCustomNodeInner);
