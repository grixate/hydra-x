import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useParams, useSearchParams } from "react-router-dom";
import { Activity, TriangleAlert, AlertTriangle } from "lucide-react";
import type { LucideIcon } from "lucide-react";

import { api } from "@/lib/api";
import { subscribeToProject } from "@/lib/project-channel";
import { cn } from "@/lib/utils";
import { Skeleton } from "@/components/ui/skeleton";
import { Card, CardContent } from "@/components/ui/card";
import { StreamEntryRow } from "@/components/stream/stream-tabs/stream-entry-row";
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
  const [activitySearch, setActivitySearch] = useState("");
  const mountedRef = useRef(true);

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
    [pid, activityAgentFilter, activitySearch],
  );

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

  // Re-fetch Activity when its filters change (debounced via requestAnimationFrame).
  useEffect(() => {
    if (tab !== "activity") return;
    const handle = requestAnimationFrame(() => loadTab("activity"));
    return () => cancelAnimationFrame(handle);
  }, [tab, activityAgentFilter, activitySearch, loadTab]);

  // Live updates via project channel.
  useEffect(() => {
    if (!pid) return;

    const refresh = () => {
      refreshCounts();
      if (tab) loadTab(tab);
    };

    return subscribeToProject(pid, [
      { event: "stream_entry.created", handler: refresh },
      { event: "agent_task.created", handler: refresh },
      { event: "agent_task.state_changed", handler: refresh },
      { event: "flow.updated", handler: refresh },
    ]);
  }, [pid, tab, loadTab, refreshCounts]);

  const visibleItems = useMemo(() => {
    if (!tab) return [];
    const list = items[tab];
    // B3.4 — smart prioritization for Needs You: urgency rank first
    // (failures / blockers / waiting all outrank proposals), then age so
    // older asks float to the top when the queue grows large.
    if (tab === "needs_you") return [...list].sort(needsYouRank);
    return list;
  }, [tab, items]);

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
      <header className="border-b px-4 py-3 lg:px-6">
        <div className="flex items-center gap-2">
          <h1 className="text-lg font-semibold">Stream</h1>
          <span className="text-[11px] text-muted-foreground">
            Retrospective view of project activity.
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
      </header>

      <div className="flex-1 overflow-y-auto px-4 py-4 lg:px-6">
        <OnboardingBanner surface="stream" />

        {tab === "activity" ? (
          <ActivityFilters
            agentFilter={activityAgentFilter}
            onAgentFilterChange={setActivityAgentFilter}
            search={activitySearch}
            onSearchChange={setActivitySearch}
          />
        ) : null}

        {loading && visibleItems.length === 0 ? (
          <div className="space-y-2">
            <Skeleton className="h-16 w-full" />
            <Skeleton className="h-16 w-full" />
            <Skeleton className="h-16 w-full" />
          </div>
        ) : visibleItems.length === 0 && tab ? (
          <EmptyTabState tab={tab} />
        ) : (
          <div className="flex flex-col gap-2">
            {visibleItems.map((item) => (
              <StreamEntryRow key={item.id} item={item} />
            ))}
          </div>
        )}
      </div>
    </div>
  );
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

function badgeFor(id: StreamTab, counts: StreamTabCounts | null): number | null {
  if (!counts) return null;
  if (id === "activity") return null; // unbounded
  return id === "needs_you" ? counts.needs_you : counts.blockers;
}

function ActivityFilters({
  agentFilter,
  onAgentFilterChange,
  search,
  onSearchChange,
}: {
  agentFilter: string | null;
  onAgentFilterChange: (value: string | null) => void;
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

  return (
    <div className="mb-3 flex flex-wrap items-center gap-2">
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

      <input
        type="search"
        value={search}
        onChange={(event) => onSearchChange(event.target.value)}
        placeholder="Search activity…"
        className="h-7 min-w-[12rem] rounded-md border bg-background px-2 text-[12px] focus:outline-none focus:ring-1 focus:ring-primary/40"
      />
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
