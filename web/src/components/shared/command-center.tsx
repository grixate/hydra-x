import { FileStack, LayoutDashboard, LibraryBig, MessagesSquare, Plus, Search, Telescope } from "lucide-react";

import {
  CommandDialog,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
  CommandSeparator,
  CommandShortcut,
} from "@/components/ui/command";
import type { ProductConversation, Project } from "@/types";

type Section = "overview" | "sources" | "chat" | "insights" | "requirements";

const sections: Array<{ id: Section; label: string; icon: typeof LayoutDashboard }> = [
  { id: "overview", label: "Overview", icon: LayoutDashboard },
  { id: "sources", label: "Sources", icon: FileStack },
  { id: "chat", label: "Chat", icon: MessagesSquare },
  { id: "insights", label: "Insights", icon: Telescope },
  { id: "requirements", label: "Requirements", icon: LibraryBig },
];

export function CommandCenter({
  open,
  projects,
  conversations,
  onOpenChange,
  onSelectProject,
  onSelectSection,
  onSelectConversation,
  onCreateProject,
  onCreateConversation,
}: {
  open: boolean;
  projects: Project[];
  conversations: ProductConversation[];
  onOpenChange: (open: boolean) => void;
  onSelectProject: (projectId: number) => void;
  onSelectSection: (section: Section) => void;
  onSelectConversation: (conversationId: number) => void;
  onCreateProject: () => void;
  onCreateConversation: () => void;
}) {
  return (
    <CommandDialog open={open} onOpenChange={onOpenChange} title="Research Ledger command center">
      <CommandInput placeholder="Jump to a project, screen, or conversation..." />
      <CommandList>
        <CommandEmpty>No matching project flow.</CommandEmpty>

        <CommandGroup heading="Actions">
          <CommandItem
            onSelect={() => {
              onOpenChange(false);
              onCreateProject();
            }}
          >
            <Plus className="h-4 w-4" />
            New project
            <CommandShortcut>Shift P</CommandShortcut>
          </CommandItem>
          <CommandItem
            onSelect={() => {
              onOpenChange(false);
              onCreateConversation();
            }}
          >
            <MessagesSquare className="h-4 w-4" />
            New conversation
            <CommandShortcut>Shift C</CommandShortcut>
          </CommandItem>
        </CommandGroup>

        <CommandSeparator />

        <CommandGroup heading="Navigate">
          {sections.map((section) => {
            const Icon = section.icon;

            return (
              <CommandItem
                key={section.id}
                onSelect={() => {
                  onOpenChange(false);
                  onSelectSection(section.id);
                }}
              >
                <Icon className="h-4 w-4" />
                {section.label}
              </CommandItem>
            );
          })}
        </CommandGroup>

        <CommandSeparator />

        <CommandGroup heading="Projects">
          {projects.map((project) => (
            <CommandItem
              key={project.id}
              onSelect={() => {
                onOpenChange(false);
                onSelectProject(project.id);
              }}
            >
              <Search className="h-4 w-4" />
              {project.name}
              <CommandShortcut>{project.status}</CommandShortcut>
            </CommandItem>
          ))}
        </CommandGroup>

        <CommandSeparator />

        <CommandGroup heading="Recent conversations">
          {conversations.slice(0, 8).map((conversation) => (
            <CommandItem
              key={conversation.id}
              onSelect={() => {
                onOpenChange(false);
                onSelectSection("chat");
                onSelectConversation(conversation.id);
              }}
            >
              <MessagesSquare className="h-4 w-4" />
              {conversation.title || "Untitled conversation"}
              <CommandShortcut>{conversation.persona}</CommandShortcut>
            </CommandItem>
          ))}
        </CommandGroup>
      </CommandList>
    </CommandDialog>
  );
}
