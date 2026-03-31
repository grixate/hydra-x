import { useState, useRef, useEffect } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Search, X } from "lucide-react";
import { NODE_COLORS, FILTERABLE_NODE_TYPES } from "./graph-constants";
import { cn } from "@/lib/utils";

const LABELS: Record<string, string> = {
  source: "source",
  insight: "insight",
  decision: "decision",
  strategy: "strategy",
  requirement: "requirement",
  design_node: "design",
  architecture_node: "architecture",
  task: "task",
  learning: "learning",
  constraint: "constraint",
};

interface GraphFilterChipsProps {
  visibleTypes: Set<string>;
  onToggle: (type: string) => void;
}

interface GraphSearchButtonProps {
  onSearch: (query: string) => void;
}

export function GraphFilterChips({
  visibleTypes,
  onToggle,
}: GraphFilterChipsProps) {
  return (
    <div className="flex items-center gap-1 pointer-events-auto">
      {FILTERABLE_NODE_TYPES.map((type) => {
        const active = visibleTypes.has(type);
        return (
          <button
            key={type}
            type="button"
            onClick={() => onToggle(type)}
            className={cn(
              "flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[11px] transition-all border",
              active
                ? "bg-background/80 backdrop-blur-sm border-border text-foreground"
                : "bg-muted/50 border-transparent opacity-50 text-muted-foreground",
            )}
          >
            <span
              className="h-1.5 w-1.5 shrink-0 rounded-full"
              style={{ backgroundColor: NODE_COLORS[type] }}
            />
            {LABELS[type] ?? type}
          </button>
        );
      })}
    </div>
  );
}

export function GraphSearchButton({ onSearch }: GraphSearchButtonProps) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (open && inputRef.current) {
      inputRef.current.focus();
    }
  }, [open]);

  useEffect(() => {
    onSearch(query);
  }, [query, onSearch]);

  const handleClose = () => {
    setOpen(false);
    setQuery("");
    onSearch("");
  };

  if (!open) {
    return (
      <Button
        variant="ghost"
        size="icon"
        className="h-7 w-7 pointer-events-auto"
        onClick={() => setOpen(true)}
      >
        <Search className="h-3.5 w-3.5" />
      </Button>
    );
  }

  return (
    <div className="pointer-events-auto flex items-center gap-1">
      <Input
        ref={inputRef}
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        placeholder="Search nodes..."
        className="h-7 w-44 text-xs"
        onKeyDown={(e) => {
          if (e.key === "Escape") handleClose();
        }}
      />
      <Button
        variant="ghost"
        size="icon"
        className="h-7 w-7"
        onClick={handleClose}
      >
        <X className="h-3.5 w-3.5" />
      </Button>
    </div>
  );
}
