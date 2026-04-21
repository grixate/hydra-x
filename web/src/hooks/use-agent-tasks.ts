import { useCallback, useEffect, useRef, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { subscribeToProject } from "@/lib/project-channel";
import type { AgentTask, ProposalItemDecision } from "@/types";

function extractFreshTask(err: unknown): AgentTask | null {
  if (err instanceof ApiError) {
    return err.data<AgentTask>();
  }
  return null;
}

export type AgentStatusSnapshot = {
  persona: string;
  state: string;
  summary?: string | null;
  active_count?: number;
  ready_count: number;
};

type UseAgentTasksResult = {
  tasks: AgentTask[];
  proposals: AgentTask[];
  statuses: AgentStatusSnapshot[];
  loading: boolean;
  error: string | null;
  pause: (task: AgentTask) => Promise<void>;
  cancel: (task: AgentTask) => Promise<void>;
  resume: (task: AgentTask) => Promise<void>;
  redirect: (task: AgentTask, refinement: string) => Promise<void>;
  recordDecisions: (task: AgentTask, decisions: ProposalItemDecision[]) => Promise<AgentTask>;
  applyProposal: (task: AgentTask) => Promise<void>;
  dismissProposal: (task: AgentTask) => Promise<void>;
};

function upsert(list: AgentTask[], next: AgentTask): AgentTask[] {
  const index = list.findIndex((entry) => entry.id === next.id);
  if (index === -1) {
    return [next, ...list];
  }
  const copy = list.slice();
  copy[index] = next;
  return copy;
}

function removeById(list: AgentTask[], id: number): AgentTask[] {
  return list.filter((entry) => entry.id !== id);
}

const TERMINAL_STATES = new Set(["completed", "rejected", "cancelled", "failed"]);

function readSeedCount(): number {
  if (typeof window === "undefined") return 0;
  const n = Number(new URLSearchParams(window.location.search).get("seed"));
  return Number.isFinite(n) && n > 0 ? Math.min(n, 50) : 0;
}

const SEED_AGENTS = [
  "researcher",
  "strategist",
  "architect",
  "designer",
  "memory_agent",
  "coherence",
  "continuous_research",
];
const SEED_STATES: AgentTask["state"][] = [
  "running",
  "waiting_for_input",
  "blocked",
  "completed",
  "running",
];

function generateSeedTasks(count: number): AgentTask[] {
  const now = Date.now();
  return Array.from({ length: count }, (_, i) => {
    const agent = SEED_AGENTS[i % SEED_AGENTS.length];
    const state = SEED_STATES[i % SEED_STATES.length];
    const iso = new Date(now - i * 1000 * 60 * 7).toISOString();
    return {
      id: -(i + 1),
      project_id: 0,
      agent_id: agent,
      title: `Seed task ${i + 1} — ${agent.replace(/_/g, " ")}`,
      state,
      prompt: "",
      summary: `Fake dev task ${i + 1} for layout testing. State: ${state.replace(/_/g, " ")}.`,
      refinement: null,
      last_state_change_at: iso,
      inserted_at: iso,
      updated_at: iso,
      proposal_items: [],
    } as unknown as AgentTask;
  });
}

export function useAgentTasks(projectId: number | null): UseAgentTasksResult {
  const [tasks, setTasks] = useState<AgentTask[]>([]);
  const [statuses, setStatuses] = useState<AgentStatusSnapshot[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refreshStatusesRef = useRef<() => void>(() => {});

  const refreshStatuses = useCallback(() => {
    if (!projectId) return;
    api
      .getAgentStatuses(projectId)
      .then((data) =>
        setStatuses(
          data.map((entry) => ({
            persona: entry.persona,
            state: entry.state,
            summary: entry.summary,
            active_count: entry.active_count,
            ready_count: entry.ready_count,
          })),
        ),
      )
      .catch(() => {});
  }, [projectId]);

  refreshStatusesRef.current = refreshStatuses;

  useEffect(() => {
    if (!projectId) {
      setTasks([]);
      setStatuses([]);
      setLoading(false);
      return;
    }

    // Clear previous project's tasks immediately so an in-flight channel
    // event from the prior project can't mutate state for the new one.
    setTasks([]);
    setStatuses([]);

    const seedCount = readSeedCount();

    let cancelled = false;
    setLoading(true);

    Promise.all([
      api.listAgentTasks(projectId, { exclude_terminal: true }),
      api.getAgentStatuses(projectId),
    ])
      .then(([taskList, statusList]) => {
        if (cancelled) return;
        const merged = seedCount > 0 ? [...generateSeedTasks(seedCount), ...taskList] : taskList;
        setTasks(merged);
        setStatuses(
          statusList.map((entry) => ({
            persona: entry.persona,
            state: entry.state,
            summary: entry.summary,
            active_count: entry.active_count,
            ready_count: entry.ready_count,
          })),
        );
        setError(null);
      })
      .catch((err: unknown) => {
        if (cancelled) return;
        setError(err instanceof Error ? err.message : "Failed to load");
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [projectId]);

  useEffect(() => {
    if (!projectId) return;

    const handleTaskPayload = (payload: Record<string, unknown>) => {
      const task = payload.task as AgentTask | undefined;
      if (!task) return;

      if (TERMINAL_STATES.has(task.state)) {
        setTasks((current) => removeById(current, task.id));
      } else {
        setTasks((current) => upsert(current, task));
      }

      refreshStatusesRef.current();
    };

    return subscribeToProject(projectId, [
      { event: "agent_task.created", handler: handleTaskPayload },
      { event: "agent_task.state_changed", handler: handleTaskPayload },
      { event: "agent_task.progress", handler: handleTaskPayload },
      { event: "agent_task.redirected", handler: handleTaskPayload },
    ]);
  }, [projectId]);

  const optimisticTransition = useCallback(
    async (task: AgentTask, nextState: AgentTask["state"]) => {
      if (!projectId) return;

      const previous = task;
      const optimistic: AgentTask = {
        ...task,
        state: nextState,
        last_state_change_at: new Date().toISOString(),
      };

      if (TERMINAL_STATES.has(nextState)) {
        setTasks((current) => removeById(current, task.id));
      } else {
        setTasks((current) => upsert(current, optimistic));
      }

      try {
        const updated = await api.transitionAgentTask(projectId, task.id, nextState);
        if (TERMINAL_STATES.has(updated.state)) {
          setTasks((current) => removeById(current, updated.id));
        } else {
          setTasks((current) => upsert(current, updated));
        }
      } catch (err) {
        // Revert to server-authoritative state. Prefer the `data` field on a
        // 409 stale response if present; else restore the pre-click task.
        const fresh = extractFreshTask(err) ?? previous;
        if (TERMINAL_STATES.has(fresh.state)) {
          setTasks((current) => removeById(current, fresh.id));
        } else {
          setTasks((current) => upsert(current, fresh));
        }
        throw err;
      }
    },
    [projectId],
  );

  const pause = useCallback((task: AgentTask) => optimisticTransition(task, "paused"), [optimisticTransition]);
  const cancel = useCallback((task: AgentTask) => optimisticTransition(task, "cancelled"), [optimisticTransition]);
  const resume = useCallback((task: AgentTask) => optimisticTransition(task, "running"), [optimisticTransition]);

  const redirect = useCallback(
    async (task: AgentTask, refinement: string) => {
      if (!projectId) return;
      await api.redirectAgentTask(projectId, task.id, refinement);
    },
    [projectId],
  );

  const recordDecisions = useCallback(
    async (task: AgentTask, decisions: ProposalItemDecision[]) => {
      if (!projectId) throw new Error("missing project");
      const updated = await api.recordProposalDecisions(projectId, task.id, decisions);
      setTasks((current) => upsert(current, updated));
      return updated;
    },
    [projectId],
  );

  const applyProposal = useCallback(
    async (task: AgentTask) => {
      if (!projectId) return;
      await api.applyProposal(projectId, task.id);
    },
    [projectId],
  );

  const dismissProposal = useCallback(
    async (task: AgentTask) => {
      if (!projectId) return;
      await api.dismissProposal(projectId, task.id);
    },
    [projectId],
  );

  const proposals = tasks.filter((task) => task.state === "proposing");

  return {
    tasks,
    proposals,
    statuses,
    loading,
    error,
    pause,
    cancel,
    resume,
    redirect,
    recordDecisions,
    applyProposal,
    dismissProposal,
  };
}
