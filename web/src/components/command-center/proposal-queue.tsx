import type { AgentTask } from "@/types";
import { ProposalCard } from "./proposal-card";

export function ProposalQueue({
  proposals,
  projectId,
  onReview,
  onDismiss,
}: {
  proposals: AgentTask[];
  projectId?: number;
  onReview: (task: AgentTask) => void;
  onDismiss: (task: AgentTask) => void;
}) {
  if (proposals.length === 0) {
    return (
      <div className="flex min-h-[8rem] flex-col items-center justify-center rounded-lg border border-dashed bg-muted/20 p-4 text-center">
        <p className="text-xs text-muted-foreground">
          No proposals awaiting review.
        </p>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-2">
      {proposals.map((task) => (
        <ProposalCard
          key={task.id}
          task={task}
          projectId={projectId}
          onReview={() => onReview(task)}
          onDismiss={() => onDismiss(task)}
        />
      ))}
    </div>
  );
}
