import { Bot, FileStack, LayoutDashboard, LibraryBig, MessagesSquare, Plus, Telescope } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Separator } from "@/components/ui/separator";
import type { Project, ProjectCounts } from "@/types";
import { cn } from "@/lib/utils";

type Section = "overview" | "sources" | "chat" | "insights" | "requirements";

const sections: Array<{ id: Section; label: string; icon: typeof Telescope }> = [
  { id: "overview", label: "Overview", icon: LayoutDashboard },
  { id: "sources", label: "Sources", icon: FileStack },
  { id: "chat", label: "Chat", icon: MessagesSquare },
  { id: "insights", label: "Insights", icon: Telescope },
  { id: "requirements", label: "Requirements", icon: LibraryBig },
];

export function ProjectSidebar({
  projects,
  selectedProjectId,
  onSelectProject,
  activeSection,
  onSelectSection,
  counts,
  onCreateProject,
  onOpenCommand,
}: {
  projects: Project[];
  selectedProjectId: number | null;
  onSelectProject: (projectId: number) => void;
  activeSection: Section;
  onSelectSection: (section: Section) => void;
  counts: ProjectCounts;
  onCreateProject: () => void;
  onOpenCommand: () => void;
}) {
  return (
    <Card className="flex h-full flex-col overflow-hidden bg-[rgba(250,244,235,0.9)]">
      <CardHeader className="pb-4">
        <div className="flex items-center gap-3">
          <div className="flex h-12 w-12 items-center justify-center rounded-[1.3rem] bg-foreground text-background">
            <Bot className="h-6 w-6" />
          </div>
          <div>
            <p className="text-[10px] font-bold uppercase tracking-[0.35em] text-muted-foreground">
              Hydra Product
            </p>
            <CardTitle className="mt-1 text-2xl">Research Ledger</CardTitle>
          </div>
        </div>
      </CardHeader>

      <CardContent className="flex min-h-0 flex-1 flex-col gap-5">
        <div className="grid grid-cols-2 gap-2">
          <Button variant="outline" className="justify-center" onClick={onOpenCommand}>
            Open palette
          </Button>
          <Button className="justify-center" onClick={onCreateProject}>
            <Plus className="h-4 w-4" />
            Project
          </Button>
        </div>

        <div>
          <p className="text-[10px] font-bold uppercase tracking-[0.3em] text-muted-foreground">
            Projects
          </p>
          <ScrollArea className="mt-3 h-[15rem] pr-2">
            <div className="space-y-2">
              {projects.map((project) => (
                <button
                  key={project.id}
                  type="button"
                  onClick={() => onSelectProject(project.id)}
                  className={cn(
                    "w-full rounded-[1.4rem] border px-4 py-3 text-left transition",
                    selectedProjectId === project.id
                      ? "border-foreground bg-foreground text-background"
                      : "border-transparent bg-white/60 text-foreground hover:border-border hover:bg-white",
                  )}
                >
                  <div className="flex items-start justify-between gap-3">
                    <div>
                      <p className="font-semibold">{project.name}</p>
                      <p
                        className={cn(
                          "mt-1 text-xs",
                          selectedProjectId === project.id
                            ? "text-[rgba(250,244,235,0.75)]"
                            : "text-muted-foreground",
                        )}
                      >
                        {project.slug}
                      </p>
                    </div>
                    <Badge variant={selectedProjectId === project.id ? "accent" : "neutral"}>
                      {project.status}
                    </Badge>
                  </div>
                </button>
              ))}
            </div>
          </ScrollArea>
        </div>

        <Separator />

        <div className="space-y-2">
          <p className="text-[10px] font-bold uppercase tracking-[0.3em] text-muted-foreground">
            Workspace
          </p>
          {sections.map((section) => {
            const Icon = section.icon;

            return (
              <button
                key={section.id}
                type="button"
                onClick={() => onSelectSection(section.id)}
                className={cn(
                  "flex w-full items-center justify-between rounded-[1.3rem] px-4 py-3 text-left transition",
                  activeSection === section.id
                    ? "bg-primary text-foreground"
                    : "text-muted-foreground hover:bg-white/70 hover:text-foreground",
                )}
              >
                <span className="inline-flex items-center gap-3">
                  <Icon className="h-4 w-4" />
                  <span className="font-medium">{section.label}</span>
                </span>
                <span className="text-xs">
                  {section.id === "overview" && projects.length}
                  {section.id === "sources" && counts.sources}
                  {section.id === "chat" && counts.conversations}
                  {section.id === "insights" && counts.insights}
                  {section.id === "requirements" && counts.requirements}
                </span>
              </button>
            );
          })}
        </div>

        <div className="mt-auto rounded-[1.5rem] border border-border bg-[rgba(255,255,255,0.72)] p-4">
          <p className="text-[10px] font-bold uppercase tracking-[0.3em] text-muted-foreground">
            Session
          </p>
          <p className="mt-2 text-xl text-foreground">Operator-authenticated</p>
          <p className="mt-2 text-sm text-muted-foreground">
            The frontend reuses the Phoenix operator session for both REST and Channels.
          </p>
          <Button asChild variant="secondary" className="mt-4 w-full justify-center">
            <a href="/login">Open operator login</a>
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
