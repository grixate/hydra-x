import { motion, AnimatePresence } from "motion/react";
import type { StreamItem as StreamItemType, MyWorkItem, MyWorkData } from "@/lib/api";
import { StreamSection } from "./stream-section";
import { StreamActionCard } from "./stream-action-card";
import { StreamListItem } from "./stream-list-item";
import { StreamSuggestionsCard } from "./stream-suggestions-card";
import { StreamModeToggle, type StreamMode } from "./stream-mode-toggle";
import { Button } from "@/components/ui/button";
import { MessageSquare, Upload } from "lucide-react";

type StreamData = {
  right_now: StreamItemType[];
  recently: StreamItemType[];
  emerging: StreamItemType[];
};

interface StreamViewProps {
  mode: StreamMode;
  onModeChange: (mode: StreamMode) => void;
  streamData: StreamData | null;
  myWorkData: MyWorkData | null;
  onNavigateToNode?: (nodeType: string, nodeId: number) => void;
  onNavigateGraph?: (nodeType: string, nodeId: number, filterType: string) => void;
  onAction?: (action: string, item: StreamItemType) => void;
  onTalkToStrategist?: () => void;
  onUploadResearch?: () => void;
}

// Convert MyWork "needs_input" items to StreamItem shape for action cards
function myWorkToActionItems(items: MyWorkItem[]): StreamItemType[] {
  return items
    .filter((i) => i.node_type && i.node_id)
    .map((i, idx) => ({
      id: `mw-action-${i.node_type}-${i.node_id}-${idx}`,
      category:
        i.type === "flag"
          ? "flag"
          : i.node_type === "insight"
            ? "insight_created"
            : i.node_type === "decision"
              ? "decision_gate"
              : "requirement_created",
      title: i.title,
      summary: "",
      node_type: i.node_type!,
      node_id: i.node_id!,
      urgency: "action" as const,
      timestamp: i.created_at ?? new Date().toISOString(),
      connections: {},
      metadata: {
        status: i.status,
        flag_type: i.flag_type,
      },
    }));
}

// Convert MyWork "active_work" + "recent_output" to StreamItem shape for list items
function myWorkToListItems(activeWork: MyWorkItem[], recentOutput: MyWorkItem[]): StreamItemType[] {
  const active = activeWork
    .filter((i) => i.node_type && i.node_id)
    .map((i, idx) => ({
      id: `mw-active-${i.node_type}-${i.node_id}-${idx}`,
      category: "status_change",
      title: i.title,
      summary: "",
      node_type: i.node_type!,
      node_id: i.node_id!,
      urgency: "info" as const,
      timestamp: i.updated_at ?? new Date().toISOString(),
      connections: {},
      metadata: { status: i.status },
    }));

  const output = recentOutput
    .filter((i) => i.node_id)
    .map((i, idx) => ({
      id: `mw-output-${i.node_type ?? "task"}-${i.node_id}-${idx}`,
      category: "status_change",
      title: i.title,
      summary: "",
      node_type: i.node_type ?? "task",
      node_id: i.node_id!,
      urgency: "info" as const,
      timestamp: i.at ?? new Date().toISOString(),
      connections: {},
      metadata: {},
    }));

  return [...active, ...output];
}

// Group list items by time period
type TimeGroup = { label: string; items: StreamItemType[] };

function groupByTime(items: StreamItemType[]): TimeGroup[] {
  const now = new Date();
  const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const yesterdayStart = new Date(todayStart.getTime() - 86400000);
  const weekStart = new Date(todayStart.getTime() - 6 * 86400000);

  const groups: Record<string, StreamItemType[]> = {
    Today: [],
    Yesterday: [],
    "This week": [],
    Earlier: [],
  };

  for (const item of items) {
    const ts = new Date(item.timestamp);
    if (ts >= todayStart) groups.Today.push(item);
    else if (ts >= yesterdayStart) groups.Yesterday.push(item);
    else if (ts >= weekStart) groups["This week"].push(item);
    else groups.Earlier.push(item);
  }

  return Object.entries(groups)
    .filter(([, items]) => items.length > 0)
    .map(([label, items]) => ({ label, items }));
}

