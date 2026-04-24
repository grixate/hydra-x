import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useNavigate, useParams, useSearchParams } from "react-router-dom";
import { Activity, TriangleAlert, AlertTriangle } from "lucide-react";
import type { LucideIcon } from "lucide-react";

import { api } from "@/lib/api";
import { subscribeToProject } from "@/lib/project-channel";
import { cn } from "@/lib/utils";
import { Skeleton } from "@/components/ui/skeleton";
import { Card, CardContent } from "@/components/ui/card";
import { StreamEntryRow } from "@/components/stream/stream-tabs/stream-entry-row";
import {
  StreamItemSpotlight,
  type LineagePayload,
  type SpotlightAction,
} from "@/components/stream/stream-tabs/stream-item-spotlight";
import { dispatchAgentChatPaneSwitch } from "@/components/chat/agent-chat-pane";
import { EmptyTabState } from "@/components/stream/stream-tabs/empty-state";
import { OnboardingBanner } from "@/components/onboarding/onboarding-banner";
import type { StreamTab, StreamTabCounts, StreamTabItem } from "@/types";

type TabMeta = {
  id: StreamTab;
  label: string;
  icon: LucideIcon;
};

const TABS: TabMeta[] = [
  { id: "activity", label: "Activity", icon: Activity },
  { id: "needs_you", label: "Needs You", icon: TriangleAlert },
  { id: "blockers", label: "Blockers", icon: AlertTriangle },
];

function preferenceKey(projectId: string) {
  return `stream-tab-pref:${projectId}`;
}

function loadPreferredTab(projectId: string): StreamTab | null {
  try {
    const raw = localStorage.getItem(preferenceKey(projectId));
    if (raw === "activity" || raw === "needs_you" || raw === "blockers") return raw;
    return null;
  } catch {
    return null;
  }
}

function persistPreferredTab(projectId: string, tab: StreamTab) {
  try {
    localStorage.setItem(preferenceKey(projectId), tab);
  } catch {
    // ignore
  }
}

