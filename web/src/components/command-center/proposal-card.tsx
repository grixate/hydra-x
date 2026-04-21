import { useState } from "react";
import { HelpCircle, Sparkles } from "lucide-react";
import { Button } from "@/components/ui/button";
import { cn, relativeLabel } from "@/lib/utils";
import type { AgentTask } from "@/types";
import { AGENTS_BY_ID, agentLabel } from "./agents";
import { WhyPanel } from "@/components/graph/why-panel";

function readProposalField(payload: Record<string, unknown> | null, key: string): string | null {
  if (!payload) return null;
  const value = payload[key];
  return typeof value === "string" ? value : null;
}

export function ProposalCard({
  task,
  projectId,
  onReview,
  onDismiss,
}: {
  task: AgentTask;
  projectId?: number;
  onReview: () => void;
  onDismiss: () => void;
}) {
  const agent = AGENTS_BY_ID[task.agent_id];
  const AgentIcon = agent?.icon ?? Sparkles;
  const [whyOpen, setWhyOpen] = useState(false);

  const hasContextNode =
    task.context_type != null && task.context_id != null && projectId != null;

  const summary = readProposalField(task.proposal_payload, "summary") ?? task.title;
  const preview = readProposalField(task.proposal_payload, "preview");
  const type = readProposalField(task.proposal_payload, "type");
  const items = Array.isArray(task.proposal_payload?.items)
    ? (task.proposal_payload?.items as unknown[])
    : [];

  return (
    <div className="flex flex-col gap-3 rounded-lg border bg-card p-3 transition-colors hover:border-primary/40">
      <div className="flex items-start gap-2">
        <AgentIcon className="mt-0.5 h-4 w-4 shrink-0 text-emerald-500" />
        <div className="min-w-0 flex-1">
          <p className="text-xs font-medium uppercase tracking-widest text-muted-foreground">
            {agentLabel(task.agent_id)} proposes
          </p>
          <p className="mt-0.5 text-sm font-medium leading-snug">{summary}</p>
        </div>
        <span className="shrink-0 text-[10px] text-muted-foreground tabular-nums">
          {relativeLabel(task.last_state_change_at)}
        </span>
      </div>

      {preview ? (
        <p className={cn("line-clamp-3 text-xs text-muted-foreground/90")}>{preview}</p>
      ) : null}

      <div className="flex items-center justify-between">
        <span className="text-[10px] uppercase tracking-widest text-muted-foreground">
          {type ? `${type} · ` : ""}
          {items.length} item{items.length === 1 ? "" : "s"}
        </span>
        <div className="flex gap-1">
          {hasContextNode ? (
            <Button
              size="sm"
              variant="ghost"
              onClick={() => setWhyOpen(true)}
              aria-label="Explain why"
            >
              <HelpCircle className="h-3.5 w-3.5" />
            </Button>
          ) : null}
          <Button size="sm" variant="ghost" onClick={onDismiss}>
            Dismiss
          </Button>
          <Button size="sm" onClick={onReview}>
            Review
          </Button>
        </div>
      </div>

      {hasContextNode && projectId ? (
        <WhyPanel
          open={whyOpen}
          projectId={projectId}
          nodeType={task.context_type}
          nodeId={task.context_id}
          onClose={() => setWhyOpen(false)}
        />
      ) : null}
    </div>
  );
}
