import { useState, useEffect } from "react";
import { NavLink, useParams } from "react-router-dom";
import { cn } from "@/lib/utils";
import { api } from "@/lib/api";
import type { ProjectCounts } from "@/types";
import { Badge } from "@/components/ui/badge";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Separator } from "@/components/ui/separator";

type SidebarItem = {
  path: string;
  label: string;
  countKey?: keyof ProjectCounts;
  end?: boolean;
};

const sidebarGroups: Array<{ label: string | null; items: SidebarItem[] }> = [
  {
    label: null,
    items: [{ path: "", label: "Stream", end: true }],
  },
  {
    label: "Research",
    items: [
      { path: "sources", label: "Sources", countKey: "sources" },
      { path: "insights", label: "Insights", countKey: "insights" },
    ],
  },
  {
    label: "Strategy",
    items: [
      { path: "decisions", label: "Decisions", countKey: "decisions" },
      { path: "strategies", label: "Strategies", countKey: "strategies" },
      { path: "requirements", label: "Requirements", countKey: "requirements" },
    ],
  },
  {
    label: "Design & Architecture",
    items: [
      { path: "design", label: "Design", countKey: "design_nodes" },
      { path: "architecture", label: "Architecture", countKey: "architecture_nodes" },
    ],
  },
  {
    label: "Execution",
    items: [
      { path: "tasks", label: "Tasks", countKey: "tasks" },
      { path: "learnings", label: "Learnings", countKey: "learnings" },
    ],
  },
  {
    label: "Agents",
    items: [{ path: "chat", label: "Chat", countKey: "conversations" }],
  },
  {
    label: "System",
    items: [
      { path: "graph-health", label: "Graph Health" },
      { path: "settings", label: "Settings" },
    ],
  },
];

export function WorkspaceSidebar() {
  const { projectId } = useParams<{ projectId: string }>();
  const basePath = projectId ? `/product/${projectId}` : "/product";
  const [counts, setCounts] = useState<Partial<ProjectCounts>>({});

  useEffect(() => {
    if (!projectId) return;
    const pid = Number(projectId);
    if (isNaN(pid)) return;
    api.getProjectCounts(pid).then(setCounts).catch(() => {});
  }, [projectId]);

  return (
    <aside className="flex w-[240px] shrink-0 flex-col border-r border-[var(--line)] bg-[var(--paper)]">
      <div className="flex items-center gap-2 px-4 py-4">
        <span className="font-display text-lg font-bold tracking-tight">
          Hydra
        </span>
      </div>
      <Separator />
      <ScrollArea className="flex-1 px-2 py-2">
        <nav className="space-y-4">
          {sidebarGroups.map((group, gi) => (
            <div key={gi}>
              {group.label && (
                <p className="px-3 pb-1 text-[10px] font-bold uppercase tracking-[0.3em] text-[var(--ink-soft)]">
                  {group.label}
                </p>
              )}
              <div className="space-y-0.5">
                {group.items.map((item) => {
                  const count = item.countKey ? counts[item.countKey] : undefined;
                  return (
                    <NavLink
                      key={item.path}
                      to={`${basePath}/${item.path}`}
                      end={item.end}
                      className={({ isActive }) =>
                        cn(
                          "flex items-center justify-between rounded-lg px-3 py-1.5 text-sm transition-colors",
                          isActive
                            ? "bg-[var(--accent)] font-medium text-[var(--ink)]"
                            : "text-[var(--ink-soft)] hover:bg-[var(--ink)]/5 hover:text-[var(--ink)]",
                        )
                      }
                    >
                      <span>{item.label}</span>
                      {item.countKey && count != null && count > 0 && (
                        <Badge variant="secondary" className="text-[9px]">
                          {count}
                        </Badge>
                      )}
                    </NavLink>
                  );
                })}
              </div>
            </div>
          ))}
        </nav>
      </ScrollArea>
    </aside>
  );
}
