import type { TrailChainNode } from "@/lib/api";
import { nodeTypeLabel } from "@/components/shared/node-type-icon";
import { cn } from "@/lib/utils";

interface TrailBreadcrumbProps {
  upstream: TrailChainNode[];
  centerType: string;
  downstream: TrailChainNode[];
  onNavigate: (nodeType: string, nodeId: number) => void;
}

type BreadcrumbItem = {
  nodeType: string;
  nodeId: number;
  isCurrent: boolean;
};

export function TrailBreadcrumb({
  upstream,
  centerType,
  downstream,
  onNavigate,
}: TrailBreadcrumbProps) {
  // Build unique type chain: upstream (reversed) → center → downstream
  const seen = new Set<string>();
  const items: BreadcrumbItem[] = [];

  // Upstream in reverse order (root first)
  const upReversed = [...upstream].reverse();
  for (const node of upReversed) {
    if (!seen.has(node.node_type)) {
      seen.add(node.node_type);
      items.push({ nodeType: node.node_type, nodeId: node.node_id, isCurrent: false });
    }
  }

  // Center
  seen.add(centerType);
  items.push({ nodeType: centerType, nodeId: 0, isCurrent: true });

  // Downstream
  for (const node of downstream) {
    if (!seen.has(node.node_type)) {
      seen.add(node.node_type);
      items.push({ nodeType: node.node_type, nodeId: node.node_id, isCurrent: false });
    }
  }

  if (items.length <= 1) return null;

  return (
    <div className="flex items-center gap-1.5 text-xs text-muted-foreground">
      {items.map((item, i) => (
        <span key={item.nodeType} className="flex items-center gap-1.5">
          {i > 0 && <span>→</span>}
          <span
            className={cn(
              item.isCurrent
                ? "font-medium text-foreground"
                : "cursor-pointer hover:text-foreground transition-colors",
            )}
            onClick={() => {
              if (!item.isCurrent) onNavigate(item.nodeType, item.nodeId);
            }}
          >
            {nodeTypeLabel(item.nodeType)}
          </span>
        </span>
      ))}
    </div>
  );
}
