import { useEffect, useMemo, useRef, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import {
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  ChevronUp,
  ExternalLink,
  Sparkles,
  User,
  X,
} from "lucide-react";
import type { LucideIcon } from "lucide-react";

import { Button } from "@/components/ui/button";
import { AGENTS_BY_ID, agentLabel } from "@/components/command-center/agents";
import { api } from "@/lib/api";
import { cn } from "@/lib/utils";
import { TrailPageView } from "@/components/trail/trail-page-view";
import type { TrailChainNode, TrailFlag, TrailNode } from "@/lib/api";
import type { StreamTab, StreamTabItem } from "@/types";

export type LineagePayload = {
  chain: LineageNode[];
  why: string | null;
  why_structured: WhyStructured | null;
  node_type: string | null;
  node_id: number | null;
  chain_b?: LineageNode[] | null;
};

export type WhyStructured = {
  root: string | null;
  path: string | null;
  summary: string | null;
};

export type LineageNode = {
  id: number;
  type: string;
  title: string;
  relation?: string | null;
};

/** A single action the spotlight can run. */
export type SpotlightAction = {
  key: string;
  label: string;
  variant?: "primary" | "secondary" | "destructive";
  /** Handler runs the action; return a truthy result to indicate success
   *  (which is what drives close/advance behaviour on Needs You + Blockers). */
  run: () => Promise<boolean> | boolean;
};

type Props = {
  item: StreamTabItem;
  tab: StreamTab;
  hasPrev: boolean;
  hasNext: boolean;
  onPrev: () => void;
  onNext: () => void;
  onClose: () => void;
  /** Actions available for this item; the first is styled as primary. */
  actions: SpotlightAction[];
  /** Called after any action resolves successfully — parent handles the
   *  refresh + auto-advance/close policy (spec §4). */
  onActionSuccess?: (actionKey: string) => void;
  lineage?: LineagePayload | null;
  lineageError?: string | null;
};

export function StreamItemSpotlight({
  item,
  tab,
  hasPrev,
  hasNext,
  onPrev,
  onNext,
  onClose,
  actions,
  onActionSuccess,
  lineage,
  lineageError,
}: Props) {
  const navigate = useNavigate();
  const { projectId } = useParams<{ projectId: string }>();
  const backdropRef = useRef<HTMLDivElement | null>(null);
  const modalRef = useRef<HTMLDivElement | null>(null);
  const touchStartRef = useRef<number | null>(null);
  const [trailExpanded, setTrailExpanded] = useState(false);
  const [runningAction, setRunningAction] = useState<string | null>(null);

  const handlersRef = useRef({ hasPrev, hasNext, onPrev, onNext, onClose, actions, onActionSuccess });
  handlersRef.current = { hasPrev, hasNext, onPrev, onNext, onClose, actions, onActionSuccess };

  const agent = item.actor_agent_id ? AGENTS_BY_ID[item.actor_agent_id] : null;
  const actorName = item.actor_agent_id ? agentLabel(item.actor_agent_id) : "System";
  const AvatarIcon: LucideIcon = agent?.icon ?? User;

  // Reset trail expansion whenever the visible item changes (pagination).
  useEffect(() => {
    setTrailExpanded(false);
    modalRef.current?.focus();
  }, [item.id]);

  useEffect(() => {
    function handleKey(e: KeyboardEvent) {
      const h = handlersRef.current;
      const target = e.target as HTMLElement | null;
      const editing =
        target instanceof HTMLInputElement ||
        target instanceof HTMLTextAreaElement ||
        target?.getAttribute?.("contenteditable") === "true";

      if (e.key === "Escape") {
        e.preventDefault();
        h.onClose();
        return;
      }
      if (editing) return;
      if (e.key === "ArrowLeft" && h.hasPrev) {
        e.preventDefault();
        h.onPrev();
        return;
      }
      if (e.key === "ArrowRight" && h.hasNext) {
        e.preventDefault();
        h.onNext();
        return;
      }
      if (e.key === "Enter") {
        if (target?.tagName === "BUTTON" || target?.tagName === "A") return;
        const primary = h.actions[0];
        if (!primary) return;
        e.preventDefault();
        void runAction(primary);
      }
    }
    document.addEventListener("keydown", handleKey);
    return () => document.removeEventListener("keydown", handleKey);
  }, []);

  async function runAction(action: SpotlightAction) {
    if (runningAction) return;
    setRunningAction(action.key);
    try {
      const ok = await action.run();
      if (ok) handlersRef.current.onActionSuccess?.(action.key);
    } finally {
      setRunningAction(null);
    }
  }

  function handleBackdropClick(e: React.MouseEvent) {
    if (e.target === backdropRef.current) onClose();
  }

  function handleViewInGraph() {
    if (!projectId) return;
    if (lineage?.node_type && lineage?.node_id) {
      navigate(`/projects/${projectId}/trail/${lineage.node_type}/${lineage.node_id}`);
      return;
    }
    navigate(`/projects/${projectId}/graph`);
  }

  const timeLabel = relativeLabel(item);
  const urgent = tab !== "activity";
  const canExpandTrail = Boolean(lineage?.node_type && lineage?.node_id);

  return (
    <div
      ref={backdropRef}
      role="dialog"
      aria-modal="true"
      aria-label={`Preview: ${item.title}`}
      onClick={handleBackdropClick}
      className="fixed inset-0 z-50 flex items-center justify-center bg-background md:bg-background/60 md:p-4 md:backdrop-blur-sm"
      onTouchStart={(e) => {
        touchStartRef.current = e.touches[0]?.clientX ?? null;
      }}
      onTouchEnd={(e) => {
        const start = touchStartRef.current;
        const end = e.changedTouches[0]?.clientX;
        touchStartRef.current = null;
        if (start == null || end == null) return;
        const dx = end - start;
        if (Math.abs(dx) < 50) return;
        if (dx < 0 && hasNext) onNext();
        else if (dx > 0 && hasPrev) onPrev();
      }}
    >
      {hasPrev ? (
        <button
          type="button"
          onClick={onPrev}
          className="absolute left-6 top-1/2 -translate-y-1/2 rounded-full border bg-background p-2 text-muted-foreground shadow-sm transition-colors hover:text-foreground md:left-12"
          aria-label="Previous item"
        >
          <ChevronLeft className="h-4 w-4" />
        </button>
      ) : null}

      <div
        ref={modalRef}
        tabIndex={-1}
        onClick={(e) => e.stopPropagation()}
        className={cn(
          "relative flex h-full w-full max-w-none flex-col overflow-y-auto border-0 bg-card p-6 shadow-2xl outline-none",
          "md:h-auto md:max-h-[85vh] md:max-w-[620px] md:rounded-xl md:border md:animate-in md:fade-in-0 md:zoom-in-95 md:duration-150",
        )}
      >
        <button
          type="button"
          onClick={onClose}
          className="absolute right-3 top-3 rounded-md p-1.5 text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
          aria-label="Close preview"
        >
          <X className="h-4 w-4" />
        </button>

        <div className="flex items-start gap-3">
          <div
            className={cn(
              "flex h-10 w-10 shrink-0 items-center justify-center rounded-full",
              urgent ? "bg-amber-100 text-amber-700" : "bg-muted text-muted-foreground",
              tab === "blockers" ? "bg-rose-100 text-rose-700" : null,
            )}
            aria-hidden
          >
            <AvatarIcon className="h-5 w-5" />
          </div>
          <div className="min-w-0 flex-1">
            <div className="flex items-baseline gap-1.5 text-sm">
              <span className="font-medium text-foreground">{actorName}</span>
              <span className="text-muted-foreground">·</span>
              <span className="text-xs text-muted-foreground">{timeLabel}</span>
            </div>
            <p className="mt-1 text-[15px] leading-relaxed text-foreground">{item.title}</p>
            {item.summary ? (
              <p className="mt-1 text-[13px] leading-relaxed text-muted-foreground">
                {item.summary}
              </p>
            ) : null}
          </div>
        </div>

        <div className="mt-4 space-y-3 border-t pt-4">
          <LineageSummary lineage={lineage} error={lineageError} />

          {canExpandTrail ? (
            <div>
              <button
                type="button"
                onClick={() => setTrailExpanded((v) => !v)}
                className="inline-flex items-center gap-1 text-[12px] font-medium text-muted-foreground hover:text-foreground"
                aria-expanded={trailExpanded}
              >
                {trailExpanded ? (
                  <ChevronUp className="h-3.5 w-3.5" />
                ) : (
                  <ChevronDown className="h-3.5 w-3.5" />
                )}
                {trailExpanded ? "Hide full trail" : "Show full trail"}
              </button>
              {trailExpanded && lineage?.node_type && lineage?.node_id ? (
                <div className="mt-2 rounded-md border bg-muted/20">
                  <InlineTrail nodeType={lineage.node_type} nodeId={lineage.node_id} />
                </div>
              ) : null}
            </div>
          ) : null}

          {lineage?.why_structured || lineage?.why ? (
            <WhyBlock
              structured={lineage?.why_structured ?? null}
              fallback={lineage?.why ?? null}
            />
          ) : null}
        </div>

        <div className="mt-4 flex flex-wrap items-center gap-2 border-t pt-4">
          {actions.map((action, i) => (
            <Button
              key={action.key}
              size="sm"
              variant={
                action.variant === "destructive"
                  ? "ghost"
                  : i === 0
                    ? "default"
                    : "secondary"
              }
              className={cn(
                action.variant === "destructive" && "text-rose-700 hover:bg-rose-50",
              )}
              disabled={runningAction !== null}
              onClick={() => runAction(action)}
            >
              {runningAction === action.key ? "…" : action.label}
            </Button>
          ))}
          <Button variant="ghost" size="sm" onClick={handleViewInGraph} className="ml-auto">
            <ExternalLink className="mr-1 h-3.5 w-3.5" />
            View in Graph
          </Button>
        </div>
      </div>

      {hasNext ? (
        <button
          type="button"
          onClick={onNext}
          className="absolute right-6 top-1/2 -translate-y-1/2 rounded-full border bg-background p-2 text-muted-foreground shadow-sm transition-colors hover:text-foreground md:right-12"
          aria-label="Next item"
        >
          <ChevronRight className="h-4 w-4" />
        </button>
      ) : null}
    </div>
  );
}

function WhyBlock({
  structured,
  fallback,
}: {
  structured: WhyStructured | null;
  fallback: string | null;
}) {
  const hasStructured =
    structured && (structured.root || structured.path || structured.summary);

  return (
    <div className="rounded-lg border bg-muted/30">
      <div className="flex items-center gap-1.5 border-b px-4 py-2 text-xs font-medium text-muted-foreground">
        <Sparkles className="h-3.5 w-3.5" />
        Why this exists
      </div>
      <div className="px-4 py-3">
        {hasStructured ? (
          <div className="space-y-3 text-[13px] leading-relaxed text-foreground">
            {structured.root ? <p>{structured.root}</p> : null}
            {structured.path ? (
              <p className="text-muted-foreground">{structured.path}</p>
            ) : null}
            {structured.summary ? (
              <p className="border-l-2 border-border pl-3 font-medium italic">
                {structured.summary}
              </p>
            ) : null}
          </div>
        ) : (
          <p className="whitespace-pre-wrap text-[13px] leading-relaxed text-foreground">
            {fallback}
          </p>
        )}
      </div>
    </div>
  );
}

function LineageSummary({
  lineage,
  error,
}: {
  lineage: LineagePayload | null | undefined;
  error: string | null | undefined;
}) {
  if (error) {
    return <p className="text-xs text-muted-foreground">Lineage unavailable: {error}</p>;
  }
  if (!lineage) {
    return (
      <div className="space-y-2">
        <div className="h-3 w-16 animate-pulse rounded bg-muted" />
        <div className="flex gap-2">
          <div className="h-6 w-20 animate-pulse rounded bg-muted" />
          <div className="h-6 w-20 animate-pulse rounded bg-muted" />
        </div>
      </div>
    );
  }
  const empty = lineage.chain.length === 0 && !lineage.chain_b?.length;
  return (
    <div className="space-y-2">
      <p className="text-[11px] font-medium uppercase tracking-wider text-muted-foreground">
        Context
      </p>
      {empty ? (
        <p className="text-xs text-muted-foreground">No graph context for this item.</p>
      ) : (
        <>
          <ChainRow nodes={lineage.chain} />
          {lineage.chain_b && lineage.chain_b.length > 0 ? (
            <>
              <div className="my-1 border-t border-dashed" />
              <ChainRow nodes={lineage.chain_b} />
            </>
          ) : null}
        </>
      )}
    </div>
  );
}

function ChainRow({ nodes }: { nodes: LineageNode[] }) {
  if (nodes.length === 0) return null;
  return (
    <div className="flex flex-wrap items-center gap-1.5 text-[12px]">
      {nodes.map((node, idx) => (
        <span key={`${node.type}-${node.id}-${idx}`} className="flex items-center gap-1.5">
          <span className="inline-flex max-w-[200px] items-center gap-1 truncate rounded-md border bg-background px-1.5 py-0.5">
            <span className="text-[10px] uppercase tracking-wider text-muted-foreground">
              {node.type.replace(/_/g, " ")}
            </span>
            <span className="truncate text-foreground">{node.title}</span>
          </span>
          {idx < nodes.length - 1 ? (
            <span className="text-muted-foreground">
              {node.relation ? `${node.relation} →` : "→"}
            </span>
          ) : null}
        </span>
      ))}
    </div>
  );
}

function InlineTrail({ nodeType, nodeId }: { nodeType: string; nodeId: number }) {
  const { projectId } = useParams<{ projectId: string }>();
  const navigate = useNavigate();
  const pid = projectId ? Number(projectId) : null;
  const [data, setData] = useState<{
    center: TrailNode;
    upstream: TrailChainNode[];
    downstream: TrailChainNode[];
    flags: TrailFlag[];
  } | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!pid) return;
    let cancelled = false;
    setData(null);
    setError(null);
    api
      .getTrail(pid, nodeType, nodeId)
      .then((res) => {
        if (!cancelled) setData(res);
      })
      .catch((err: unknown) => {
        if (!cancelled) {
          setError(err instanceof Error ? err.message : "Failed to load trail");
        }
      });
    return () => {
      cancelled = true;
    };
  }, [pid, nodeType, nodeId]);

  if (error) {
    return <p className="p-3 text-xs text-muted-foreground">Trail unavailable: {error}</p>;
  }
  if (!data || !pid) {
    return (
      <div className="space-y-2 p-3">
        <div className="h-4 w-3/4 animate-pulse rounded bg-muted" />
        <div className="h-4 w-2/3 animate-pulse rounded bg-muted" />
        <div className="h-4 w-1/2 animate-pulse rounded bg-muted" />
      </div>
    );
  }

  return (
    <div className="text-[13px] [&_.mx-auto]:mx-0 [&_.max-w-2xl]:max-w-none [&_.px-4]:px-3 [&_.py-6]:py-3 [&>div>div:first-child>button:first-child]:hidden">
      <TrailPageView
        center={data.center}
        upstream={data.upstream}
        downstream={data.downstream}
        flags={data.flags}
        projectId={pid}
        backLabel=""
        onBack={() => {
          /* no-op inline */
        }}
        onNavigate={(t, id) => navigate(`/projects/${pid}/trail/${t}/${id}`)}
        onNavigateGraph={() => navigate(`/projects/${pid}/graph`)}
        onChat={() => {
          /* no-op; spotlight primary actions handle chat */
        }}
        onRefresh={() => {
          /* no-op; rely on re-open for refresh */
        }}
      />
    </div>
  );
}

function relativeLabel(item: StreamTabItem): string {
  const age = item.age_seconds ?? 0;
  if (age < 60) return "just now";
  if (age < 3600) return `${Math.round(age / 60)}m ago`;
  if (age < 86400) return `${Math.round(age / 3600)}h ago`;
  const days = Math.round(age / 86400);
  return days < 7 ? `${days}d ago` : item.inserted_at ? new Date(item.inserted_at).toLocaleDateString() : "recently";
}
