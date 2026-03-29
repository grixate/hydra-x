import { NodeTypeIcon, nodeTypeLabel } from "./node-type-icon";
import { cn } from "@/lib/utils";

interface ConnectionChipProps {
  nodeType: string;
  count: number;
  onClick?: (nodeType: string) => void;
  className?: string;
}

export function ConnectionChip({
  nodeType,
  count,
  onClick,
  className,
}: ConnectionChipProps) {
  if (count <= 0) return null;

  return (
    <button
      type="button"
      onClick={(e) => {
        e.stopPropagation();
        onClick?.(nodeType);
      }}
      className={cn(
        "inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-[11px] transition-colors",
        "text-muted-foreground hover:bg-accent hover:text-accent-foreground",
        className,
      )}
    >
      <NodeTypeIcon nodeType={nodeType} className="h-3 w-3" />
      <span>
        {count} {count === 1 ? nodeTypeLabel(nodeType).toLowerCase() : nodeTypeLabel(nodeType).toLowerCase() + "s"}
      </span>
    </button>
  );
}

interface ConnectionChipsProps {
  connections: Record<string, number>;
  onChipClick?: (nodeType: string) => void;
  className?: string;
}

export function ConnectionChips({
  connections,
  onChipClick,
  className,
}: ConnectionChipsProps) {
  const entries = Object.entries(connections).filter(([, count]) => count > 0);
  if (entries.length === 0) return null;

  return (
    <div className={cn("flex flex-wrap gap-1.5", className)}>
      {entries.map(([nodeType, count]) => (
        <ConnectionChip
          key={nodeType}
          nodeType={nodeType}
          count={count}
          onClick={onChipClick}
        />
      ))}
    </div>
  );
}
