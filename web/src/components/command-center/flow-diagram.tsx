import { ArrowRight } from "lucide-react";
import { cn, relativeLabel } from "@/lib/utils";
import type { Flow } from "@/types";
import { AGENTS_BY_ID, agentLabel } from "./agents";

const STATUS_LABEL: Record<Flow["status"], string> = {
  ongoing: "Ongoing",
  complete: "Complete",
  stalled: "Stalled",
  cancelled: "Cancelled",
};

const STATUS_TONE: Record<Flow["status"], string> = {
  ongoing: "text-primary",
  complete: "text-emerald-500",
  stalled: "text-amber-500",
  cancelled: "text-muted-foreground",
};

export function FlowDiagram({
  flow,
  onAgentClick,
}: {
  flow: Flow;
  onAgentClick: (agentId: string) => void;
}) {
  return (
    <div className="flex min-w-[18rem] shrink-0 flex-col gap-2 rounded-lg border bg-card p-3">
      <div className="flex items-start justify-between gap-2">
        <p className="truncate text-sm font-medium">{flow.name}</p>
        <span
          className={cn("shrink-0 text-[10px] uppercase tracking-widest", STATUS_TONE[flow.status])}
        >
          {STATUS_LABEL[flow.status]}
        </span>
      </div>

      <div className="flex flex-wrap items-center gap-1.5">
        {flow.participating_agent_ids.map((id, idx) => {
          const agent = AGENTS_BY_ID[id];
          const Icon = agent?.icon;
          return (
            <div key={`${id}-${idx}`} className="flex items-center gap-1.5">
              {idx > 0 ? <ArrowRight className="h-3 w-3 text-muted-foreground/60" /> : null}
              <button
                type="button"
                onClick={() => onAgentClick(id)}
                className="inline-flex items-center gap-1 rounded-md border bg-background px-2 py-1 text-xs transition-colors hover:border-primary/40"
              >
                {Icon ? <Icon className="h-3 w-3" /> : null}
                <span>{agentLabel(id)}</span>
              </button>
            </div>
          );
        })}
      </div>

      <p className="text-[10px] text-muted-foreground">
        {flow.task_ids.length} tasks · updated {relativeLabel(flow.updated_at)}
      </p>
    </div>
  );
}
