import { useState, useEffect, useRef } from "react";
import { NavLink, useParams, useLocation } from "react-router-dom";
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
} from "lucide-react";
import type { LucideIcon } from "lucide-react";

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
  const base = projectId ? `/projects/${projectId}` : "/projects";
  const [streamUnread, setStreamUnread] = useState(0);
  const lastViewedRef = useRef<number>(Date.now());

  // Track when the user is on the stream page
  const isOnStream =
    location.pathname === `${base}` || location.pathname === `${base}/stream`;

  useEffect(() => {
    if (isOnStream) {
      setStreamUnread(0);
      lastViewedRef.current = Date.now();
    }
  }, [isOnStream]);

  // Poll for new stream items
  useEffect(() => {
    if (!projectId) return;
    const pid = Number(projectId);
    const interval = setInterval(() => {
      if (isOnStream) return;
      api.getStream(pid).then((data) => {
        const total =
          data.right_now.length + data.recently.length + data.emerging.length;
        // Simple heuristic: if total is higher than what we last saw, show a badge
        setStreamUnread((prev) => (total > 0 ? Math.min(total, 9) : 0));
      }).catch(() => {});
    }, 30000);
    return () => clearInterval(interval);
  }, [projectId, isOnStream]);

  return (
    <aside className="flex w-[220px] shrink-0 flex-col border-r bg-sidebar-background">
      <div className="flex items-center gap-2 px-4 py-4">
        <span className="text-lg font-bold tracking-tight">Hydra</span>
      </div>
      <Separator />
      <ScrollArea className="flex-1">
        <nav className="space-y-1 px-2 py-3">
          {surfaces.map((item) => (
            <NavLink
              key={item.path}
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
                <Badge variant="default" className="ml-auto h-4 min-w-4 px-1 text-[9px]">
                  {streamUnread}
                </Badge>
              )}
            </NavLink>
          ))}
        </nav>

        <Separator className="mx-2" />

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
