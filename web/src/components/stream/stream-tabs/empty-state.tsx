import { Button } from "@/components/ui/button";
import { dispatchAgentChatPaneSwitch } from "@/components/chat/agent-chat-pane";
import type { StreamTab } from "@/types";


export function EmptyTabState({
  tab,
  filtered,
  onClearFilters,
  onNavigate,
  onSwitchTab,
}: {
  tab: StreamTab;
  filtered?: boolean;
  onClearFilters?: () => void;
  onNavigate?: (path: string) => void;
  onSwitchTab?: (tab: StreamTab) => void;
}) {
  // When filters are active we show a "no results" state rather than the
  // fresh-project CTAs, which would be misleading.
  if (filtered) {
    return (
      <div className="flex flex-col items-center justify-center pt-16 pb-12 text-center">
        <p className="text-[15px] font-medium text-foreground">No matches.</p>
        <p className="mt-1.5 max-w-[380px] text-[13px] leading-relaxed text-muted-foreground">
          No {tab === "activity" ? "activity" : "items"} match the current filters.
        </p>
        {onClearFilters ? (
          <div className="mt-4">
            <Button variant="secondary" size="sm" onClick={onClearFilters}>
              Clear filters
            </Button>
          </div>
        ) : null}
      </div>
    );
  }

  if (tab === "blockers") {
    return (
      <div className="flex flex-col items-center justify-center pt-16 pb-12 text-center">
        <p className="text-[15px] font-medium text-foreground">
          No blockers. Everything is either moving or complete.
        </p>
      </div>
    );
  }

  if (tab === "needs_you") {
    return (
      <div className="flex flex-col items-center justify-center pt-16 pb-12 text-center">
        <p className="text-[15px] font-medium text-foreground">Nothing needs you right now.</p>
        <p className="mt-1.5 max-w-[380px] text-[13px] leading-relaxed text-muted-foreground">
          Your agents are working or idle. Check Activity to see what has been happening.
        </p>
        <div className="mt-4 flex items-center gap-2">
          <Button variant="secondary" size="sm" onClick={() => onSwitchTab?.("activity")}>
            View Activity
          </Button>
        </div>
      </div>
    );
  }

  return (
    <div className="flex flex-col items-center justify-center pt-16 pb-12 text-center">
      <p className="text-[15px] font-medium text-foreground">No activity yet.</p>
      <p className="mt-1.5 max-w-[380px] text-[13px] leading-relaxed text-muted-foreground">
        Start by adding sources to your Library or chatting with the Strategist about your Vision.
      </p>
      <div className="mt-4 flex items-center gap-2">
        <Button variant="secondary" size="sm" onClick={() => onNavigate?.("/library")}>
          Open Library
        </Button>
        <Button
          variant="ghost"
          size="sm"
          onClick={() => dispatchAgentChatPaneSwitch("strategist")}
        >
          Start with Strategist
        </Button>
      </div>
    </div>
  );
}
