import type { TrailChainNode } from "@/lib/api";
import { TrailNodeCard } from "./trail-node";

interface TrailChainProps {
  nodes: TrailChainNode[];
  direction: "upstream" | "downstream";
  onNodeClick?: (nodeType: string, nodeId: number) => void;
}

const kindLabels: Record<string, string> = {
  lineage: "derived from",
  dependency: "depends on",
  supports: "supports",
  contradicts: "contradicts",
  supersedes: "supersedes",
  blocks: "blocks",
  enables: "enables",
};

export function TrailChain({ nodes, direction, onNodeClick }: TrailChainProps) {
  if (nodes.length === 0) return null;

  return (
    <div className="space-y-1">
      <p className="text-[10px] font-bold uppercase tracking-[0.3em] text-ink-soft">
        {direction === "upstream" ? "Upstream" : "Downstream"}
      </p>
      <div className="space-y-0">
        {nodes.map((node, i) => (
          <div key={`${node.node_type}-${node.node_id}-${i}`}>
            {i > 0 && (
              <div className="flex items-center gap-2 py-1 pl-4">
                <div className="h-4 w-px bg-line" />
                <span className="text-[9px] text-ink-soft">
                  {kindLabels[node.edge_kind] ?? node.edge_kind}
                </span>
              </div>
            )}
            <TrailNodeCard node={node} onClick={onNodeClick} />
          </div>
        ))}
      </div>
    </div>
  );
}
