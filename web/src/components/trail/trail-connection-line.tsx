import { motion } from "motion/react";
import { cn } from "@/lib/utils";

interface TrailConnectionLineProps {
  edgeKind: string;
}

const kindLabels: Record<string, string> = {
  lineage: "lineage",
  dependency: "dependency",
  supports: "supports",
  contradicts: "contradicts",
  supersedes: "supersedes",
  blocks: "blocks",
  enables: "enables",
  constrains: "constrains",
};

export function TrailConnectionLine({ edgeKind }: TrailConnectionLineProps) {
  const isDestructive = edgeKind === "contradicts";

  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      transition={{ duration: 0.3 }}
      className="flex flex-col items-center py-1"
    >
      <div
        className={cn("h-6 w-px", isDestructive ? "bg-destructive/30" : "bg-border")}
      />
      <span
        className={cn(
          "rounded-full px-2.5 py-0.5 text-[10px]",
          isDestructive
            ? "bg-destructive/10 text-destructive"
            : "bg-muted text-muted-foreground",
        )}
      >
        {kindLabels[edgeKind] ?? edgeKind}
      </span>
      <div
        className={cn("h-6 w-px", isDestructive ? "bg-destructive/30" : "bg-border")}
      />
    </motion.div>
  );
}
