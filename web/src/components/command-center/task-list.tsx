import { useState } from "react";
import type { AgentTask } from "@/types";
import { TaskRow } from "./task-row";

export function TaskList({
  tasks,
  onPause,
  onCancel,
  onResume,
  onRedirect,
}: {
  tasks: AgentTask[];
  onPause: (task: AgentTask) => void;
  onCancel: (task: AgentTask) => void;
  onResume: (task: AgentTask) => void;
  onRedirect: (task: AgentTask, refinement: string) => void;
}) {
  const [expandedId, setExpandedId] = useState<number | null>(null);

  if (tasks.length === 0) {
    return (
      <div className="flex min-h-[12rem] flex-col items-center justify-center rounded-lg border border-dashed bg-muted/20 p-6 text-center">
        <p className="text-sm font-medium text-foreground">No active tasks</p>
        <p className="mt-1 text-xs text-muted-foreground">
          Agents are idle. Start work by chatting with an agent.
        </p>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-1.5">
      {tasks.map((task) => (
        <TaskRow
          key={task.id}
          task={task}
          expanded={expandedId === task.id}
          onToggleExpand={() => setExpandedId((current) => (current === task.id ? null : task.id))}
          onPause={() => onPause(task)}
          onCancel={() => onCancel(task)}
          onResume={() => onResume(task)}
          onRedirect={(refinement) => onRedirect(task, refinement)}
        />
      ))}
    </div>
  );
}
