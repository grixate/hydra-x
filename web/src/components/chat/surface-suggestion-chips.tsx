import { useState } from "react";
import { X } from "lucide-react";

import { cn } from "@/lib/utils";

export type ChipSurface =
  | "stream"
  | "command_center"
  | "graph"
  | "board"
  | "library"
  | "you";

const CHIPS: Record<ChipSurface, string[]> = {
  stream: ["What needs my attention?", "Summarize today", "Any blockers?"],
  command_center: ["Status of all agents", "Pause everything", "What's proposing?"],
  graph: ["Explain a node", "Restructure this area", "What's missing here?"],
  board: ["Draft a node", "Promote drafts", "Brainstorm"],
  library: ["Summarize this source", "Find related sources", "Upload more"],
  you: ["Update my values", "Review my principles", "What have I learned?"],
};

function storageKey(projectId: string, surface: ChipSurface) {
  return `chat-chips-dismissed:${projectId}:${surface}`;
}

function loadDismissed(projectId: string, surface: ChipSurface): Set<string> {
  try {
    const raw = localStorage.getItem(storageKey(projectId, surface));
    return new Set(raw ? (JSON.parse(raw) as string[]) : []);
  } catch {
    return new Set();
  }
}

function persistDismissed(projectId: string, surface: ChipSurface, set: Set<string>) {
  try {
    localStorage.setItem(storageKey(projectId, surface), JSON.stringify([...set]));
  } catch {
    // ignore quota
  }
}

export function SurfaceSuggestionChips({
  projectId,
  surface,
  onSelect,
  className,
}: {
  projectId: string;
  surface: ChipSurface;
  onSelect: (prompt: string) => void;
  className?: string;
}) {
  const [dismissed, setDismissed] = useState<Set<string>>(() => loadDismissed(projectId, surface));

  const visible = CHIPS[surface].filter((chip) => !dismissed.has(chip));
  if (visible.length === 0) return null;

  return (
    <div className={cn("flex flex-wrap gap-1.5 px-3 pt-2", className)}>
      {visible.map((chip) => (
        <div
          key={chip}
          className="group inline-flex items-center gap-1 rounded-full border bg-muted/30 text-[11px] transition-colors hover:bg-muted/60"
        >
          <button
            type="button"
            className="px-2.5 py-1 text-muted-foreground hover:text-foreground"
            onClick={() => onSelect(chip)}
          >
            {chip}
          </button>
          <button
            type="button"
            aria-label="Dismiss suggestion"
            className="pr-1.5 text-muted-foreground/50 opacity-0 transition-opacity group-hover:opacity-100 hover:text-foreground"
            onClick={() => {
              setDismissed((current) => {
                const next = new Set(current);
                next.add(chip);
                persistDismissed(projectId, surface, next);
                return next;
              });
            }}
          >
            <X className="h-2.5 w-2.5" />
          </button>
        </div>
      ))}
    </div>
  );
}
