import { useEffect, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { Bell } from "lucide-react";

import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Button } from "@/components/ui/button";
import { api } from "@/lib/api";
import { subscribeToProject } from "@/lib/project-channel";
import { showToast } from "@/components/ui/toast-notification";
import { cn, relativeLabel } from "@/lib/utils";
import type { AgentTask, Mention, MentionIntent, StreamEntry } from "@/types";
import { agentLabel } from "./agents";

type BellCounts = { activity: number; needs_you: number; blockers: number; total: number };

type AttentionTask = {
  id: number;
  title: string;
  state: string;
  agent_id: string;
  last_state_change_at: string;
};

function taskToAttention(task: AgentTask): AttentionTask {
  return {
    id: task.id,
    title: task.title,
    state: task.state,
    agent_id: task.agent_id,
    last_state_change_at: task.last_state_change_at,
  };
}

function upsertAttention(list: AttentionTask[], next: AttentionTask): AttentionTask[] {
  const existing = list.findIndex((entry) => entry.id === next.id);
  if (existing === -1) return [next, ...list];
  const copy = list.slice();
  copy[existing] = next;
  return copy;
}

function removeAttention(list: AttentionTask[], id: number): AttentionTask[] {
  return list.filter((entry) => entry.id !== id);
}

const ATTENTION_STATES = new Set(["proposing", "waiting_for_input", "blocked", "failed"]);

