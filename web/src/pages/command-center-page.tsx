import { useEffect, useMemo, useRef, useState } from "react";
import { useParams, useSearchParams } from "react-router-dom";
import { Zap } from "lucide-react";

import { AgentStatusStrip } from "@/components/command-center/agent-status-strip";
import { ProposalQueue } from "@/components/command-center/proposal-queue";
import { ProposalReviewPanel } from "@/components/command-center/proposal-review-panel";
import { TaskFilters, type TaskFilter } from "@/components/command-center/task-filters";
import { TaskList } from "@/components/command-center/task-list";
import { AGENTS } from "@/components/command-center/agents";
import { useAgentTasks } from "@/hooks/use-agent-tasks";
import { Skeleton } from "@/components/ui/skeleton";
import type { AgentTask, AgentTaskState } from "@/types";

function matchesFilter(task: AgentTask, filter: TaskFilter): boolean {
  switch (filter) {
    case "all":
      return true;
    case "needs_me":
      return task.state === "waiting_for_input";
    case "running":
      return task.state === "running";
    case "blocked":
      return task.state === "blocked";
  }
}

const FILTER_STATE_KEYS: Partial<Record<TaskFilter, AgentTaskState>> = {
  needs_me: "waiting_for_input",
  running: "running",
  blocked: "blocked",
};

function filterStorageKey(projectId: string | undefined) {
  return projectId ? `cc-filters-${projectId}` : null;
}

function loadPersisted(projectId: string | undefined): {
  filter: TaskFilter;
  search: string;
  agentFilter: string | null;
} {
  const key = filterStorageKey(projectId);
  if (!key) return { filter: "all", search: "", agentFilter: null };
  try {
    const raw = localStorage.getItem(key);
    if (!raw) return { filter: "all", search: "", agentFilter: null };
    const parsed = JSON.parse(raw) as {
      filter?: TaskFilter;
      search?: string;
      agentFilter?: string | null;
    };
    return {
      filter: parsed.filter ?? "all",
      search: parsed.search ?? "",
      agentFilter: parsed.agentFilter ?? null,
    };
  } catch {
    return { filter: "all", search: "", agentFilter: null };
  }
}

