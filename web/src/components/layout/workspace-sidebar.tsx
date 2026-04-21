import { useState, useEffect, useRef } from "react";
import { NavLink, useParams, useLocation, useNavigate } from "react-router-dom";
import { cn } from "@/lib/utils";
import { api } from "@/lib/api";
import { Badge } from "@/components/ui/badge";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Separator } from "@/components/ui/separator";
import {
  Activity,
  GitFork,
  LayoutDashboard,
  FlaskConical,
  BookOpen,
  Telescope,
  Compass,
  Blocks,
  PenTool,
  Brain,
  Settings,
  Circle,
  UserPlus,
  Zap,
  GitCompareArrows,
  Radar,
} from "lucide-react";
import type { LucideIcon } from "lucide-react";
import { dispatchAgentChatPaneSwitch } from "@/components/chat/agent-chat-pane";
import { NotificationBell } from "@/components/command-center/notification-bell";

type NavItem = {
  path: string;
  label: string;
  icon: LucideIcon;
  end?: boolean;
};

const surfaces: NavItem[] = [
  { path: "command-center", label: "Command Center", icon: Zap },
  { path: "", label: "Stream", icon: Activity, end: true },
  { path: "graph", label: "Graph", icon: GitFork },
  { path: "board", label: "Boards", icon: LayoutDashboard },
  { path: "library", label: "Library", icon: BookOpen },
  { path: "simulation", label: "Simulation", icon: FlaskConical },
];

type AgentEntry = { persona: string; label: string; icon: LucideIcon };

const CONVERSATIONAL_AGENTS: AgentEntry[] = [
  { persona: "researcher", label: "Researcher", icon: Telescope },
  { persona: "strategist", label: "Strategist", icon: Compass },
  { persona: "architect", label: "Architect", icon: Blocks },
  { persona: "designer", label: "Designer", icon: PenTool },
  { persona: "memory_agent", label: "Memory", icon: Brain },
];

const BACKGROUND_AGENTS: AgentEntry[] = [
  { persona: "coherence", label: "Coherence", icon: GitCompareArrows },
  { persona: "continuous_research", label: "Watch", icon: Radar },
];

type AgentStatusEntry = {
  state: string;
  ready_count: number;
  summary?: string | null;
  active_count?: number;
};

