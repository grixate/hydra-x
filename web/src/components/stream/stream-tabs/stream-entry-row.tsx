import { useEffect, useRef, useState, type MouseEvent } from "react";
import { useParams } from "react-router-dom";
import { AlertTriangle, MoreHorizontal, User } from "lucide-react";
import type { LucideIcon } from "lucide-react";

import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { api } from "@/lib/api";
import { cn } from "@/lib/utils";
import { AGENTS_BY_ID, agentLabel } from "@/components/command-center/agents";
import { dispatchAgentChatPaneSwitch } from "@/components/chat/agent-chat-pane";
import type { StreamTab, StreamTabItem } from "@/types";

const PRIMARY_LABEL: Partial<Record<StreamTabItem["kind"], string>> = {
  proposing: "Review",
  waiting_for_input: "Reply",
  blocked: "Resolve",
  failed: "View error",
  stalled_flow: "Inspect",
  contradiction: "Review",
};

export function StreamEntryRow({
  item,
  tab,
  onAction,
  onEscape,
  onOpenSpotlight,
}: {
  item: StreamTabItem;
  tab: StreamTab;
  onAction?: () => void;
  onEscape?: () => void;
  onOpenSpotlight?: (item: StreamTabItem) => void;
}) {
  const { projectId } = useParams<{ projectId: string }>();
  const [busy, setBusy] = useState(false);

  const agent = item.actor_agent_id ? AGENTS_BY_ID[item.actor_agent_id] : null;
  const actorName = item.actor_agent_id ? agentLabel(item.actor_agent_id) : "System";
  const AvatarIcon: LucideIcon = agent?.icon ?? User;

  const primaryLabel =
    PRIMARY_LABEL[item.kind] ??
    (tab === "activity" ? "View" : tab === "blockers" ? "Resolve" : "Review");
  const timeLabel = formatTimeLabel(item, tab);
  const contextLabel = formatContextLabel(item);

  const blocker =
    tab === "blockers" ||
    item.kind === "blocked" ||
    item.kind === "failed" ||
    item.kind === "contradiction";
  const needsYou = tab === "needs_you" && !blocker;

  const pid = projectId ? Number(projectId) : null;
  const hasTaskActions = Boolean(item.source_task_id) && Boolean(pid);
  const hasEntryActions = Boolean(item.stream_entry_id) && Boolean(pid);

  const [ctxMenu, setCtxMenu] = useState<{ x: number; y: number } | null>(null);
  const articleRef = useRef<HTMLElement | null>(null);

  function openSpotlight() {
    onOpenSpotlight?.(item);
  }

  function openContextMenu(e: MouseEvent) {
    if (!pid || !item.stream_entry_id) return;
    e.preventDefault();
    setCtxMenu({ x: e.clientX, y: e.clientY });
  }

  async function runMarkRead() {
    if (!pid || !item.stream_entry_id || busy) return;
    setCtxMenu(null);
    setBusy(true);
    try {
      await api.markStreamEntriesRead(pid, [item.stream_entry_id]);
      onAction?.();
    } finally {
      setBusy(false);
    }
  }

  async function runHide() {
    if (!pid || !item.stream_entry_id || busy) return;
    setCtxMenu(null);
    setBusy(true);
    try {
      await api.dismissStreamEntry(pid, item.stream_entry_id);
      onAction?.();
    } finally {
      setBusy(false);
    }
  }

  function handleTalk() {
    if (!item.actor_agent_id) return;
    dispatchAgentChatPaneSwitch(item.actor_agent_id);
  }

  async function runDefer(hours: number) {
    if (!pid || !item.source_task_id || busy) return;
    setBusy(true);
    try {
      await api.deferAgentTask(pid, item.source_task_id, hours);
      onAction?.();
    } finally {
      setBusy(false);
    }
  }

  async function runCancelTask() {
    if (!pid || !item.source_task_id || busy) return;
    setBusy(true);
    try {
      await api.transitionAgentTask(pid, item.source_task_id, "cancelled");
      onAction?.();
    } finally {
      setBusy(false);
    }
  }

  async function runDismiss() {
    if (!pid || !item.stream_entry_id || busy) return;
    setBusy(true);
    try {
      await api.dismissStreamEntry(pid, item.stream_entry_id);
      onAction?.();
    } finally {
      setBusy(false);
    }
  }

  const stop = (e: MouseEvent) => e.stopPropagation();

  return (
    <article
      ref={articleRef}
      data-stream-item
      tabIndex={0}
      aria-label={ariaLabelFor(item, actorName, timeLabel)}
      onClick={openSpotlight}
      onContextMenu={openContextMenu}
      onKeyDown={(e) => handleRowKey(e, { openSpotlight, onEscape })}
      className={cn(
        "group flex cursor-pointer gap-3 rounded-md px-2 py-3 transition-colors hover:bg-muted/40 focus-visible:bg-muted/40 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/30",
        busy && "pointer-events-none opacity-50",
      )}
    >
      <div
        className={cn(
          "mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-full",
          blocker
            ? "bg-rose-100 text-rose-700"
            : needsYou
              ? "bg-amber-100 text-amber-700"
              : "bg-muted text-muted-foreground",
        )}
        aria-hidden
      >
        <AvatarIcon className="h-4 w-4" />
      </div>

      <div className="min-w-0 flex-1">
        <div className="flex items-baseline gap-1.5 text-sm">
          <span className="font-medium text-foreground">{actorName}</span>
          <span className="text-muted-foreground">·</span>
          <span
            className={cn(
              "text-xs",
              blocker
                ? "font-medium text-rose-700"
                : needsYou
                  ? "font-medium text-amber-700"
                  : "text-muted-foreground",
            )}
          >
            {timeLabel}
          </span>
        </div>

        <p className="mt-1 text-[14px] leading-relaxed text-foreground">{item.title}</p>

        {item.summary ? (
          <p className="mt-0.5 text-[13px] leading-relaxed text-muted-foreground">{item.summary}</p>
        ) : null}

        {contextLabel ? (
          <span className="mt-1.5 inline-flex items-center gap-1 text-[13px] text-muted-foreground group-hover:text-foreground">
            <span aria-hidden>→</span>
            <span>{contextLabel}</span>
          </span>
        ) : null}

        <div
          className="mt-2 flex items-center gap-1"
          onClick={stop}
          onKeyDown={stop as unknown as React.KeyboardEventHandler}
        >
          {primaryLabel ? (
            <Button
              variant="secondary"
              size="sm"
              className="h-7 px-2.5 text-[12px]"
              onClick={openSpotlight}
            >
              {primaryLabel}
            </Button>
          ) : null}

          {needsYou && hasTaskActions ? (
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button
                  variant="ghost"
                  size="sm"
                  className="h-7 px-2.5 text-[12px] text-muted-foreground"
                >
                  Defer
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="start" className="w-32">
                <DropdownMenuItem onSelect={() => runDefer(4)}>4 hours</DropdownMenuItem>
                <DropdownMenuItem onSelect={() => runDefer(24)}>1 day</DropdownMenuItem>
                <DropdownMenuItem onSelect={() => runDefer(24 * 7)}>1 week</DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          ) : null}

          {blocker && hasTaskActions ? (
            <Button
              variant="ghost"
              size="sm"
              className="h-7 px-2.5 text-[12px] text-rose-700 hover:bg-rose-50 hover:text-rose-800"
              onClick={runCancelTask}
            >
              Cancel task
            </Button>
          ) : null}

          {item.actor_agent_id ? (
            <Button
              variant="ghost"
              size="sm"
              className="h-7 px-2.5 text-[12px] text-muted-foreground"
              onClick={handleTalk}
            >
              Talk to {agent?.label ?? item.actor_agent_id}
            </Button>
          ) : null}

          {hasEntryActions ? (
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button
                  variant="ghost"
                  size="sm"
                  className="h-7 w-7 px-0 text-muted-foreground opacity-0 group-hover:opacity-100 focus:opacity-100 data-[state=open]:opacity-100"
                  aria-label="More actions"
                >
                  <MoreHorizontal className="h-3.5 w-3.5" />
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="start" className="w-40">
                <DropdownMenuItem onSelect={runDismiss}>
                  {tab === "blockers" ? "Mark resolved" : "Ignore for now"}
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          ) : null}
        </div>
      </div>

      {item.severity && item.severity >= 2 ? (
        <AlertTriangle className="mt-1 h-3.5 w-3.5 shrink-0 text-rose-500" aria-hidden />
      ) : null}
      {ctxMenu ? (
        <RowContextMenu
          x={ctxMenu.x}
          y={ctxMenu.y}
          onClose={() => setCtxMenu(null)}
          onMarkRead={runMarkRead}
          onHide={runHide}
        />
      ) : null}
    </article>
  );
}