export function NotificationBell() {
  const { projectId } = useParams<{ projectId: string }>();
  const pid = projectId ? Number(projectId) : null;
  const navigate = useNavigate();

  const [counts, setCounts] = useState<BellCounts>({
    activity: 0,
    needs_you: 0,
    blockers: 0,
    total: 0,
  });
  const [attention, setAttention] = useState<AttentionTask[]>([]);
  const [recent, setRecent] = useState<StreamEntry[]>([]);

  useEffect(() => {
    if (!pid) return;

    let cancelled = false;

    Promise.all([
      api.getStreamEntryCounts(pid),
      api.listAgentTasks(pid, { exclude_terminal: true }),
      api.listStreamEntries(pid, { unread: true }),
    ])
      .then(([countsData, taskList, entries]) => {
        if (cancelled) return;
        setCounts(countsData);
        setAttention(
          taskList
            .filter((task) => ATTENTION_STATES.has(task.state))
            .map(taskToAttention)
            .slice(0, 20),
        );
        setRecent(entries.slice(0, 10));
      })
      .catch(() => {});

    return () => {
      cancelled = true;
    };
  }, [pid]);

  useEffect(() => {
    if (!pid) return;

    const onTaskEvent = (payload: Record<string, unknown>) => {
      const task = payload.task as AgentTask | undefined;
      if (!task) return;

      setAttention((current) =>
        ATTENTION_STATES.has(task.state)
          ? upsertAttention(current, taskToAttention(task))
          : removeAttention(current, task.id),
      );
    };

    const onStreamEntry = (payload: Record<string, unknown>) => {
      const entry = payload.stream_entry as StreamEntry | undefined;
      if (!entry) return;
      setRecent((current) => [entry, ...current].slice(0, 10));
      setCounts((current) => ({
        ...current,
        [entry.tab]: (current[entry.tab] ?? 0) + 1,
        total: current.total + 1,
      }));
    };

    // Coherence surfacing — fire a sonner toast when a new
    // medium/high contradiction is detected (spec §6 table).
    const onContradiction = (payload: Record<string, unknown>) => {
      const c = payload.contradiction as
        | { id: number; severity: string; explanation?: string }
        | undefined;
      if (!c || c.severity === "low") return;

      showToast(
        `Coherence found a contradiction${c.explanation ? `: ${c.explanation.slice(0, 80)}…` : "."}`,
        {
          label: "View",
          onClick: () => navigate(`/projects/${pid}/stream?tab=blockers`),
        },
      );
    };

    // B1.5 — disambiguate @-mentions with low-confidence intent.
    // The backend stores the default `share_context` + metadata flag;
    // we prompt the user to confirm or change it before side effects
    // (task spawn) happen.
    const onMention = (payload: Record<string, unknown>) => {
      const mention = payload.mention as Mention | undefined;
      if (!mention || !mention.metadata?.ambiguous_intent) return;

      const inferred = mention.metadata.inferred as MentionIntent | undefined;
      const target = agentLabel(mention.target_agent_id);

      const confirmIntent = async (intent: MentionIntent) => {
        try {
          await api.updateMentionIntent(pid, mention.id, intent);
        } catch {
          /* swallow — channel will re-broadcast or user can retry */
        }
      };

      showToast(`Did you want ${target} to handle this, or just see it?`, {
        label: inferred === "request_task" ? "Handle it" : "Share only",
        onClick: () => confirmIntent(inferred === "request_task" ? "request_task" : "share_context"),
      });
    };

    return subscribeToProject(pid, [
      { event: "agent_task.created", handler: onTaskEvent },
      { event: "agent_task.state_changed", handler: onTaskEvent },
      { event: "stream_entry.created", handler: onStreamEntry },
      { event: "contradiction.detected", handler: onContradiction },
      { event: "mention.created", handler: onMention },
    ]);
  }, [pid, navigate]);

  const attentionCount = attention.length + counts.needs_you + counts.blockers;
  const displayCount = attentionCount > 9 ? "9+" : String(attentionCount);

  function openTask(task: AttentionTask) {
    if (!pid) return;
    navigate(`/projects/${pid}/command-center?agent=${task.agent_id}`);
  }

  async function markAllRead() {
    if (!pid || recent.length === 0) return;
    const ids = recent.filter((entry) => !entry.read_at).map((entry) => entry.id);
    if (ids.length === 0) return;
    await api.markStreamEntriesRead(pid, ids);
    setRecent((current) => current.map((entry) => ({ ...entry, read_at: new Date().toISOString() })));
    setCounts({ activity: 0, needs_you: 0, blockers: 0, total: 0 });
  }

  if (!pid) return null;

  return (
    <div className="fixed right-4 top-3 z-40">
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button
            variant="outline"
            size="icon"
            className="relative h-8 w-8 bg-background/80 backdrop-blur"
            aria-label="Notifications"
          >
            <Bell className="h-4 w-4" />
            {attentionCount > 0 ? (
              <span
                className={cn(
                  "absolute -right-1 -top-1 flex h-4 min-w-4 items-center justify-center rounded-full px-1 text-[9px] font-bold tabular-nums text-background",
                  counts.blockers > 0 ? "bg-rose-500" : "bg-primary",
                )}
              >
                {displayCount}
              </span>
            ) : null}
          </Button>
        </DropdownMenuTrigger>

        <DropdownMenuContent align="end" className="w-[22rem] max-h-[32rem] overflow-y-auto">
          <DropdownMenuLabel className="flex items-center justify-between">
            <span>Attention</span>
            <span className="text-[10px] text-muted-foreground tabular-nums">
              {attention.length} tasks
            </span>
          </DropdownMenuLabel>
          {attention.length === 0 ? (
            <div className="px-3 pb-2 text-xs text-muted-foreground">Nothing requires action.</div>
          ) : (
            attention.slice(0, 6).map((task) => (
              <DropdownMenuItem key={task.id} onClick={() => openTask(task)} className="flex flex-col items-start">
                <span className="text-xs font-medium">{task.title}</span>
                <span className="text-[10px] text-muted-foreground">
                  {agentLabel(task.agent_id)} · {task.state.replace(/_/g, " ")} ·{" "}
                  {relativeLabel(task.last_state_change_at)}
                </span>
              </DropdownMenuItem>
            ))
          )}

          <DropdownMenuSeparator />

          <DropdownMenuLabel className="flex items-center justify-between">
            <span>Recent activity</span>
            <button
              type="button"
              onClick={markAllRead}
              className="text-[10px] text-muted-foreground hover:text-foreground"
            >
              Mark all read
            </button>
          </DropdownMenuLabel>
          {recent.length === 0 ? (
            <div className="px-3 pb-2 text-xs text-muted-foreground">No recent activity.</div>
          ) : (
            recent.slice(0, 6).map((entry) => (
              <DropdownMenuItem
                key={entry.id}
                onClick={() => navigate(`/projects/${pid}/command-center`)}
                className="flex flex-col items-start"
              >
                <span className={cn("text-xs", entry.read_at ? "text-muted-foreground" : "font-medium")}>
                  {entry.title}
                </span>
                <span className="text-[10px] text-muted-foreground">
                  {entry.tab.replace(/_/g, " ")} · {relativeLabel(entry.inserted_at)}
                </span>
              </DropdownMenuItem>
            ))
          )}
        </DropdownMenuContent>
      </DropdownMenu>
    </div>
  );
}
