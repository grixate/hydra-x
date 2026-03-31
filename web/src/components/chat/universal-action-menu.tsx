import { useState } from "react";
import { Button } from "@/components/ui/button";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import { Plus, FileUp, StickyNote, Link, CheckSquare, Lock, Lightbulb } from "lucide-react";
import { UploadSourceForm } from "./action-forms/upload-source-form";
import { QuickNoteForm } from "./action-forms/quick-note-form";
import { AddUrlForm } from "./action-forms/add-url-form";
import { CreateTaskForm } from "./action-forms/create-task-form";
import { AddConstraintForm } from "./action-forms/add-constraint-form";
import { LogLearningForm } from "./action-forms/log-learning-form";

const ACTIONS = [
  { key: "upload", icon: FileUp, label: "Upload source", description: "PDF, DOCX, TXT, MD" },
  { key: "note", icon: StickyNote, label: "Quick note", description: "Paste text or thoughts" },
  { key: "url", icon: Link, label: "Add URL", description: "Fetch and process a web page" },
  { key: "task", icon: CheckSquare, label: "Create task", description: "Add to the board" },
  { key: "constraint", icon: Lock, label: "Add constraint", description: "Non-negotiable boundary" },
  { key: "learning", icon: Lightbulb, label: "Log a learning", description: "Capture what you learned" },
] as const;

type ActionKey = (typeof ACTIONS)[number]["key"];

interface UniversalActionMenuProps {
  projectId: number;
  onComplete?: () => void;
}

export function UniversalActionMenu({ projectId, onComplete }: UniversalActionMenuProps) {
  const [menuOpen, setMenuOpen] = useState(false);
  const [activeForm, setActiveForm] = useState<ActionKey | null>(null);

  const handleAction = (key: ActionKey) => {
    setMenuOpen(false);
    setActiveForm(key);
  };

  const handleFormClose = () => {
    setActiveForm(null);
    onComplete?.();
  };

  return (
    <>
      <Popover open={menuOpen} onOpenChange={setMenuOpen}>
        <PopoverTrigger asChild>
          <Button
            variant="ghost"
            size="icon"
            className="h-7 w-7 text-muted-foreground"
          >
            <Plus className="h-4 w-4" />
          </Button>
        </PopoverTrigger>
        <PopoverContent side="top" align="start" className="w-56 p-1" sideOffset={8}>
          <div className="space-y-0.5">
            {ACTIONS.map((action) => {
              const Icon = action.icon;
              return (
                <button
                  key={action.key}
                  type="button"
                  onClick={() => handleAction(action.key)}
                  className="flex w-full items-center gap-3 rounded-md px-2.5 py-2 text-left transition-colors hover:bg-muted"
                >
                  <Icon className="h-4 w-4 shrink-0 text-muted-foreground" />
                  <div>
                    <div className="text-sm font-medium">{action.label}</div>
                    <div className="text-[11px] text-muted-foreground">{action.description}</div>
                  </div>
                </button>
              );
            })}
          </div>
        </PopoverContent>
      </Popover>

      {activeForm === "upload" && (
        <UploadSourceForm projectId={projectId} onClose={handleFormClose} />
      )}
      {activeForm === "note" && (
        <QuickNoteForm projectId={projectId} onClose={handleFormClose} />
      )}
      {activeForm === "url" && (
        <AddUrlForm projectId={projectId} onClose={handleFormClose} />
      )}
      {activeForm === "task" && (
        <CreateTaskForm projectId={projectId} onClose={handleFormClose} />
      )}
      {activeForm === "constraint" && (
        <AddConstraintForm projectId={projectId} onClose={handleFormClose} />
      )}
      {activeForm === "learning" && (
        <LogLearningForm projectId={projectId} onClose={handleFormClose} />
      )}
    </>
  );
}