export function WorkspaceSidebar() {
  const { projectId } = useParams<{ projectId: string }>();
  const location = useLocation();

  const base = projectId ? `/projects/${projectId}` : "/projects";
  const pid = projectId ? Number(projectId) : null;

  const navigate = useNavigate();
  const [projectName, setProjectName] = useState("");
  const [streamUnread, setStreamUnread] = useState(0);
  const [agentStatuses, setAgentStatuses] = useState<Map<string, AgentStatusEntry>>(new Map());
  const lastViewedRef = useRef<number>(Date.now());

  const isOnStream =
    location.pathname === `${base}` || location.pathname === `${base}/stream`;

  // Load project name
  useEffect(() => {
    if (!pid) return;
    api.listProjects().then((projects) => {
      const p = projects.find((proj) => proj.id === pid);
      if (p) setProjectName(p.name);
    }).catch(() => {});
  }, [pid]);

  // Agent statuses — fetch on mount, poll every 30s
  useEffect(() => {
    if (!pid) return;
    const fetchStatuses = () => {
      api.getAgentStatuses(pid).then((data) => {
        const map = new Map<string, AgentStatusEntry>();
        for (const s of data) {
          map.set(s.persona, {
            state: s.state,
            ready_count: s.ready_count,
            summary: s.summary,
            active_count: s.active_count,
          });
        }
        setAgentStatuses(map);
      }).catch(() => {});
    };
    fetchStatuses();
    const interval = setInterval(fetchStatuses, 30000);
    return () => clearInterval(interval);
  }, [pid]);

  // Stream unread tracking
  useEffect(() => {
    if (isOnStream) {
      setStreamUnread(0);
      lastViewedRef.current = Date.now();
    }
  }, [isOnStream]);

  useEffect(() => {
    if (!pid) return;
    const interval = setInterval(() => {
      if (isOnStream) return;
      api
        .getStream(pid)
        .then((data) => {
          const total =
            data.right_now.length + data.recently.length + data.emerging.length;
          setStreamUnread((prev) => (total > 0 ? Math.min(total, 9) : 0));
        })
        .catch(() => {});
    }, 30000);
    return () => clearInterval(interval);
  }, [pid, isOnStream]);


  return (
    <aside className="flex h-full min-h-0 w-[220px] shrink-0 flex-col border-r bg-sidebar-background">
      {/* Project name header */}
      <div className="flex items-center justify-between gap-2 px-4 py-3">
        <span className="text-sm font-semibold truncate">{projectName}</span>
        <NotificationBell />
      </div>
      <Separator />

      <ScrollArea className="flex-1 min-h-0">
        {/* Surfaces */}
        <nav className="space-y-0.5 px-2 py-3">
          {surfaces.map((item) => (
            <div key={item.path}>
              <NavLink
                to={`${base}/${item.path}`}
                end={item.end}
                className={({ isActive }) =>
                  cn(
                    "flex items-center gap-2 rounded-md px-3 py-1.5 text-sm transition-colors",
                    isActive
                      ? "bg-sidebar-accent font-medium text-sidebar-accent-foreground"
                      : "text-muted-foreground hover:bg-sidebar-accent/50 hover:text-sidebar-foreground",
                  )
                }
              >
                <item.icon className="h-4 w-4" />
                <span>{item.label}</span>
                {item.label === "Stream" && streamUnread > 0 && (
                  <Badge
                    variant="default"
                    className="ml-auto h-4 min-w-4 px-1 text-[9px]"
                  >
                    {streamUnread}
                  </Badge>
                )}
              </NavLink>

            </div>
          ))}
        </nav>

        <Separator className="mx-2" />

        {/* Conversational agents */}
        <div className="px-2 py-3">
          <p className="mb-2 px-3 text-[10px] font-semibold uppercase tracking-widest text-muted-foreground">
            Agents
          </p>
          <div className="space-y-0.5">
            {CONVERSATIONAL_AGENTS.map((agent) => (
              <SidebarAgentRow
                key={agent.persona}
                agent={agent}
                status={agentStatuses.get(agent.persona)}
                onSingleClick={() => pid && navigate(`${base}/agents/${agent.persona}`)}
                onDoubleClick={() => dispatchAgentChatPaneSwitch(agent.persona)}
                muted={false}
              />
            ))}
          </div>
        </div>

        <Separator className="mx-2" />

        {/* Background agents */}
        <div className="px-2 py-3">
          <p className="mb-2 px-3 text-[10px] font-semibold uppercase tracking-widest text-muted-foreground">
            Background
          </p>
          <div className="space-y-0.5">
            {BACKGROUND_AGENTS.map((agent) => (
              <SidebarAgentRow
                key={agent.persona}
                agent={agent}
                status={agentStatuses.get(agent.persona)}
                onSingleClick={() =>
                  pid &&
                  navigate(
                    agent.persona === "continuous_research"
                      ? `${base}/watch`
                      : `${base}/coherence`,
                  )
                }
                onDoubleClick={() => dispatchAgentChatPaneSwitch(agent.persona)}
                muted
              />
            ))}
          </div>
        </div>

        <Separator className="mx-2" />

        {/* Members */}
        <div className="px-2 py-3">
          <p className="mb-2 px-3 text-[10px] font-semibold uppercase tracking-widest text-muted-foreground">
            Members
          </p>
          <div className="space-y-0.5">
            <button className="flex items-center justify-between rounded-md px-3 py-1.5 text-sm text-muted-foreground hover:bg-sidebar-accent/50 hover:text-sidebar-foreground w-full transition-colors">
              <div className="flex items-center gap-2">
                <Circle className="h-2 w-2 fill-green-500 text-green-500" />
                <span>Greg (you)</span>
              </div>
              <span className="text-[10px] text-muted-foreground">online</span>
            </button>
            <button className="flex items-center gap-2 rounded-md px-3 py-1.5 text-sm text-muted-foreground hover:bg-sidebar-accent/50 hover:text-sidebar-foreground w-full transition-colors">
              <UserPlus className="h-3.5 w-3.5" />
              <span>Invite</span>
            </button>
          </div>
        </div>

        <Separator className="mx-2" />

        {/* Token spend widget */}
        {pid && <SidebarTokenWidget projectId={pid} base={base} />}

        {/* Settings */}
        <div className="px-2 py-3">
          <NavLink
            to={`${base}/settings`}
            className={({ isActive }) =>
              cn(
                "flex items-center gap-2 rounded-md px-3 py-1.5 text-sm transition-colors",
                isActive
                  ? "bg-sidebar-accent font-medium text-sidebar-accent-foreground"
                  : "text-muted-foreground hover:bg-sidebar-accent/50 hover:text-sidebar-foreground",
              )
            }
          >
            <Settings className="h-4 w-4" />
            <span>Settings</span>
          </NavLink>
        </div>
      </ScrollArea>
    </aside>
  );
}

const STATE_DOT: Record<string, string> = {
  idle: "bg-muted-foreground/30",
  working: "bg-primary animate-pulse",
  running: "bg-primary animate-pulse",
  waiting_for_input: "bg-amber-500",
  blocked: "bg-rose-500",
  proposing: "bg-emerald-500",
  paused: "bg-muted-foreground/60",
};

