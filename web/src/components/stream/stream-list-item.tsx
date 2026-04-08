import { motion } from "motion/react";
import type { StreamItem } from "@/lib/api";
import { nodeTypeLabel } from "@/components/shared/node-type-icon";
import { NODE_COLORS } from "@/components/graph/graph-constants";
import { relativeLabel } from "@/lib/utils";

interface StreamListItemProps {
  item: StreamItem;
  index?: number;
  onNavigate?: (nodeType: string, nodeId: number) => void;
}

export function StreamListItem({ item, index = 0, onNavigate }: StreamListItemProps) {
  const dotColor = NODE_COLORS[item.node_type] ?? NODE_COLORS.default;
  const isResolved = item.metadata?.status === "resolved";

  const content = (
    <>
      <div
        className="h-2 w-2 shrink-0 rounded-full"
        style={{
          backgroundColor: dotColor,
          opacity: isResolved ? 0.4 : 1,
        }}
      />
      <span className="w-20 shrink-0 text-xs text-muted-foreground">
        {item.type === "group" && item.items
          ? `${nodeTypeLabel(item.node_type)} (${item.items.length})`
          : nodeTypeLabel(item.node_type)}
      </span>
      <span className="flex-1 truncate text-sm">
        {item.title}
      </span>
      <span className="shrink-0 text-xs text-muted-foreground">
        {relativeLabel(item.timestamp)}
      </span>
    </>
  );

  return (
    <motion.div
      initial={{ opacity: 0, x: -8 }}
      animate={{ opacity: 1, x: 0 }}
      transition={{
        duration: 0.25,
        delay: index * 0.03,
        ease: [0.25, 0.46, 0.45, 0.94],
      }}
      className="flex items-center gap-3 py-2 px-2 rounded-md hover:bg-muted/50 cursor-pointer"
      onClick={() => {
        if (item.type === "group" && item.items) {
          const first = item.items[0];
          if (first) onNavigate?.(first.node_type, first.node_id);
        } else {
          onNavigate?.(item.node_type, item.node_id);
        }
      }}
    >
      {content}
    </motion.div>
  );
}