export function StreamPage() {
  const { projectId } = useParams<{ projectId: string }>();
  const [searchParams, setSearchParams] = useSearchParams();
  const navigateTo = useNavigate();
  const pid = projectId ? Number(projectId) : null;

  const [counts, setCounts] = useState<StreamTabCounts | null>(null);
  const [tab, setTab] = useState<StreamTab | null>(() => {
    const urlTab = searchParams.get("tab") as StreamTab | null;
    if (urlTab === "activity" || urlTab === "needs_you" || urlTab === "blockers") return urlTab;
    return projectId ? loadPreferredTab(projectId) : null;
  });
  const [items, setItems] = useState<Record<StreamTab, StreamTabItem[]>>({
    activity: [],
    needs_you: [],
    blockers: [],
  });
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [activityAgentFilter, setActivityAgentFilter] = useState<string | null>(null);
  const [activityTypeFilter, setActivityTypeFilter] = useState<string | null>(null);
  const [activitySearch, setActivitySearch] = useState("");
  const mountedRef = useRef(true);
  const loadTabRef = useRef<((target: StreamTab) => Promise<void>) | null>(null);
  const [spotlightId, setSpotlightId] = useState<string | null>(null);
  const [lineageCache, setLineageCache] = useState<Record<string, LineagePayload | null>>({});
  const [lineageError, setLineageError] = useState<Record<string, string>>({});
  // Read the cache via ref inside fetchLineage so the callback identity is
  // stable across cache updates. Without this the callback re-creates every
  // time we write to lineageCache, thrashing the pre-fetch effect.
  const lineageCacheRef = useRef(lineageCache);
  const lineageErrorRef = useRef(lineageError);
  lineageCacheRef.current = lineageCache;
  lineageErrorRef.current = lineageError;

  const refreshCounts = useCallback(async () => {
    if (!pid) return null;
    try {
      const data = await api.getStreamTabCounts(pid);
      if (mountedRef.current) setCounts(data);
      return data;
    } catch {
      return null;
    }
  }, [pid]);

  const loadTab = useCallback(
    async (target: StreamTab) => {
      if (!pid) return;
      try {
        const filters =
          target === "activity"
            ? {
                agent_id: activityAgentFilter ?? undefined,
                context_type: activityTypeFilter ?? undefined,
                search: activitySearch.trim() || undefined,
              }
            : {};
        const data = await api.getStreamTab(pid, target, filters);
        if (!mountedRef.current) return;
        setItems((prev) => ({ ...prev, [target]: data }));
      } catch (err) {
        if (!mountedRef.current) return;
        setError(err instanceof Error ? err.message : "Failed to load");
      }
    },
    [pid, activityAgentFilter, activityTypeFilter, activitySearch],
  );

  // Keep ref current so async callbacks (channel refresh) always see the
  // latest loadTab closure with the latest filter state.
  loadTabRef.current = loadTab;

  // Initial load: fetch counts + default tab, optionally seeded from URL/pref.
  useEffect(() => {
    if (!pid || !projectId) return;
    mountedRef.current = true;
    setLoading(true);
    setError(null);

    (async () => {
      const fetched = await refreshCounts();
      if (!mountedRef.current) return;

      // Resolve the tab to display: URL > explicit local pref > server default.
      let resolved: StreamTab | null = tab;
      if (!resolved) {
        resolved = fetched?.default_tab ?? "activity";
      }
      setTab(resolved);

      // Pre-fetch that tab immediately; others lazy-load on click.
      await loadTab(resolved);

      if (mountedRef.current) setLoading(false);
    })();

    return () => {
      mountedRef.current = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [projectId]);

  // Persist tab to URL + localStorage.
  useEffect(() => {
    if (!tab || !projectId) return;
    persistPreferredTab(projectId, tab);
    const next = new URLSearchParams(searchParams);
    next.set("tab", tab);
    if (next.toString() !== searchParams.toString()) {
      setSearchParams(next, { replace: true });
    }
  }, [tab, projectId, searchParams, setSearchParams]);

  // When switching tabs, ensure that tab is loaded.
  useEffect(() => {
    if (!tab) return;
    if (items[tab].length === 0) loadTab(tab);
  }, [tab, loadTab]);

  // Re-fetch Activity when its filters change. We used to wrap this in a
  // requestAnimationFrame for debounce, but in React 18 Strict Mode the
  // repeated render/cleanup cycles cancelled the RAF before it could fire,
  // so the filtered fetch never ran. Calling directly is reliable; the
  // network call itself debounces naturally because loadTab is a useCallback
  // keyed on the filter values.
  useEffect(() => {
    if (tab !== "activity") return;
    loadTab("activity");
  }, [tab, activityAgentFilter, activityTypeFilter, activitySearch, loadTab]);

  // Live updates via project channel. The handler reads `loadTab` from a
  // ref so it always invokes the current closure — this avoids an overwrite
  // race where a broadcast during a filter change re-fetches unfiltered.
  useEffect(() => {
    if (!pid) return;

    const refresh = () => {
      refreshCounts();
      const latest = loadTabRef.current;
      if (tab && latest) latest(tab);
    };

    return subscribeToProject(pid, [
      { event: "stream_entry.created", handler: refresh },
      { event: "agent_task.created", handler: refresh },
      { event: "agent_task.state_changed", handler: refresh },
      { event: "flow.updated", handler: refresh },
    ]);
  }, [pid, tab, refreshCounts]);

  const focusFilters = useCallback(() => {
    // Escape from a row returns focus to the filter strip. Prefer the
    // Activity search input when available, else the active tab button
    // (tabs mark themselves with aria-current="page").
    const search = document.querySelector<HTMLInputElement>('input[type="search"]');
    if (search) {
      search.focus();
      return;
    }
    const activeTab = document.querySelector<HTMLButtonElement>('nav button[aria-current="page"]');
    activeTab?.focus();
  }, []);

  const visibleItems = useMemo(() => {
    if (!tab) return [];
    const list = items[tab];
    // B3.4 — smart prioritization for Needs You: urgency rank first
    // (failures / blockers / waiting all outrank proposals), then age so
    // older asks float to the top when the queue grows large.
    if (tab === "needs_you") return [...list].sort(needsYouRank);
    return list;
  }, [tab, items]);

  const spotlightIndex = useMemo(() => {
    if (!spotlightId) return -1;
    return visibleItems.findIndex((item) => item.id === spotlightId);
  }, [spotlightId, visibleItems]);

  const spotlightItem = spotlightIndex >= 0 ? visibleItems[spotlightIndex] : null;

  // Fetch lineage for a specific stream item and neighbours (pre-fetch).
  // Reads cache/error state via refs so the callback identity stays stable;
  // otherwise every cache update would re-create this function and re-fire
  // the pre-fetch effect. Also marks the key as failed on error so we don't
  // retry forever when lineage is genuinely unavailable.
  const fetchLineage = useCallback(
    async (targetItem: StreamTabItem) => {
      if (!pid) return;
      const key = targetItem.id;
      if (lineageCacheRef.current[key] !== undefined) return;
      if (lineageErrorRef.current[key]) return;
      setLineageCache((prev) => ({ ...prev, [key]: null }));
      try {
        const payload = await api.getStreamItemLineage(pid, targetItem);
        if (!mountedRef.current) return;
        setLineageCache((prev) => ({ ...prev, [key]: payload }));
      } catch (err) {
        if (!mountedRef.current) return;
        setLineageError((prev) => ({
          ...prev,
          [key]: err instanceof Error ? err.message : "Unavailable",
        }));
        // Also flip the cache slot to null so the pending spinner clears.
        setLineageCache((prev) => ({ ...prev, [key]: null }));
      }
    },
    [pid],
  );

  useEffect(() => {
    if (!spotlightItem) return;
    void fetchLineage(spotlightItem);
    if (spotlightIndex > 0) void fetchLineage(visibleItems[spotlightIndex - 1]);
    if (spotlightIndex < visibleItems.length - 1) void fetchLineage(visibleItems[spotlightIndex + 1]);
  }, [spotlightItem, spotlightIndex, visibleItems, fetchLineage]);

  const openSpotlight = useCallback((item: StreamTabItem) => {
    setSpotlightId(item.id);
  }, []);

  const closeSpotlight = useCallback(() => {
    setSpotlightId(null);
  }, []);

  const paginateSpotlight = useCallback(
    (delta: 1 | -1) => {
      if (spotlightIndex < 0) return;
      const next = visibleItems[spotlightIndex + delta];
      if (next) setSpotlightId(next.id);
    },
    [spotlightIndex, visibleItems],
  );

  if (error && !counts) {
    return (
      <div className="p-6">
        <Card>
          <CardContent className="py-8 text-center">
            <p className="text-sm font-medium text-foreground">Unable to load Stream</p>
            <p className="mt-1 text-sm text-muted-foreground">{error}</p>
          </CardContent>
        </Card>
      </div>
    );
  }

  return (
    <div className="flex h-full flex-col">
      <header className="border-b">
        <div className="mx-auto w-full max-w-[720px] px-4 py-4 lg:px-6">
          <div className="flex items-baseline gap-2">
            <h1 className="text-lg font-semibold">Stream</h1>
            <span className="text-[11px] text-muted-foreground">
              A reading feed of what happened, what needs you, and what's stuck.
            </span>
          </div>

          <nav className="mt-3 flex gap-1">
            {TABS.map((entry) => (
              <TabButton
                key={entry.id}
                meta={entry}
                active={tab === entry.id}
                badge={badgeFor(entry.id, counts)}
                onClick={() => setTab(entry.id)}
              />
            ))}
          </nav>
        </div>
      </header>

      <div className="flex-1 overflow-y-auto">
        <div className="mx-auto w-full max-w-[720px] px-4 py-6 lg:px-6">
          <OnboardingBanner surface="stream" />

          {tab === "activity" ? (
            <ActivityFilters
              agentFilter={activityAgentFilter}
              onAgentFilterChange={setActivityAgentFilter}
              typeFilter={activityTypeFilter}
              onTypeFilterChange={setActivityTypeFilter}
              search={activitySearch}
              onSearchChange={setActivitySearch}
            />
          ) : null}

          {loading && visibleItems.length === 0 ? (
            <div className="space-y-3">
              <Skeleton className="h-16 w-full" />
              <Skeleton className="h-16 w-full" />
              <Skeleton className="h-16 w-full" />
            </div>
          ) : visibleItems.length === 0 && tab ? (
            <EmptyTabState
              tab={tab}
              filtered={
                tab === "activity" &&
                (Boolean(activityAgentFilter) || Boolean(activityTypeFilter) || Boolean(activitySearch.trim()))
              }
              onClearFilters={() => {
                setActivityAgentFilter(null);
                setActivityTypeFilter(null);
                setActivitySearch("");
              }}
              onNavigate={(path) =>
                projectId ? navigateTo(`/projects/${projectId}${path}`) : undefined
              }
              onSwitchTab={setTab}
            />
          ) : (
            <StreamGroupedList
              items={visibleItems}
              tab={tab!}
              onAction={() => {
                refreshCounts();
                if (tab) loadTab(tab);
              }}
              onEscape={focusFilters}
              onOpenSpotlight={openSpotlight}
            />
          )}
        </div>
      </div>

      {spotlightItem && tab ? (
        <StreamItemSpotlight
          item={spotlightItem}
          tab={tab}
          hasPrev={spotlightIndex > 0}
          hasNext={spotlightIndex < visibleItems.length - 1}
          onPrev={() => paginateSpotlight(-1)}
          onNext={() => paginateSpotlight(1)}
          onClose={closeSpotlight}
          actions={buildActions(spotlightItem, tab, pid)}
          onActionSuccess={() => {
            // Capture the next id BEFORE the refresh repopulates items.
            const nextId = visibleItems[spotlightIndex + 1]?.id ?? null;
            // Advance on Needs You for a fast review flow; close on Blockers
            // (individual attention) and on Activity.
            if (tab === "needs_you" && nextId) setSpotlightId(nextId);
            else closeSpotlight();
            refreshCounts();
            if (tab) loadTab(tab);
          }}
          lineage={lineageCache[spotlightItem.id]}
          lineageError={lineageError[spotlightItem.id] ?? null}
        />
      ) : null}
    </div>
  );
}

function StreamGroupedList({
  items,
  tab,
  onAction,
  onEscape,
  onOpenSpotlight,
}: {
  items: StreamTabItem[];
  tab: StreamTab;
  onAction: () => void;
  onEscape: () => void;
  onOpenSpotlight: (item: StreamTabItem) => void;
}) {
  const groups = useMemo(() => groupByDateBucket(items), [items]);

  return (
    <div className="flex flex-col">
      {groups.map((group) => (
        <section key={group.label} className="flex flex-col">
          <h2 className="sticky top-0 z-10 -mx-2 mb-1 bg-background/90 px-2 py-1.5 text-[11px] font-medium uppercase tracking-wider text-muted-foreground backdrop-blur">
            {group.label}
          </h2>
          {group.items.map((item) => (
            <StreamEntryRow
              key={item.id}
              item={item}
              tab={tab}
              onAction={onAction}
              onEscape={onEscape}
              onOpenSpotlight={onOpenSpotlight}
            />
          ))}
        </section>
      ))}
    </div>
  );
}

type DateGroup = { label: string; items: StreamTabItem[] };

function groupByDateBucket(items: StreamTabItem[]): DateGroup[] {
  const now = new Date();
  const todayStart = startOfDay(now).getTime();
  const yesterdayStart = todayStart - 24 * 3600 * 1000;
  const weekStart = todayStart - 6 * 24 * 3600 * 1000;

  // Buckets keyed by a sort rank so the order is deterministic regardless
  // of the input iteration order. Ranks: 0=Today, 1=Yesterday, 2=This week,
  // 3+=older (larger = older), so ascending rank = newest → oldest.
  const buckets = new Map<string, { rank: number; maxTs: number; items: StreamTabItem[] }>();

  const ensure = (label: string, rank: number, ts: number) => {
    const existing = buckets.get(label);
    if (existing) {
      if (ts > existing.maxTs) existing.maxTs = ts;
      return existing;
    }
    const fresh = { rank, maxTs: ts, items: [] as StreamTabItem[] };
    buckets.set(label, fresh);
    return fresh;
  };

  for (const item of items) {
    const ts = item.inserted_at ? new Date(item.inserted_at).getTime() : Date.now();
    let bucket;
    if (ts >= todayStart) bucket = ensure("Today", 0, ts);
    else if (ts >= yesterdayStart) bucket = ensure("Yesterday", 1, ts);
    else if (ts >= weekStart) bucket = ensure("This week", 2, ts);
    else bucket = ensure(formatMonthLabel(ts), 3, ts);
    bucket.items.push(item);
  }

  // Items inside a bucket keep the caller's order (visibleItems) so the
  // visual sequence matches spotlight pagination. For Activity that means
  // server-side reverse-chronological; for Needs You it means the urgency
  // rank applied upstream. Re-sorting here would desync the two.
  return [...buckets.entries()]
    .sort((a, b) => a[1].rank - b[1].rank || b[1].maxTs - a[1].maxTs)
    .map(([label, { items }]) => ({ label, items }));
}

function startOfDay(d: Date): Date {
  const out = new Date(d);
  out.setHours(0, 0, 0, 0);
  return out;
}

function formatMonthLabel(ts: number): string {
  return new Intl.DateTimeFormat(undefined, { month: "short", year: "numeric" }).format(new Date(ts));
}

const NEEDS_YOU_URGENCY: Record<string, number> = {
  failed: 0,
  blocked: 1,
  waiting_for_input: 2,
  proposing: 3,
  stalled_flow: 4,
  contradiction: 5,
  burst: 6,
  stream_entry: 7,
};

function needsYouRank(a: StreamTabItem, b: StreamTabItem): number {
  const rankA = NEEDS_YOU_URGENCY[a.kind] ?? 99;
  const rankB = NEEDS_YOU_URGENCY[b.kind] ?? 99;
  if (rankA !== rankB) return rankA - rankB;
  // Older first within the same urgency band.
  return (b.age_seconds ?? 0) - (a.age_seconds ?? 0);
}

/**
 * Build the per-item action list for the spotlight modal. Actions map to
 * concrete backend calls per the item's `kind`, following the stream-tabs
 * spec §4–§6 primary/secondary action model:
 *
 *   proposing          → Accept (apply) / Decline (dismiss) / Defer
 *   waiting_for_input  → Reply (open chat) / Defer
 *   blocked            → Resume / Cancel
 *   failed             → Retry / Cancel
 *   stalled_flow       → Inspect
 *   contradiction      → Dismiss
 *   stream_entry       → Dismiss (Needs You) / Mark resolved (Blockers) / none (Activity)
 *   burst              → Expand (navigates to Command Center)
 *
 * Each handler returns a boolean — truthy triggers the parent's auto-
 * advance/close policy. We treat network failures as "didn't succeed" so
 * the modal stays open for the user to retry.
 */
function buildActions(
  item: StreamTabItem,
  tab: StreamTab,
  pid: number | null,
): SpotlightAction[] {
  if (!pid) return [];

  const taskId = item.source_task_id ?? null;
  const entryId = item.stream_entry_id ?? null;
  const agentId = item.actor_agent_id;

  const defer = (hours: number): SpotlightAction => ({
    key: `defer_${hours}`,
    label: hours === 4 ? "Defer 4h" : hours === 24 ? "Defer 1d" : "Defer 1w",
    variant: "secondary",
    run: async () => {
      if (!taskId) return false;
      try {
        await api.deferAgentTask(pid, taskId, hours);
        return true;
      } catch {
        return false;
      }
    },
  });

  const cancelTask: SpotlightAction = {
    key: "cancel",
    label: "Cancel task",
    variant: "destructive",
    run: async () => {
      if (!taskId) return false;
      try {
        await api.transitionAgentTask(pid, taskId, "cancelled");
        return true;
      } catch {
        return false;
      }
    },
  };

  const dismissEntry = (label: string): SpotlightAction => ({
    key: "dismiss_entry",
    label,
    variant: "secondary",
    run: async () => {
      if (!entryId) return false;
      try {
        await api.dismissStreamEntry(pid, entryId);
        return true;
      } catch {
        return false;
      }
    },
  });

  const replyToAgent: SpotlightAction = {
    key: "reply",
    label: "Reply",
    run: async () => {
      if (agentId) dispatchAgentChatPaneSwitch(agentId);
      return true;
    },
  };

  switch (item.kind) {
    case "proposing":
      if (!taskId) return [];
      return [
        {
          key: "accept",
          label: "Accept",
          run: async () => {
            try {
              await api.applyProposal(pid, taskId);
              return true;
            } catch {
              return false;
            }
          },
        },
        {
          key: "decline",
          label: "Decline",
          variant: "secondary",
          run: async () => {
            try {
              await api.dismissProposal(pid, taskId);
              return true;
            } catch {
              return false;
            }
          },
        },
        defer(24),
      ];

    case "waiting_for_input":
      return taskId ? [replyToAgent, defer(24)] : [replyToAgent];

    case "blocked":
      if (!taskId) return [];
      return [
        {
          key: "resume",
          label: "Resume",
          run: async () => {
            try {
              await api.transitionAgentTask(pid, taskId, "running");
              return true;
            } catch {
              return false;
            }
          },
        },
        cancelTask,
      ];

    case "failed":
      if (!taskId) return [];
      return [
        {
          key: "retry",
          label: "Retry",
          run: async () => {
            try {
              await api.transitionAgentTask(pid, taskId, "running");
              return true;
            } catch {
              return false;
            }
          },
        },
        cancelTask,
      ];

    case "stalled_flow":
      return [];

    case "contradiction":
      if (!item.context_id) return [];
      return [
        {
          key: "dismiss_contradiction",
          label: "Dismiss contradiction",
          variant: "secondary",
          run: async () => {
            try {
              await api.dismissContradiction(pid, item.context_id!);
              return true;
            } catch {
              return false;
            }
          },
        },
      ];

    case "stream_entry":
      if (tab === "activity") return [];
      if (!entryId) return [];
      return [dismissEntry(tab === "blockers" ? "Mark resolved" : "Dismiss")];

    case "burst":
      return [];

    default:
      return [];
  }
}

function badgeFor(id: StreamTab, counts: StreamTabCounts | null): number | null {
  if (!counts) return null;
  if (id === "activity") return null; // unbounded
  return id === "needs_you" ? counts.needs_you : counts.blockers;
}

function ActivityFilters({
  agentFilter,
  onAgentFilterChange,
  typeFilter,
  onTypeFilterChange,
  search,
  onSearchChange,
}: {
  agentFilter: string | null;
  onAgentFilterChange: (value: string | null) => void;
  typeFilter: string | null;
  onTypeFilterChange: (value: string | null) => void;
  search: string;
  onSearchChange: (value: string) => void;
}) {
  const AGENT_OPTIONS = [
    { id: null, label: "All agents" },
    { id: "researcher", label: "Researcher" },
    { id: "strategist", label: "Strategist" },
    { id: "architect", label: "Architect" },
    { id: "designer", label: "Designer" },
    { id: "memory_agent", label: "Memory" },
    { id: "coherence", label: "Coherence" },
    { id: "continuous_research", label: "Watch" },
  ];

  const TYPE_OPTIONS = [
    { id: null, label: "All types" },
    { id: "node", label: "Nodes" },
    { id: "source", label: "Sources" },
    { id: "session", label: "Sessions" },
    { id: "flow", label: "Flows" },
    { id: "task", label: "Tasks" },
  ];

  return (
    <div className="mb-3 flex flex-col gap-1.5">
      <div className="flex flex-wrap gap-1">
        {AGENT_OPTIONS.map((opt) => (
          <button
            key={opt.id ?? "all"}
            type="button"
            onClick={() => onAgentFilterChange(opt.id)}
            className={cn(
              "rounded-full border px-2 py-0.5 text-[11px] transition-colors",
              agentFilter === opt.id
                ? "border-primary bg-primary/10 text-foreground"
                : "border-transparent bg-muted/30 text-muted-foreground hover:text-foreground",
            )}
          >
            {opt.label}
          </button>
        ))}
      </div>

      <div className="flex flex-wrap items-center gap-1">
        {TYPE_OPTIONS.map((opt) => (
          <button
            key={opt.id ?? "all"}
            type="button"
            onClick={() => onTypeFilterChange(opt.id)}
            className={cn(
              "rounded-full border px-2 py-0.5 text-[11px] transition-colors",
              typeFilter === opt.id
                ? "border-primary bg-primary/10 text-foreground"
                : "border-transparent bg-muted/30 text-muted-foreground hover:text-foreground",
            )}
          >
            {opt.label}
          </button>
        ))}

        <input
          type="search"
          value={search}
          onChange={(event) => onSearchChange(event.target.value)}
          placeholder="Search activity…"
          className="ml-auto h-7 min-w-[10rem] rounded-md border bg-background px-2 text-[12px] focus:outline-none focus:ring-1 focus:ring-primary/40"
        />
      </div>
    </div>
  );
}

function TabButton({
  meta,
  active,
  badge,
  onClick,
}: {
  meta: TabMeta;
  active: boolean;
  badge: number | null;
  onClick: () => void;
}) {
  const Icon = meta.icon;
  const displayBadge = badge !== null && badge > 0 ? (badge > 9 ? "9+" : String(badge)) : null;

  return (
    <button
      type="button"
      onClick={onClick}
      aria-current={active ? "page" : undefined}
      className={cn(
        "group inline-flex items-center gap-1.5 rounded-md border px-2.5 py-1 text-xs transition-colors",
        active
          ? "border-primary bg-primary/10 text-foreground"
          : "border-transparent text-muted-foreground hover:bg-muted/40 hover:text-foreground",
      )}
    >
      <Icon className="h-3.5 w-3.5" />
      <span className="font-medium">{meta.label}</span>
      {displayBadge ? (
        <span
          className={cn(
            "ml-1 inline-flex h-4 min-w-4 items-center justify-center rounded-full px-1 text-[9px] tabular-nums",
            meta.id === "blockers" ? "bg-rose-500 text-white" : "bg-primary text-primary-foreground",
          )}
        >
          {displayBadge}
        </span>
      ) : null}
    </button>
  );
}
