import { useState, useEffect } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { cn } from "@/lib/utils";
import { api } from "@/lib/api";
import { Plus } from "lucide-react";
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import type { Project } from "@/types";

export function ProjectRail() {
  const navigate = useNavigate();
  const { projectId } = useParams<{ projectId: string }>();
  const activeId = projectId ? Number(projectId) : null;

  const [projects, setProjects] = useState<Project[]>([]);

  useEffect(() => {
    api.listProjects().then(setProjects).catch(() => {});

    const interval = setInterval(() => {
      api.listProjects().then(setProjects).catch(() => {});
    }, 60000);

    return () => clearInterval(interval);
  }, []);

  function getInitials(name: string) {
    const words = name.split(/\s+/).filter(Boolean);
    if (words.length >= 2) {
      return (words[0][0] + words[1][0]).toUpperCase();
    }
    // Single word: take first 2 characters (e.g. "Hydra" → "Hy")
    return name.slice(0, 2).toUpperCase();
  }

  // Sort by most recently updated
  const sorted = [...projects].sort(
    (a, b) =>
      new Date(b.updated_at ?? 0).getTime() -
      new Date(a.updated_at ?? 0).getTime(),
  );

  return (
    <TooltipProvider delayDuration={300}>
      <aside className="flex w-14 shrink-0 flex-col items-center border-r bg-background py-3 gap-2">
        {/* Logo */}
        <div className="flex h-9 w-9 items-center justify-center text-lg font-bold tracking-tight">
          H
        </div>

        <div className="h-px w-6 bg-border my-1" />

        {/* Project icons */}
        <div className="flex flex-1 flex-col items-center gap-2 overflow-y-auto">
          {sorted.map((project) => (
            <Tooltip key={project.id}>
              <TooltipTrigger asChild>
                <button
                  onClick={() => navigate(`/projects/${project.id}`)}
                  className={cn(
                    "relative flex h-9 w-9 items-center justify-center rounded-lg text-xs font-semibold transition-colors",
                    activeId === project.id
                      ? "bg-primary text-primary-foreground"
                      : "bg-muted text-muted-foreground hover:bg-accent hover:text-accent-foreground",
                  )}
                >
                  {getInitials(project.name)}

                  {/* Active indicator pill on left edge */}
                  {activeId === project.id && (
                    <span className="absolute -left-[11px] top-1/2 h-5 w-[3px] -translate-y-1/2 rounded-r-full bg-primary" />
                  )}
                </button>
              </TooltipTrigger>
              <TooltipContent side="right" sideOffset={8}>
                {project.name}
              </TooltipContent>
            </Tooltip>
          ))}
        </div>

        <div className="h-px w-6 bg-border my-1" />

        {/* Create new project */}
        <Tooltip>
          <TooltipTrigger asChild>
            <button
              onClick={() => navigate("/projects/new")}
              className="flex h-9 w-9 items-center justify-center rounded-lg border border-dashed border-muted-foreground/30 text-muted-foreground transition-colors hover:border-muted-foreground/60 hover:text-foreground"
            >
              <Plus className="h-4 w-4" />
            </button>
          </TooltipTrigger>
          <TooltipContent side="right" sideOffset={8}>
            New project
          </TooltipContent>
        </Tooltip>

        {/* User avatar */}
        <Tooltip>
          <TooltipTrigger asChild>
            <button
              onClick={() => navigate("/account")}
              className="flex h-9 w-9 items-center justify-center rounded-full bg-muted text-xs font-medium text-muted-foreground transition-colors hover:bg-accent"
            >
              G
            </button>
          </TooltipTrigger>
          <TooltipContent side="right" sideOffset={8}>
            Account settings
          </TooltipContent>
        </Tooltip>
      </aside>
    </TooltipProvider>
  );
}
