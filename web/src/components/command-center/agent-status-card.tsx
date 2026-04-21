import { cn } from "@/lib/utils";
import type { AgentDefinition } from "./agents";

export type AgentStatus = {
  persona: string;
  state: string;
  summary?: string | null;
  active_count?: number;
  ready_count?: number;
};

const STATE_DOT: Record<string, string> = {
  idle: "bg-muted-foreground/40",
  working: "bg-primary animate-pulse",
  running: "bg-primary animate-pulse",
  waiting_for_input: "bg-amber-500",
  blocked: "bg-rose-500",
  proposing: "bg-emerald-500",
  paused: "bg-muted-foreground/60",
};

const STATE_LABEL: Record<string, string> = {
  idle: "Idle",
  working: "Working",
  running: "Working",
  waiting_for_input: "Needs you",
  blocked: "Blocked",
  proposing: "Proposing",
  paused: "Paused",
};

export function AgentStatusCard({
  agent,
  status,
  selected,
  onSelect,
}: {
  agent: AgentDefinition;
  status: AgentStatus | undefined;
  selected: boolean;
  onSelect: () => void;
}) {
  const state = status?.state ?? "idle";
  const activeCount = status?.active_count ?? 0;
  const summary = status?.summary?.trim();

  return (
    <button
      type="button"
      onClick={onSelect}
      className={cn(
        "flex min-w-0 flex-1 flex-col items-start gap-1.5 rounded-lg border bg-card p-3 text-left transition-colors",
        "hover:border-primary/40",
        selected && "border-primary bg-primary/5",
      )}
    >
      <div className="flex w-full items-center gap-2">
        <agent.icon className="h-4 w-4 shrink-0 text-muted-foreground" />
        <span className="truncate text-sm font-medium">{agent.label}</span>
        {activeCount > 1 ? (
          <span className="ml-auto shrink-0 rounded-full bg-muted px-1.5 text-[10px] tabular-nums text-muted-foreground">
            {activeCount}
          </span>
        ) : null}
      </div>

      <div className="flex items-center gap-1.5">
        <span className={cn("h-1.5 w-1.5 shrink-0 rounded-full", STATE_DOT[state] ?? STATE_DOT.idle)} />
        <span className="text-[11px] text-muted-foreground">
          {STATE_LABEL[state] ?? state}
        </span>
      </div>

      <p className="line-clamp-2 min-h-[2.25rem] text-[11px] text-muted-foreground/80">
        {summary || (state === "idle" ? "—" : "")}
      </p>
    </button>
  );
}
