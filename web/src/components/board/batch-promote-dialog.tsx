import { useState, useEffect, useMemo } from "react";
import { api } from "@/lib/api";
import type { BoardNode } from "@/types";
import { NODE_COLORS, NODE_TYPE_LABELS, REACTION_MARKS } from "./board-constants";
import type { ReactionType } from "./board-constants";

type BatchPromoteDialogProps = {
  projectId: number;
  sessionId: number;
  nodes: BoardNode[];
  open: boolean;
  onClose: () => void;
};

function computePreselected(draftNodes: BoardNode[]): Set<number> {
  const preselected = new Set<number>();
  for (const node of draftNodes) {
    const agreeCount = node.metadata?.reactions?.agree?.length ?? 0;
    if (agreeCount >= 2) preselected.add(node.id);
  }
  return preselected;
}

export function BatchPromoteDialog({ projectId, sessionId, nodes, open, onClose }: BatchPromoteDialogProps) {
  const draftNodes = useMemo(() => nodes.filter((n) => n.status === "draft"), [nodes]);

  const [selected, setSelected] = useState<Set<number>>(() => computePreselected(draftNodes));
  const [promoting, setPromoting] = useState(false);

  // Reset selection when dialog opens or nodes change
  useEffect(() => {
    if (open) {
      setSelected(computePreselected(draftNodes));
    }
  }, [open, draftNodes]);

  if (!open) return null;

  function toggle(id: number) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  async function handlePromote() {
    setPromoting(true);
    await api.promoteBoardNodesBatch(projectId, sessionId, Array.from(selected));
    setPromoting(false);
    onClose();
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm">
      <div className="w-full max-w-lg rounded-xl border border-zinc-800 bg-zinc-950 p-6 shadow-2xl">
        <h2 className="text-lg font-medium text-white">Review session nodes</h2>
        <p className="mt-1 text-xs text-zinc-500">
          {draftNodes.length} draft nodes · Pre-selected: nodes with 2+ agrees
        </p>

        <div className="mt-4 max-h-80 space-y-2 overflow-y-auto">
          {draftNodes.map((node) => {
            const reactions = node.metadata?.reactions;
            return (
              <label
                key={node.id}
                className="flex cursor-pointer items-center gap-3 rounded-lg border border-zinc-800 px-3 py-2 hover:bg-zinc-900 transition"
              >
                <input
                  type="checkbox"
                  checked={selected.has(node.id)}
                  onChange={() => toggle(node.id)}
                  className="rounded border-zinc-600"
                />
                <span
                  className="w-2 h-2 rounded-full shrink-0"
                  style={{ backgroundColor: NODE_COLORS[node.node_type] ?? NODE_COLORS.default }}
                />
                <span className="flex-1 text-sm text-white truncate">{node.title}</span>
                <span className="text-[10px] text-zinc-500">{NODE_TYPE_LABELS[node.node_type]}</span>
                {reactions && (
                  <div className="flex gap-1.5 ml-2">
                    {(Object.keys(REACTION_MARKS) as ReactionType[]).map((key) => {
                      const count = reactions[key]?.length ?? 0;
                      if (count === 0) return null;
                      return (
                        <span key={key} className="text-[10px] text-zinc-400">
                          {REACTION_MARKS[key].icon}{count}
                        </span>
                      );
                    })}
                  </div>
                )}
              </label>
            );
          })}
        </div>

        <div className="mt-4 flex items-center justify-between">
          <div className="flex gap-2">
            <button
              onClick={() => setSelected(new Set(draftNodes.map((n) => n.id)))}
              className="text-[10px] uppercase tracking-wider text-zinc-500 hover:text-white transition"
            >
              Select all
            </button>
            <button
              onClick={() => setSelected(new Set())}
              className="text-[10px] uppercase tracking-wider text-zinc-500 hover:text-white transition"
            >
              Deselect all
            </button>
          </div>
          <div className="flex gap-2">
            <button
              onClick={onClose}
              className="rounded-lg border border-zinc-700 px-4 py-2 text-xs text-zinc-400 hover:bg-zinc-800 transition"
            >
              Cancel
            </button>
            <button
              onClick={handlePromote}
              disabled={promoting || selected.size === 0}
              className="rounded-lg bg-green-600 px-4 py-2 text-xs font-medium text-white hover:bg-green-500 transition disabled:opacity-50"
            >
              {promoting ? "Promoting..." : `Promote ${selected.size} selected`}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