function RowContextMenu({
  x,
  y,
  onClose,
  onMarkRead,
  onHide,
}: {
  x: number;
  y: number;
  onClose: () => void;
  onMarkRead: () => void;
  onHide: () => void;
}) {
  const ref = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    function handleDown(e: globalThis.MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) onClose();
    }
    function handleKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose();
    }
    document.addEventListener("mousedown", handleDown);
    document.addEventListener("keydown", handleKey);
    return () => {
      document.removeEventListener("mousedown", handleDown);
      document.removeEventListener("keydown", handleKey);
    };
  }, [onClose]);

  return (
    <div
      ref={ref}
      role="menu"
      className="fixed z-50 min-w-[10rem] rounded-md border bg-popover p-1 text-sm text-popover-foreground shadow-md"
      style={{ left: x, top: y }}
      onClick={(e) => e.stopPropagation()}
    >
      <button
        type="button"
        role="menuitem"
        className="flex w-full items-center rounded-sm px-2 py-1.5 text-left hover:bg-accent"
        onClick={onMarkRead}
      >
        Mark as read
      </button>
      <button
        type="button"
        role="menuitem"
        className="flex w-full items-center rounded-sm px-2 py-1.5 text-left hover:bg-accent"
        onClick={onHide}
      >
        Hide from feed
      </button>
      <button
        type="button"
        role="menuitem"
        disabled
        title="Star support coming soon"
        className="flex w-full cursor-not-allowed items-center rounded-sm px-2 py-1.5 text-left text-muted-foreground opacity-50"
      >
        Star
      </button>
    </div>
  );
}

