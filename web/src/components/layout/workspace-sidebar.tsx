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
  Telescope,
  Compass,
  Blocks,
  PenTool,
  Brain,
  Settings,
  Plus,
  Circle,
  UserPlus,
} from "lucide-react";
import type { LucideIcon } from "lucide-react";
import type { BoardSession } from "@/types";

type NavItem = {
  path: string;
  label: string;
  icon: LucideIcon;
  end?: boolean;
};

const surfaces: NavItem[] = [
  { path: "", label: "Stream", icon: Activity, end: true },
  { path: "graph", label: "Graph", icon: GitFork },
  { path: "board", label: "Board", icon: LayoutDashboard },
  { path: "simulation", label: "Simulation", icon: FlaskConical },
];

const agents = [
  { persona: "researcher", label: "Researcher", icon: Telescope },
  { persona: "strategist", label: "Strategist", icon: Compass },
  { persona: "architect", label: "Architect", icon: Blocks },
  { persona: "designer", label: "Designer", icon: PenTool },
  { persona: "memory_agent", label: "Memory", icon: Brain },
];

export function WorkspaceSidebar() {
  const { projectId } = useParams<{ projectId: string }>();
  const location = useLocation();
  const navigate = useNavigate();
  const base = projectId ? `/projects/${projectId}` : "/projects";
  const pid = projectId ? Number(projectId) : null;

  const [projectName, setProjectName] = useState("");
  const [streamUnread, setStreamUnread] = useState(0);
  const [boardSessions, setBoardSessions] = useState<BoardSession[]>([]);
  const lastViewedRef = useRef<number>(Date.now());

  const isOnStream =
    location.pathname === `${base}` || location.pathname === `${base}/stream`;
  const isOnBoard = location.pathname.startsWith(`${base}/board`);

  // Load project name
  useEffect(() => {
    if (!pid) return;
    api.listProjects().then((projects) => {
      const p = projects.find((proj) => proj.id === pid);
      if (p) setProjectName(p.name);
    }).catch(() => {});
  }, [pid]);

  // Load board sessions
  useEffect(() => {
    if (!pid) return;
    api.listBoardSessions(pid).then(setBoardSessions).catch(() => {});
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

  async function handleNewSession() {
    if (!pid) return;
    try {
      const session = await api.createBoardSession(pid, { title: "Untitled session" });
      setBoardSessions((prev) => [...prev, session]);
      navigate(`${base}/board/${session.id}`);
    } catch {
      // Silently fail — toast could be added later
    }
  }

  return (
    <aside className="flex w-[220px] shrink-0 flex-col border-r bg-sidebar-background">
      {/* Project name header */}
      <div className="flex items-center gap-2 px-4 py-3">
        <span className="text-sm font-semibold truncate">{projectName}</span>
      </div>
      <Separator />

      <ScrollArea className="flex-1">
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

              {/* Board session sub-items — show when Board is active OR has sessions */}
              {item.label === "Board" && (isOnBoard || boardSessions.length > 0) && (
                <div className="ml-5 mt-0.5 space-y-0.5">
                  {boardSessions.map((session) => (
                    <NavLink
                      key={session.id}
                      to={`${base}/board/${session.id}`}
                      className={({ isActive }) =>
                        cn(
                          "flex items-center gap-1.5 rounded-md px-2 py-1 text-xs transition-colors",
                          isActive
                            ? "bg-sidebar-accent font-medium text-sidebar-accent-foreground"
                            : "text-muted-foreground hover:bg-sidebar-accent/50 hover:text-sidebar-foreground",
                        )
                      }
                    >
                      <span className="truncate">{session.title}</span>
                    </NavLink>
                  ))}
                  <button
                    onClick={handleNewSession}
                    className="flex items-center gap-1.5 rounded-md px-2 py-1 text-xs text-muted-foreground transition-colors hover:bg-sidebar-accent/50 hover:text-sidebar-foreground w-full text-left"
                  >
                    <Plus className="h-3 w-3 shrink-0" />
                    <span>New session</span>
                  </button>
                </div>
              )}
            </div>
          ))}
        </nav>

        <Separator className="mx-2" />

        {/* Agents */}
        <div className="px-2 py-3">
          <p className="mb-2 px-3 text-[10px] font-semibold uppercase tracking-widest text-muted-foreground">
            Agents
          </p>
          <div className="space-y-0.5">
            {agents.map((agent) => (
              <NavLink
                key={agent.persona}
                to={`${base}/chat/${agent.persona}`}
                className={({ isActive }) =>
                  cn(
                    "flex items-center justify-between rounded-md px-3 py-1.5 text-sm transition-colors",
                    isActive
                      ? "bg-sidebar-accent font-medium text-sidebar-accent-foreground"
                      : "text-muted-foreground hover:bg-sidebar-accent/50 hover:text-sidebar-foreground",
                  )
                }
              >
                <div className="flex items-center gap-2">
                  <agent.icon className="h-4 w-4" />
                  <span>{agent.label}</span>
                </div>
                <Badge variant="outline" className="text-[9px] font-normal">
                  idle
                </Badge>
              </NavLink>
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