function SidebarAgentRow({
  agent,
  status,
  onSingleClick,
  onDoubleClick,
  muted,
}: {
  agent: AgentEntry;
  status: AgentStatusEntry | undefined;
  onSingleClick: () => void;
  onDoubleClick: () => void;
  muted: boolean;
}) {
  const state = status?.state ?? "idle";
  const summary = status?.summary?.trim();
  const ready = status?.ready_count ?? 0;
  const hasActivity = state !== "idle" && !!summary;

  // Single vs. double click disambiguation. Radix NavLink isn't used here
  // because we need custom click behavior.
  const clickTimer = useRef<number | null>(null);
  function handleClick() {
    if (clickTimer.current) {
      window.clearTimeout(clickTimer.current);
      clickTimer.current = null;
      onDoubleClick();
      return;
    }
    clickTimer.current = window.setTimeout(() => {
      onSingleClick();
      clickTimer.current = null;
    }, 200);
  }

  return (
    <button
      type="button"
      onClick={handleClick}
      className={cn(
        "group flex w-full flex-col gap-0.5 rounded-md px-3 py-1.5 text-left text-sm transition-colors hover:bg-sidebar-accent/50 hover:text-sidebar-foreground",
        muted ? "text-muted-foreground/70" : "text-muted-foreground",
      )}
      title={`Click: Command Center · Double-click: open chat`}
    >
      <div className="flex items-center gap-2">
        <agent.icon className="h-4 w-4 shrink-0" />
        <span className="flex-1 truncate">{agent.label}</span>
        {ready > 0 ? (
          <Badge variant="default" className="h-4 min-w-4 px-1 text-[9px]">
            {ready}
          </Badge>
        ) : null}
        <span className={cn("h-1.5 w-1.5 shrink-0 rounded-full", STATE_DOT[state] ?? STATE_DOT.idle)} />
      </div>
      {hasActivity ? (
        <span className="truncate pl-6 text-[10px] text-muted-foreground/70">{summary}</span>
      ) : null}
    </button>
  );
}

function formatTokens(tokens: number): string {
  if (tokens >= 1_000_000) return `${(tokens / 1_000_000).toFixed(1)}M`;
  if (tokens >= 1_000) return `${(tokens / 1_000).toFixed(0)}K`;
  return String(tokens);
}

function SidebarTokenWidget({ projectId, base }: { projectId: number; base: string }) {
  const [data, setData] = useState<{
    month_cost_cents: number;
    month_tokens: number;
    week_cost_cents: number;
    week_tokens: number;
    today_cost_cents: number;
    today_tokens: number;
    budget_cents: number | null;
    budget_percent: number | null;
  } | null>(null);

  useEffect(() => {
    const fetchData = () => {
      api.getSpendSummary(projectId).then(setData).catch(() => {});
    };
    fetchData();
    const interval = setInterval(fetchData, 5 * 60 * 1000);
    return () => clearInterval(interval);
  }, [projectId]);

  if (!data) return null;

  const budgetPercent = data.budget_percent ?? 0;
  const barColor =
    budgetPercent > 80 ? "bg-destructive"
    : budgetPercent > 60 ? "bg-amber-500"
    : "bg-primary";

  const accentColor =
    budgetPercent > 80 ? "text-rose-400" : budgetPercent > 60 ? "text-amber-400" : "text-emerald-400";
  const barTrack =
    budgetPercent > 80 ? "bg-rose-500/10" : budgetPercent > 60 ? "bg-amber-500/10" : "bg-emerald-500/10";
  const barFill =
    budgetPercent > 80 ? "bg-rose-500" : budgetPercent > 60 ? "bg-amber-500" : "bg-emerald-500";

  return (
    <div className="px-2 py-1">
      <NavLink
        to={`${base}/usage`}
        className="block rounded-lg px-3 py-2.5 transition-colors hover:bg-sidebar-accent/30"
      >
        <div className="flex items-baseline justify-between">
          <span className={cn("text-sm tabular-nums font-medium", accentColor)}>
            ${(data.month_cost_cents / 100).toFixed(2)}
          </span>
          {data.budget_cents != null ? (
            <span className="text-[10px] text-muted-foreground/50">
              / ${(data.budget_cents / 100).toFixed(0)}
            </span>
          ) : (
            <span className="text-[10px] text-muted-foreground/50">this month</span>
          )}
        </div>
        <span className="text-[10px] text-muted-foreground/50 tabular-nums">
          {formatTokens(data.month_tokens)} tokens
        </span>

        <div className={cn("mt-1.5 h-1 w-full rounded-full", barTrack)}>
          <div
            className={cn("h-1 rounded-full transition-all duration-700", barFill)}
            style={{ width: `${data.budget_cents != null ? Math.min(budgetPercent, 100) : 100}%` }}
          />
        </div>

        <div className="mt-2 flex items-center justify-between text-[10px]">
          <div>
            <span className="text-muted-foreground/40">week</span>
            <span className="ml-1 tabular-nums text-muted-foreground">{formatTokens(data.week_tokens)}</span>
          </div>
          <div>
            <span className="text-muted-foreground/40">today</span>
            <span className="ml-1 tabular-nums text-muted-foreground">{formatTokens(data.today_tokens)}</span>
          </div>
        </div>
      </NavLink>
    </div>
  );
}
