// Graph-Opt §8 + §9 — tiny toolbar shown when the graph is in a non-default
// mode (Lineage / Composed view). Lets the user return to the full graph.

import { Button } from "@/components/ui/button";
import { X } from "lucide-react";

export type GraphViewMode =
  | { kind: "default" }
  | { kind: "lineage"; targetTitle: string }
  | { kind: "composed"; label: string };

export function GraphViewModeToolbar({
  mode,
  onExit,
}: {
  mode: GraphViewMode;
  onExit: () => void;
}) {
  if (mode.kind === "default") return null;

  const label =
    mode.kind === "lineage"
      ? `Lineage — ${mode.targetTitle}`
      : `Composed view — ${mode.label}`;

  return (
    <div className="pointer-events-auto absolute left-1/2 top-4 z-20 flex -translate-x-1/2 items-center gap-2 rounded-full border bg-background/95 px-4 py-1.5 shadow-sm backdrop-blur">
      <span className="text-[11px] font-medium text-foreground/80">{label}</span>
      <Button
        variant="ghost"
        size="sm"
        className="h-6 gap-1 px-2 text-[11px]"
        onClick={onExit}
      >
        <X className="h-3 w-3" />
        Return to default
      </Button>
    </div>
  );
}
