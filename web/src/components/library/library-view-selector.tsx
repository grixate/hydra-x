import { Button } from "@/components/ui/button";
import { Network, List, Tag } from "lucide-react";

// Library spec §7 — switcher between graph (default), source list, and
// topic browser. State is preserved across switches at the page level (each
// view re-mounts on switch but shares the URL and selection state).

export type LibraryView = "graph" | "list" | "topics";

const ITEMS: Array<{ value: LibraryView; label: string; Icon: React.ElementType }> = [
  { value: "graph", label: "Graph", Icon: Network },
  { value: "list", label: "Sources", Icon: List },
  { value: "topics", label: "Topics", Icon: Tag },
];

export function LibraryViewSelector({
  active,
  onChange,
}: {
  active: LibraryView;
  onChange: (view: LibraryView) => void;
}) {
  return (
    <div className="pointer-events-auto inline-flex items-center gap-0.5 rounded-md border bg-background/95 p-0.5 shadow-sm backdrop-blur">
      {ITEMS.map(({ value, label, Icon }) => (
        <Button
          key={value}
          size="xs"
          variant={active === value ? "default" : "ghost"}
          onClick={() => onChange(value)}
          className="h-7 gap-1 text-[11px]"
        >
          <Icon className="h-3 w-3" />
          {label}
        </Button>
      ))}
    </div>
  );
}
