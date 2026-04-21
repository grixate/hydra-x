import type { StreamTab } from "@/types";

const EMPTY_COPY: Record<StreamTab, { primary: string; secondary?: string }> = {
  activity: {
    primary: "Nothing has happened in this project yet.",
    secondary: "Start a conversation with an agent or upload sources to begin.",
  },
  needs_you: {
    primary: "Nothing needs you right now.",
    secondary: "Agents are working or idle. Check Command Center for live status.",
  },
  blockers: {
    primary: "No blockers. Everything is either moving or complete.",
  },
};

export function EmptyTabState({ tab }: { tab: StreamTab }) {
  const copy = EMPTY_COPY[tab];
  return (
    <div className="flex min-h-[16rem] flex-col items-center justify-center rounded-lg border border-dashed bg-muted/20 p-8 text-center">
      <p className="text-sm font-medium text-foreground">{copy.primary}</p>
      {copy.secondary ? <p className="mt-1 text-xs text-muted-foreground">{copy.secondary}</p> : null}
    </div>
  );
}