function handleRowKey(
  e: React.KeyboardEvent<HTMLElement>,
  opts: { openSpotlight: () => void; onEscape?: () => void },
) {
  const target = e.currentTarget;

  // Focus navigation: j/k and arrows move between rows across sections.
  if (e.key === "ArrowDown" || e.key === "j") {
    e.preventDefault();
    focusSibling(target, 1);
    return;
  }
  if (e.key === "ArrowUp" || e.key === "k") {
    e.preventDefault();
    focusSibling(target, -1);
    return;
  }

  // Enter or Space: open the spotlight preview modal (spec v3 §3).
  if (e.key === "Enter" || e.key === " " || e.key === "Spacebar") {
    e.preventDefault();
    opts.openSpotlight();
    return;
  }

  if (e.key === "Escape") {
    e.preventDefault();
    opts.onEscape?.();
  }
}

function focusSibling(current: HTMLElement, direction: 1 | -1) {
  const items = Array.from(document.querySelectorAll<HTMLElement>("[data-stream-item]"));
  const idx = items.indexOf(current);
  if (idx === -1) return;
  const next = items[idx + direction];
  if (next) next.focus();
}

function ariaLabelFor(item: StreamTabItem, actorName: string, timeLabel: string): string {
  const parts = [actorName, timeLabel, item.title];
  if (item.summary) parts.push(item.summary);
  parts.push("press Enter to preview");
  return parts.join(", ");
}

function formatTimeLabel(item: StreamTabItem, tab: StreamTab): string {
  const ageSec = item.age_seconds ?? deriveAgeSeconds(item.inserted_at);
  if (tab === "needs_you") return `waiting ${humanDuration(ageSec)}`;
  if (tab === "blockers") {
    if (item.kind === "failed") return `failed ${humanDuration(ageSec)} ago`;
    return `blocked ${humanDuration(ageSec)}`;
  }
  return `${humanDuration(ageSec)} ago`;
}

function humanDuration(seconds: number): string {
  if (seconds < 60) return "just now";
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.round(minutes / 60);
  if (hours < 24) return `${hours}h`;
  const days = Math.round(hours / 24);
  if (days < 7) return `${days}d`;
  const weeks = Math.round(days / 7);
  return `${weeks}w`;
}

function deriveAgeSeconds(iso: string | null): number {
  if (!iso) return 0;
  const delta = Date.now() - new Date(iso).getTime();
  return Math.max(Math.round(delta / 1000), 0);
}

function formatContextLabel(item: StreamTabItem): string | null {
  if (!item.context_type) return null;
  const pretty = item.context_type.replace(/_/g, " ");
  return item.context_id ? `${pretty} #${item.context_id}` : pretty;
}
