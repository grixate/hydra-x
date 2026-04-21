import { useState } from "react";
import {
  Ban,
  CheckCircle2,
  CircleAlert,
  CirclePause,
  CirclePlay,
  Loader2,
  PauseCircle,
  RotateCw,
  Sparkles,
  TriangleAlert,
  XCircle,
} from "lucide-react";
import type { LucideIcon } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { cn, relativeLabel } from "@/lib/utils";
import type { AgentTask } from "@/types";
import { AGENTS_BY_ID, agentLabel } from "./agents";

const STATE_ICON: Record<string, { icon: LucideIcon; className: string; label: string }> = {
  pending: { icon: CirclePause, className: "text-muted-foreground", label: "Pending" },
  running: { icon: Loader2, className: "text-primary animate-spin", label: "Running" },
  paused: { icon: PauseCircle, className: "text-muted-foreground", label: "Paused" },
  waiting_for_input: { icon: TriangleAlert, className: "text-amber-500", label: "Needs you" },
  blocked: { icon: Ban, className: "text-rose-500", label: "Blocked" },
  proposing: { icon: Sparkles, className: "text-emerald-500", label: "Proposing" },
  completed: { icon: CheckCircle2, className: "text-emerald-500", label: "Completed" },
  rejected: { icon: XCircle, className: "text-muted-foreground", label: "Rejected" },
  cancelled: { icon: XCircle, className: "text-muted-foreground", label: "Cancelled" },
  failed: { icon: CircleAlert, className: "text-rose-500", label: "Failed" },
};

export function TaskRow({
  task,
  expanded,
  onToggleExpand,
  onPause,
  onCancel,
  onResume,
  onRedirect,
}: {
  task: AgentTask;
  expanded: boolean;
  onToggleExpand: () => void;
  onPause: () => void;
  onCancel: () => void;
  onResume: () => void;
  onRedirect: (refinement: string) => void;
}) {
  const [refinement, setRefinement] = useState("");
  const [redirectOpen, setRedirectOpen] = useState(false);

  const agent = AGENTS_BY_ID[task.agent_id];
  const AgentIcon = agent?.icon;
  const stateInfo = STATE_ICON[task.state] ?? STATE_ICON.pending;
  const StateIcon = stateInfo.icon;

  const showProgress =
    task.state === "running" &&
    typeof task.progress_current === "number" &&
    typeof task.progress_total === "number" &&
    task.progress_total > 0;
  const pct = showProgress
    ? Math.min(100, Math.round(((task.progress_current as number) / (task.progress_total as number)) * 100))
    : 0;

  const isPauseable = task.state === "running";
  const isResumable = task.state === "paused";
  const isCancellable = !["completed", "rejected", "cancelled", "failed"].includes(task.state);

  return (
    <div
      className={cn(
        "group flex flex-col rounded-lg border bg-card transition-colors",
        expanded && "border-primary/40",
      )}
    >
      <button
        type="button"
        onClick={onToggleExpand}
        className="flex w-full items-center gap-3 px-3 py-2.5 text-left"
      >
        {AgentIcon ? (
          <AgentIcon className="h-4 w-4 shrink-0 text-muted-foreground" />
        ) : (
          <div className="h-4 w-4" />
        )}
        <StateIcon className={cn("h-4 w-4 shrink-0", stateInfo.className)} />

        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2">
            <p className="truncate text-sm font-medium">{task.title}</p>
            {task.priority === "urgent" || task.priority === "high" ? (
              <span className="shrink-0 rounded bg-amber-500/10 px-1.5 py-0.5 text-[10px] uppercase text-amber-600">
                {task.priority}
              </span>
            ) : null}
          </div>
          {task.state_reason && !expanded ? (
            <p className="truncate text-[11px] text-muted-foreground/80">{task.state_reason}</p>
          ) : null}
        </div>

        {showProgress ? (
          <div className="hidden w-20 shrink-0 md:block">
            <div className="h-1 w-full rounded-full bg-muted">
              <div className="h-1 rounded-full bg-primary transition-all" style={{ width: `${pct}%` }} />
            </div>
            <p className="mt-0.5 text-right text-[10px] text-muted-foreground tabular-nums">
              {task.progress_current}/{task.progress_total}
            </p>
          </div>
        ) : null}

        <span className="shrink-0 text-[11px] text-muted-foreground tabular-nums">
          {relativeLabel(task.last_state_change_at)}
        </span>
      </button>

      {expanded ? (
        <div className="border-t px-3 py-3">
          <p className="text-xs uppercase tracking-widest text-muted-foreground">
            {agentLabel(task.agent_id)} · {stateInfo.label}
          </p>
          {task.description ? (
            <p className="mt-1.5 text-sm text-foreground">{task.description}</p>
          ) : null}
          {task.state_reason ? (
            <p className="mt-1.5 text-sm text-rose-600">{task.state_reason}</p>
          ) : null}

          <div className="mt-3 flex flex-wrap items-center gap-2">
            {isResumable ? (
              <Button size="sm" variant="outline" onClick={onResume}>
                <CirclePlay className="h-3.5 w-3.5" />
                Resume
              </Button>
            ) : null}
            {isPauseable ? (
              <Button size="sm" variant="outline" onClick={onPause}>
                <CirclePause className="h-3.5 w-3.5" />
                Pause
              </Button>
            ) : null}
            {isCancellable ? (
              <Button size="sm" variant="outline" onClick={onCancel}>
                <XCircle className="h-3.5 w-3.5" />
                Cancel
              </Button>
            ) : null}
            {!redirectOpen && isCancellable ? (
              <Button size="sm" variant="outline" onClick={() => setRedirectOpen(true)}>
                <RotateCw className="h-3.5 w-3.5" />
                Redirect
              </Button>
            ) : null}
          </div>

          {redirectOpen ? (
            <form
              className="mt-3 flex gap-2"
              onSubmit={(event) => {
                event.preventDefault();
                if (!refinement.trim()) return;
                onRedirect(refinement.trim());
                setRefinement("");
                setRedirectOpen(false);
              }}
            >
              <Input
                autoFocus
                placeholder="Refinement for the agent..."
                value={refinement}
                onChange={(event) => setRefinement(event.target.value)}
              />
              <Button size="sm" type="submit">
                Send
              </Button>
              <Button
                size="sm"
                variant="ghost"
                type="button"
                onClick={() => {
                  setRedirectOpen(false);
                  setRefinement("");
                }}
              >
                Cancel
              </Button>
            </form>
          ) : null}
        </div>
      ) : null}
    </div>
  );
}
