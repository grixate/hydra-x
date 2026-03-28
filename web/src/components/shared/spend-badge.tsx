import { cn } from "@/lib/utils";

interface SpendBadgeProps {
  costCents?: number | null;
  tokens?: number | null;
  className?: string;
}

export function SpendBadge({ costCents, tokens, className }: SpendBadgeProps) {
  if (!costCents && !tokens) return null;

  const dollars = costCents ? (costCents / 100).toFixed(2) : null;

  return (
    <span
      className={cn(
        "inline-flex items-center text-[10px] text-[var(--ink-soft)]",
        className,
      )}
      title={tokens ? `${tokens.toLocaleString()} tokens` : undefined}
    >
      {dollars ? `$${dollars}` : `${tokens?.toLocaleString()} tok`}
    </span>
  );
}
