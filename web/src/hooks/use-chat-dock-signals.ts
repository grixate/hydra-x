import { useEffect, useMemo, useState } from "react";

import { api } from "@/lib/api";
import { subscribeToProject } from "@/lib/project-channel";
import type { AgentTask, AgentTaskState } from "@/types";
import type { StackedAgent } from "@/components/chat/agent-avatar-stack";

const WORKING_STATES: ReadonlyArray<AgentTaskState> = [
  "running",
  "waiting_for_input",
  "proposing",
];

function isWorking(state: AgentTaskState): boolean {
  return WORKING_STATES.includes(state);
}

function stateToStack(state: AgentTaskState): StackedAgent["state"] {
  if (state === "running") return "working";
  if (state === "waiting_for_input") return "waiting";
  if (state === "proposing") return "proposing";
  if (state === "blocked") return "blocked";
  return "idle";
}

export interface ChatDockSignals {
  activeTasks: AgentTask[];
  workingAgents: StackedAgent[];
  proposalCount: number;
  anyWorking: boolean;
}

/**
 * Subscribes to agent_task.* events and keeps a live list of non-terminal
 * tasks. Shared between the collapsed chat bar and any expanded
 * pane element that wants to show activity signals.
 */
export function useChatDockSignals(projectId: number | null): ChatDockSignals {
  const [tasks, setTasks] = useState<Map<number, AgentTask>>(() => new Map());

  useEffect(() => {
    if (!projectId) {
      setTasks(new Map());
      return;
    }

    let cancelled = false;

    api
      .listAgentTasks(projectId, { exclude_terminal: true })
      .then((items) => {
        if (cancelled) return;
        const next = new Map<number, AgentTask>();
        for (const t of items ?? []) {
          if (isWorking(t.state)) next.set(t.id, t);
        }
        setTasks(next);
      })
      .catch(() => {});

    const upsert = (task: AgentTask | undefined) => {
      if (!task) return;
      setTasks((prev) => {
        const next = new Map(prev);
        if (isWorking(task.state)) {
          next.set(task.id, task);
        } else {
          next.delete(task.id);
        }
        return next;
      });
    };

    const unsub = subscribeToProject(projectId, [
      {
        event: "agent_task.created",
        handler: (payload) => upsert(payload.task as AgentTask | undefined),
      },
      {
        event: "agent_task.state_changed",
        handler: (payload) => upsert(payload.task as AgentTask | undefined),
      },
      {
        event: "agent_task.progress",
        handler: (payload) => upsert(payload.task as AgentTask | undefined),
      },
      {
        event: "agent_task.redirected",
        handler: (payload) => upsert(payload.task as AgentTask | undefined),
      },
    ]);

    return () => {
      cancelled = true;
      unsub();
    };
  }, [projectId]);

  return useMemo(() => {
    const activeTasks = Array.from(tasks.values());
    const seen = new Set<string>();
    const workingAgents: StackedAgent[] = [];
    let proposalCount = 0;

    for (const t of activeTasks) {
      if (t.state === "proposing") proposalCount++;
      if (!t.agent_id || seen.has(t.agent_id)) continue;
      seen.add(t.agent_id);
      workingAgents.push({ persona: t.agent_id, state: stateToStack(t.state) });
    }

    return {
      activeTasks,
      workingAgents,
      proposalCount,
      anyWorking: activeTasks.length > 0,
    };
  }, [tasks]);
}