export function StreamView({
  mode,
  onModeChange,
  streamData,
  myWorkData,
  onNavigateToNode,
  onAction,
  onTalkToStrategist,
  onUploadResearch,
}: StreamViewProps) {
  // Derive display data based on mode
  let actionItems: StreamItemType[] = [];
  let recentItems: StreamItemType[] = [];
  let emergingItems: StreamItemType[] = [];

  if (mode === "project" && streamData) {
    actionItems = streamData.right_now;
    recentItems = streamData.recently;
    emergingItems = streamData.emerging;
  } else if (mode === "my-work" && myWorkData) {
    actionItems = myWorkToActionItems(myWorkData.needs_input);
    recentItems = myWorkToListItems(myWorkData.active_work, myWorkData.recent_output);
  }

  const isEmpty =
    actionItems.length === 0 && recentItems.length === 0 && emergingItems.length === 0;

  const timeGroups = groupByTime(recentItems);

  // Running index counter for staggered list item animations
  let listIndex = 0;

  return (
    <div className="mx-auto max-w-2xl px-4 py-6">
      <StreamModeToggle mode={mode} onModeChange={onModeChange} />

      <AnimatePresence mode="popLayout">
        <motion.div
          key={mode}
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          transition={{ duration: 0.15 }}
        >
          {isEmpty ? (
            <motion.div
              initial={{ opacity: 0, scale: 0.97 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={{ duration: 0.4, delay: 0.1 }}
              className="flex flex-col items-center justify-center py-24 text-center"
            >
              <p className="text-base font-medium text-foreground">
                {mode === "my-work"
                  ? "Nothing needs your attention yet"
                  : "Your stream is quiet"}
              </p>
              <p className="mt-2 max-w-sm text-sm text-muted-foreground">
                {mode === "my-work"
                  ? "Items appear here when agents surface insights, decisions, or flags that need your review. Talk to the Strategist or upload research to kick things off."
                  : "The stream shows a live feed of your product graph — new insights, decisions, flags, and activity from agents working on your project. Upload research or start a conversation to see it come alive."}
              </p>
              <div className="mt-6 flex gap-3">
                <Button variant="default" onClick={onTalkToStrategist}>
                  <MessageSquare className="mr-2 h-4 w-4" />
                  Talk to Strategist
                </Button>
                <Button variant="outline" onClick={onUploadResearch}>
                  <Upload className="mr-2 h-4 w-4" />
                  Upload research
                </Button>
              </div>
            </motion.div>
          ) : (
            <>
              {/* Section 1: Needs your input — action cards */}
              {actionItems.length > 0 && (
                <StreamSection title="Needs your input" count={actionItems.length}>
                  <div className="space-y-3">
                    {actionItems.slice(0, 5).map((item, i) => (
                      <StreamActionCard
                        key={item.id}
                        item={item}
                        index={i}
                        onNavigate={onNavigateToNode}
                        onAction={onAction}
                      />
                    ))}
                  </div>
                </StreamSection>
              )}

              {/* Section 2: Recent activity — compact list */}
              <StreamSection title="Recent activity">
                {recentItems.length === 0 ? (
                  <motion.p
                    initial={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                    transition={{ duration: 0.3, delay: 0.2 }}
                    className="py-4 text-sm text-muted-foreground"
                  >
                    No recent activity. Chat with an agent or upload research to get started.
                  </motion.p>
                ) : (
                  <div>
                    {timeGroups.map((group) => (
                      <div key={group.label}>
                        <motion.p
                          initial={{ opacity: 0 }}
                          animate={{ opacity: 1 }}
                          transition={{ duration: 0.2, delay: listIndex * 0.03 }}
                          className="mt-4 mb-1 text-xs uppercase tracking-wide text-muted-foreground/60"
                        >
                          {group.label}
                        </motion.p>
                        {group.items.map((item) => {
                          const idx = listIndex++;
                          return (
                            <StreamListItem
                              key={item.id}
                              item={item}
                              index={idx}
                              onNavigate={onNavigateToNode}
                            />
                          );
                        })}
                      </div>
                    ))}
                  </div>
                )}
              </StreamSection>

              {/* Section 3: On the horizon — quiet suggestions */}
              {emergingItems.length > 0 && (
                <StreamSection title="On the horizon">
                  <StreamSuggestionsCard
                    items={emergingItems}
                    onNavigate={onNavigateToNode}
                    onAction={onAction}
                  />
                </StreamSection>
              )}
            </>
          )}
        </motion.div>
      </AnimatePresence>
    </div>
  );
}
