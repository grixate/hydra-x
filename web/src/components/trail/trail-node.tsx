import type { TrailChainNode } from "@/lib/api";
import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";

interface TrailNodeProps {
  node: TrailChainNode;
  onClick?: (nodeType: string, nodeId: number) => void;
  isCenter?: boolean;
}

export function TrailNodeCard({ node, onClick, isCenter }: TrailNodeProps) {
  return (
    <button
      type="button"
      onClick={() => onClick?.(node.node_type, node.node_id)}
      className={cn(
        "w-full rounded-[1rem] border p-3 text-left transition-colors hover:border-accent",
        isCenter
          ? "border-accent bg-accent/5"
          : "border-line bg-paper",
      )}
    >
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0 flex-1">
          <p className="text-sm font-medium leading-tight">
            {node.title || `${node.node_type}#${node.node_id}`}
          </p>
          {node.summary && (
            <p className="mt-1 text-xs text-ink-soft line-clamp-2">
              {node.summary}
            </p>
          )}
        </div>
        <div className="flex shrink-0 items-center gap-1">
          <Badge variant="secondary" className="text-[9px]">
            {node.node_type}
          </Badge>
          {node.status && (
            <Badge
              variant={node.status === "active" ? "default" : "secondary"}
              className="text-[9px]"
            >
              {node.status}
            </Badge>
          )}
        </div>
      </div>
    </button>
  );
}
