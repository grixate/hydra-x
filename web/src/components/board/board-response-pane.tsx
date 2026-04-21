import { useRef, useEffect, useState, useMemo } from "react";
import { motion } from "motion/react";
import type { useChatState } from "@/hooks/use-chat-state";
import type { BoardSessionEvent } from "@/types";
import { api } from "@/lib/api";
import { BoardChatMessage } from "./board-chat-message";
import {
  SessionEvent,
  GroupedSessionEvent,
  groupConsecutiveEvents,
} from "./board-session-event";
import { Button } from "@/components/ui/button";
import { X } from "lucide-react";
import { AGENT_ICONS } from "./board-constants";

interface BoardResponsePaneProps {
  projectId: number;
  sessionId: number;
  chatState: ReturnType<typeof useChatState>;
  onCollapse: () => void;
  onHighlightNode?: (nodeType: string, nodeId: number) => void;
}

type TimelineItem =
  | { type: "message"; data: { role: string; content: string; timestamp: string }; key: string }
  | { type: "event"; data: BoardSessionEvent; key: string }
  | { type: "event_group"; data: BoardSessionEvent[]; key: string };

export function BoardResponsePane({
  projectId,
  sessionId,
  chatState,
  onCollapse,
  onHighlightNode,
}: BoardResponsePaneProps) {
  const { chatTabs, activeTabIndex, activeTab, handleTabClick } = chatState;
  const messages = activeTab?.messages ?? [];
  const bottomRef = useRef<HTMLDivElement>(null);
  const [events, setEvents] = useState<BoardSessionEvent[]>([]);

  // Fetch events on mount
  useEffect(() => {
    api.listBoardSessionEvents(projectId, sessionId)
      .then(setEvents)
      .catch(() => {});
  }, [projectId, sessionId]);

  // Listen for real-time events via the board session channel
  // The channel pushes "session_event" events — we need to listen on window
  // Actually, we can append events when they arrive via the channel
  // For now, poll-refresh when messages change (events and messages are correlated)
  useEffect(() => {
    if (messages.length === 0) return;
    api.listBoardSessionEvents(projectId, sessionId)
      .then(setEvents)
      .catch(() => {});
  }, [projectId, sessionId, messages.length]);

  // Build merged timeline
  const timeline = useMemo<TimelineItem[]>(() => {
    const items: { timestamp: number; item: TimelineItem }[] = [];

    // Add messages
    messages.forEach((msg, i) => {
      items.push({
        timestamp: new Date(msg.timestamp).getTime(),
        item: {
          type: "message",
          data: msg,
          key: `msg-${i}-${msg.timestamp}`,
        },
      });
    });

    // Group and add events
    const grouped = groupConsecutiveEvents(events);
    for (const entry of grouped) {
      if (entry.type === "single") {
        items.push({
          timestamp: new Date(entry.event.inserted_at).getTime(),
          item: {
            type: "event",
            data: entry.event,
            key: `evt-${entry.event.id}`,
          },
        });
      } else {
        items.push({
          timestamp: new Date(entry.events[0].inserted_at).getTime(),
          item: {
            type: "event_group",
            data: entry.events,
            key: `evtg-${entry.events.map((e) => e.id).join("-")}`,
          },
        });
      }
    }

    // Sort chronologically
    items.sort((a, b) => a.timestamp - b.timestamp);
    return items.map((i) => i.item);
  }, [messages, events]);

  // Auto-scroll to bottom on new content
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [timeline.length]);

  return (
    <div className="flex h-full flex-col">
      {/* Header */}
      <div className="flex items-center justify-between px-3 py-2 shrink-0">
        <span className="text-xs font-semibold uppercase tracking-widest text-muted-foreground">
          Conversation
        </span>
        <Button
          variant="ghost"
          size="icon-sm"
          onClick={onCollapse}
          title="Hide responses (⌘\)"
        >
          <X className="h-3.5 w-3.5" />
        </Button>
      </div>

      {/* Agent tabs */}
      {chatTabs.length > 1 && (
        <div className="flex items-center gap-1 px-3 py-1.5 border-b shrink-0">
          {chatTabs.map((tab, i) => {
            const icon = AGENT_ICONS[tab.agent] ?? "🤖";
            return (
              <button
                key={tab.agent}
                onClick={() => handleTabClick(i)}
                className={`rounded-full px-2.5 py-0.5 text-xs transition-colors ${
                  i === activeTabIndex
                    ? "bg-muted font-medium"
                    : "text-muted-foreground hover:text-foreground"
                }`}
              >
                {icon} {tab.agent}
                {tab.unread > 0 && (
                  <span className="ml-1 inline-flex h-4 w-4 items-center justify-center rounded-full bg-primary text-[9px] text-primary-foreground">
                    {tab.unread}
                  </span>
                )}
              </button>
            );
          })}
        </div>
      )}

      {/* Scrollable timeline */}
      <div className="flex-1 overflow-y-auto min-h-0">
        <div className="py-4">
          {timeline.length === 0 && (
            <motion.div
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              className="flex flex-col items-center justify-center py-16 text-center text-muted-foreground"
            >
              <p className="text-sm leading-relaxed">
                Agent responses will appear here as they<br />
                analyze your materials and answer your questions.
              </p>
            </motion.div>
          )}

          {timeline.map((item) => {
            if (item.type === "message") {
              return (
                <motion.div
                  key={item.key}
                  initial={{ opacity: 0, y: 8 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ duration: 0.2 }}
                  className="px-4 py-2"
                >
                  <BoardChatMessage
                    role={item.data.role}
                    content={item.data.content}
                    agent={activeTab?.agent}
                    projectId={projectId}
                    onSelectContext={(nodeType, nodeId) => {
                      onHighlightNode?.(nodeType, nodeId);
                    }}
                  />
                </motion.div>
              );
            }

            if (item.type === "event") {
              return (
                <motion.div
                  key={item.key}
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  transition={{ duration: 0.15 }}
                >
                  <SessionEvent
                    event={item.data}
                    onNodeClick={onHighlightNode}
                  />
                </motion.div>
              );
            }

            if (item.type === "event_group") {
              return (
                <motion.div
                  key={item.key}
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  transition={{ duration: 0.15 }}
                >
                  <GroupedSessionEvent
                    events={item.data}
                    onNodeClick={onHighlightNode}
                  />
                </motion.div>
              );
            }

            return null;
          })}

          <div ref={bottomRef} />
        </div>
      </div>
    </div>
  );
}
