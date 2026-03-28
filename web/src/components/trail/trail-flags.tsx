import type { TrailFlag } from "@/lib/api";
import { Badge } from "@/components/ui/badge";

interface TrailFlagsProps {
  flags: TrailFlag[];
}

export function TrailFlags({ flags }: TrailFlagsProps) {
  if (flags.length === 0) return null;

  return (
    <div className="space-y-2">
      <p className="text-[10px] font-bold uppercase tracking-[0.3em] text-ink-soft">
        Open flags
      </p>
      {flags.map((flag) => (
        <div
          key={flag.id}
          className="flex items-start gap-2 rounded-lg border border-accent/30 bg-accent/5 p-2"
        >
          <Badge variant="secondary" className="shrink-0 text-[9px]">
            {flag.flag_type}
          </Badge>
          <div className="min-w-0 flex-1">
            <p className="text-xs">{flag.reason}</p>
            <p className="mt-0.5 text-[10px] text-ink-soft">
              by {flag.source_agent}
            </p>
          </div>
        </div>
      ))}
    </div>
  );
}
