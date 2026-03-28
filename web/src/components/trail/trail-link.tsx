import { cn } from "@/lib/utils";

interface TrailLinkProps {
  nodeType: string;
  nodeId: number;
  title?: string;
  onClick?: (nodeType: string, nodeId: number) => void;
  className?: string;
}

const typeLabels: Record<string, string> = {
  insight: "I",
  decision: "D",
  strategy: "S",
  requirement: "R",
  design_node: "Dn",
  architecture_node: "A",
  task: "T",
  learning: "L",
  signal: "Sg",
  source: "Src",
};

export function TrailLink({
  nodeType,
  nodeId,
  title,
  onClick,
  className,
}: TrailLinkProps) {
  return (
    <button
      type="button"
      onClick={() => onClick?.(nodeType, nodeId)}
      className={cn(
        "inline-flex items-center gap-1 rounded px-1.5 py-0.5 text-xs font-medium text-accent underline-offset-2 hover:underline",
        className,
      )}
    >
      <span className="rounded bg-ink/5 px-1 text-[9px] font-bold uppercase text-ink-soft">
        {typeLabels[nodeType] ?? nodeType.charAt(0).toUpperCase()}
      </span>
      {title ? title : `${nodeType}#${nodeId}`}
    </button>
  );
}
