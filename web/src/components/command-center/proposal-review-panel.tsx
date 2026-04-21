import { useEffect, useMemo, useState } from "react";
import { Check, CircleDashed, X } from "lucide-react";

import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import type { AgentTask, ProposalDecision, ProposalItemDecision } from "@/types";
import { agentLabel } from "./agents";

type DecisionState = Record<number, ProposalDecision>;

function readItems(task: AgentTask | null): Array<Record<string, unknown>> {
  if (!task) return [];
  const raw = task.proposal_payload?.items;
  return Array.isArray(raw) ? (raw as Array<Record<string, unknown>>) : [];
}

function readInitialDecisions(task: AgentTask | null): DecisionState {
  if (!task) return {};
  const prior = task.proposal_payload?.item_decisions;
  if (!Array.isArray(prior)) return {};
  const state: DecisionState = {};
  for (const entry of prior as ProposalItemDecision[]) {
    if (typeof entry.item_index === "number" && entry.decision) {
      state[entry.item_index] = entry.decision;
    }
  }
  return state;
}

function itemTitle(item: Record<string, unknown>, index: number): string {
  const explicit =
    (typeof item.title === "string" && item.title) ||
    (typeof item.summary === "string" && item.summary) ||
    (typeof item.explanation === "string" && item.explanation) ||
    (typeof item.extracted_insight === "string" && item.extracted_insight);
  return explicit || `Item ${index + 1}`;
}

function itemPreview(item: Record<string, unknown>): string | null {
  const content =
    (typeof item.content === "string" && item.content) ||
    (typeof item.rationale === "string" && item.rationale) ||
    (typeof item.supporting_quote === "string" && item.supporting_quote) ||
    null;
  return content;
}

export function ProposalReviewPanel({
  task,
  open,
  onClose,
  onRecord,
  onApply,
  applying,
}: {
  task: AgentTask | null;
  open: boolean;
  onClose: () => void;
  onRecord: (decisions: ProposalItemDecision[]) => Promise<void>;
  onApply: () => Promise<void>;
  applying: boolean;
}) {
  const items = readItems(task);
  const [decisions, setDecisions] = useState<DecisionState>({});

  useEffect(() => {
    if (open && task) {
      setDecisions(readInitialDecisions(task));
    }
  }, [open, task]);

  const summary = useMemo(() => {
    const counts = { accepted: 0, rejected: 0, deferred: 0, pending: 0 };
    for (let i = 0; i < items.length; i++) {
      const d = decisions[i];
      if (d === "accepted") counts.accepted += 1;
      else if (d === "rejected") counts.rejected += 1;
      else if (d === "deferred") counts.deferred += 1;
      else counts.pending += 1;
    }
    return counts;
  }, [items.length, decisions]);

  async function acceptAll() {
    const next: DecisionState = {};
    for (let i = 0; i < items.length; i++) next[i] = "accepted";
    setDecisions(next);
    await onRecord(
      items.map((_, i) => ({ item_index: i, decision: "accepted" as const })),
    );
  }

  function setDecision(index: number, decision: ProposalDecision) {
    setDecisions((current) => ({ ...current, [index]: decision }));
  }

  async function saveAndApply() {
    const payload: ProposalItemDecision[] = Object.entries(decisions).map(
      ([idx, decision]) => ({ item_index: Number(idx), decision }),
    );
    if (payload.length === 0) return;
    await onRecord(payload);
    await onApply();
  }

  return (
    <Sheet open={open} onOpenChange={(value) => (!value ? onClose() : undefined)}>
      <SheetContent className="w-full overflow-y-auto sm:max-w-xl">
        {task ? (
          <>
            <SheetHeader>
              <SheetTitle>Review: {task.title}</SheetTitle>
              <SheetDescription>
                {agentLabel(task.agent_id)} · {items.length} item{items.length === 1 ? "" : "s"}
              </SheetDescription>
            </SheetHeader>

            <div className="mt-4 flex flex-wrap items-center gap-2 px-4">
              <Button size="sm" variant="outline" onClick={acceptAll} disabled={items.length === 0}>
                <Check className="h-3.5 w-3.5" />
                Accept all
              </Button>
              <span className="text-xs text-muted-foreground">
                {summary.accepted} accepted · {summary.rejected} rejected ·{" "}
                {summary.deferred} deferred · {summary.pending} pending
              </span>
            </div>

            <div className="mt-3 flex flex-col gap-2 px-4 pb-4">
              {items.length === 0 ? (
                <div className="rounded-lg border border-dashed bg-muted/30 p-4 text-center text-xs text-muted-foreground">
                  This proposal has no itemised payload. Use Accept / Reject on the whole task.
                </div>
              ) : (
                items.map((item, index) => {
                  const decision = decisions[index];
                  return (
                    <div
                      key={index}
                      className={cn(
                        "flex flex-col gap-1 rounded-lg border p-2.5",
                        decision === "accepted" && "border-emerald-500/40 bg-emerald-500/5",
                        decision === "rejected" && "border-rose-500/40 bg-rose-500/5",
                        decision === "deferred" && "border-amber-500/40 bg-amber-500/5",
                      )}
                    >
                      <p className="text-sm font-medium leading-snug">{itemTitle(item, index)}</p>
                      {itemPreview(item) ? (
                        <p className="text-xs text-muted-foreground/90">{itemPreview(item)}</p>
                      ) : null}

                      <div className="mt-1 flex gap-1">
                        <Button
                          size="sm"
                          variant={decision === "accepted" ? "default" : "outline"}
                          onClick={() => setDecision(index, "accepted")}
                        >
                          <Check className="h-3 w-3" />
                          Accept
                        </Button>
                        <Button
                          size="sm"
                          variant={decision === "rejected" ? "default" : "outline"}
                          onClick={() => setDecision(index, "rejected")}
                        >
                          <X className="h-3 w-3" />
                          Reject
                        </Button>
                        <Button
                          size="sm"
                          variant={decision === "deferred" ? "default" : "outline"}
                          onClick={() => setDecision(index, "deferred")}
                        >
                          <CircleDashed className="h-3 w-3" />
                          Defer
                        </Button>
                      </div>
                    </div>
                  );
                })
              )}
            </div>

            <div className="sticky bottom-0 flex items-center justify-end gap-2 border-t bg-background px-4 py-3">
              <Button variant="ghost" onClick={onClose} disabled={applying}>
                Close
              </Button>
              <Button
                onClick={saveAndApply}
                disabled={applying || (summary.accepted + summary.rejected + summary.deferred) === 0}
              >
                Apply decisions
              </Button>
            </div>
          </>
        ) : null}
      </SheetContent>
    </Sheet>
  );
}
