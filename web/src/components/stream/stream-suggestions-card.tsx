import { motion } from "motion/react";
import type { StreamItem } from "@/lib/api";
import { Button } from "@/components/ui/button";
import { AlertTriangle, Lightbulb } from "lucide-react";

interface StreamSuggestionsCardProps {
  items: StreamItem[];
  onNavigate?: (nodeType: string, nodeId: number) => void;
  onAction?: (action: string, item: StreamItem) => void;
}

function itemIcon(item: StreamItem) {
  const flagType = item.metadata?.flag_type as string | undefined;
  if (flagType === "stale" || flagType === "orphaned" || flagType === "confidence_decayed") {
    return <AlertTriangle className="h-3.5 w-3.5 shrink-0 text-amber-500" />;
  }
  return <Lightbulb className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />;
}

export function StreamSuggestionsCard({ items, onNavigate, onAction }: StreamSuggestionsCardProps) {
  if (items.length === 0) return null;

  return (
    <motion.div
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.4, ease: [0.25, 0.46, 0.45, 0.94] }}
      className="rounded-xl border bg-muted/30 p-5 space-y-1"
    >
      {items.map((item, i) => (
        <motion.div
          key={item.id}
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ duration: 0.3, delay: 0.1 + i * 0.05 }}
          className="flex items-center gap-3 py-1.5"
        >
          {itemIcon(item)}
          <span
            className="flex-1 text-sm text-muted-foreground cursor-pointer hover:text-foreground transition-colors"
            onClick={() => onNavigate?.(item.node_type, item.node_id)}
          >
            {item.title}
          </span>
          <Button
            variant="ghost"
            size="sm"
            className="text-xs h-6 px-2 shrink-0"
            onClick={() => onAction?.(
              item.metadata?.flag_type === "stale" || item.metadata?.flag_type === "orphaned"
                ? "review"
                : "dismiss",
              item,
            )}
          >
            {item.metadata?.flag_type === "stale" || item.metadata?.flag_type === "orphaned"
              ? "Review"
              : "Dismiss"}
          </Button>
        </motion.div>
      ))}
    </motion.div>
  );
}