export function CommandCenterPage() {
  const { projectId } = useParams<{ projectId: string }>();
  const [searchParams, setSearchParams] = useSearchParams();
  const pid = projectId ? Number(projectId) : null;

  const initialAgentParam = searchParams.get("agent");
  const persisted = useMemo(() => loadPersisted(projectId), [projectId]);

  const [filter, setFilter] = useState<TaskFilter>(persisted.filter);
  const [search, setSearch] = useState(persisted.search);
  const [agentFilter, setAgentFilter] = useState<string | null>(
    initialAgentParam ?? persisted.agentFilter,
  );
  const [reviewTaskId, setReviewTaskId] = useState<number | null>(null);
  const [applying, setApplying] = useState(false);
  const searchInputRef = useRef<HTMLInputElement | null>(null);

  useEffect(() => {
    const key = filterStorageKey(projectId);
    if (!key) return;
    localStorage.setItem(key, JSON.stringify({ filter, search, agentFilter }));
  }, [projectId, filter, search, agentFilter]);

  useEffect(() => {
    const next = new URLSearchParams(searchParams);
    if (agentFilter) {
      next.set("agent", agentFilter);
    } else {
      next.delete("agent");
    }
    if (next.toString() !== searchParams.toString()) {
      setSearchParams(next, { replace: true });
    }
  }, [agentFilter, searchParams, setSearchParams]);

  useEffect(() => {
    function onKey(event: KeyboardEvent) {
      const target = event.target as HTMLElement | null;
      const inEditable =
        target &&
        (target.tagName === "INPUT" ||
          target.tagName === "TEXTAREA" ||
          target.isContentEditable);

      if (event.key === "Escape") {
        if (reviewTaskId !== null) return; // sheet handles its own
        if (agentFilter || search || filter !== "all") {
          setAgentFilter(null);
          setSearch("");
          setFilter("all");
        }
        return;
      }

      if (inEditable) return;
      if (event.metaKey || event.ctrlKey || event.altKey) return;

      if (event.key === "/") {
        event.preventDefault();
        searchInputRef.current?.focus();
        return;
      }

      if (event.key.toLowerCase() === "a") {
        event.preventDefault();
        setFilter("all");
        setAgentFilter(null);
        return;
      }

      if (event.key.toLowerCase() === "n") {
        event.preventDefault();
        setFilter("needs_me");
        return;
      }

      const digit = Number(event.key);
      if (Number.isFinite(digit) && digit >= 1 && digit <= AGENTS.length) {
        event.preventDefault();
        const agent = AGENTS[digit - 1];
        if (agent) setAgentFilter(agent.id);
      }
    }

    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [agentFilter, search, filter, reviewTaskId]);

  const {
    tasks,
    proposals,
    statuses,
    loading,
    pause,
    cancel,
    resume,
    redirect,
    recordDecisions,
    applyProposal,
    dismissProposal,
  } = useAgentTasks(pid);

  const visibleTasks = useMemo(() => {
    const lower = search.trim().toLowerCase();
    return tasks.filter((task) => {
      if (task.state === "proposing") return false;
      if (agentFilter && task.agent_id !== agentFilter) return false;
      if (!matchesFilter(task, filter)) return false;
      if (lower) {
        const haystack = `${task.title} ${task.description ?? ""}`.toLowerCase();
        if (!haystack.includes(lower)) return false;
      }
      return true;
    });
  }, [tasks, filter, search, agentFilter]);

  const visibleProposals = useMemo(
    () => (agentFilter ? proposals.filter((p) => p.agent_id === agentFilter) : proposals),
    [proposals, agentFilter],
  );

  const reviewTask = reviewTaskId
    ? tasks.find((task) => task.id === reviewTaskId) ?? null
    : null;

  const filterStateHint = FILTER_STATE_KEYS[filter];
  const filterSummary = filterStateHint
    ? `${visibleTasks.length} in ${filterStateHint.replace(/_/g, " ")}`
    : `${visibleTasks.length} tasks`;

  return (
    <div className="flex flex-col gap-4 p-4 lg:p-6">
      <div className="flex items-center gap-3">
        <Zap className="h-5 w-5 text-primary" />
        <div>
          <h1 className="text-xl font-semibold">Command Center</h1>
          <p className="text-xs text-muted-foreground">
            Live view of all agentic work in this project.
          </p>
        </div>
      </div>

      {loading ? (
        <>
          <Skeleton className="h-[92px] w-full" />
          <Skeleton className="h-[12rem] w-full" />
        </>
      ) : (
        <>
          <AgentStatusStrip
            statuses={statuses}
            selectedAgentId={agentFilter}
            onSelectAgent={setAgentFilter}
          />

          <div className="grid gap-4 @container lg:grid-cols-[minmax(0,3fr)_minmax(0,2fr)]">
            <div className="flex flex-col gap-3 rounded-lg border bg-card p-3">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <TaskFilters
                  ref={searchInputRef}
                  filter={filter}
                  onFilterChange={setFilter}
                  search={search}
                  onSearchChange={setSearch}
                  agentFilter={agentFilter}
                  onClearAgentFilter={() => setAgentFilter(null)}
                />
                <span className="text-xs text-muted-foreground tabular-nums">{filterSummary}</span>
              </div>

              <TaskList
                tasks={visibleTasks}
                onPause={pause}
                onCancel={cancel}
                onResume={resume}
                onRedirect={redirect}
              />
            </div>

            <div className="flex flex-col gap-3 rounded-lg border bg-card p-3">
              <div className="flex items-center justify-between">
                <h2 className="text-sm font-semibold">Proposals</h2>
                <span className="text-xs text-muted-foreground tabular-nums">
                  {visibleProposals.length} awaiting review
                </span>
              </div>
              <ProposalQueue
                proposals={visibleProposals}
                projectId={pid ?? undefined}
                onReview={(task) => setReviewTaskId(task.id)}
                onDismiss={(task) => {
                  if (confirm("Dismiss this proposal?")) dismissProposal(task);
                }}
              />
            </div>
          </div>

        </>
      )}

      <ProposalReviewPanel
        task={reviewTask}
        open={Boolean(reviewTask)}
        onClose={() => setReviewTaskId(null)}
        applying={applying}
        onRecord={async (decisions) => {
          if (!reviewTask) return;
          await recordDecisions(reviewTask, decisions);
        }}
        onApply={async () => {
          if (!reviewTask) return;
          setApplying(true);
          try {
            await applyProposal(reviewTask);
            setReviewTaskId(null);
          } finally {
            setApplying(false);
          }
        }}
      />
    </div>
  );
}
