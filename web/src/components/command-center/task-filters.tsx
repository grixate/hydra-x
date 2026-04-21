import { forwardRef } from "react";
import { X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";
import { agentLabel } from "./agents";

export type TaskFilter = "all" | "needs_me" | "running" | "blocked";

const FILTERS: Array<{ id: TaskFilter; label: string }> = [
  { id: "all", label: "All" },
  { id: "needs_me", label: "Needs Me" },
  { id: "running", label: "Running" },
  { id: "blocked", label: "Blocked" },
];

type Props = {
  filter: TaskFilter;
  onFilterChange: (filter: TaskFilter) => void;
  search: string;
  onSearchChange: (value: string) => void;
  agentFilter: string | null;
  onClearAgentFilter: () => void;
};

export const TaskFilters = forwardRef<HTMLInputElement, Props>(function TaskFilters(
  { filter, onFilterChange, search, onSearchChange, agentFilter, onClearAgentFilter },
  searchRef,
) {
  return (
    <div className="flex flex-wrap items-center gap-2">
      <div className="flex gap-1 rounded-md border bg-muted/40 p-0.5">
        {FILTERS.map((entry) => (
          <button
            key={entry.id}
            type="button"
            onClick={() => onFilterChange(entry.id)}
            className={cn(
              "rounded px-2.5 py-1 text-xs transition-colors",
              filter === entry.id
                ? "bg-background font-medium text-foreground shadow-sm"
                : "text-muted-foreground hover:text-foreground",
            )}
          >
            {entry.label}
          </button>
        ))}
      </div>

      <Input
        ref={searchRef}
        value={search}
        onChange={(event) => onSearchChange(event.target.value)}
        placeholder="Search tasks... (press /)"
        className="h-8 max-w-[16rem]"
      />

      {agentFilter ? (
        <Button variant="outline" size="sm" onClick={onClearAgentFilter}>
          <span className="text-xs">Filtered: {agentLabel(agentFilter)}</span>
          <X className="h-3 w-3" />
        </Button>
      ) : null}
    </div>
  );
});
