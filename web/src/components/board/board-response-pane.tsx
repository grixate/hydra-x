import { useRef, useEffect } from "react";
import { motion } from "motion/react";
import type { useChatState } from "@/hooks/use-chat-state";
import { BoardChatMessage } from "./board-chat-message";
import { Button } from "@/components/ui/button";
import { X } from "lucide-react";
import { AGENT_ICONS } from "./board-constants";

interface BoardResponsePaneProps {
  projectId: number;
  chatState: ReturnType<typeof useChatState>;
  onCollapse: () => void;
  onHighlightNode?: (nodeType: string, nodeId: number) => void;
}

export function BoardResponsePane({
  projectId,
  chatState,
  onCollapse,
  onHighlightNode,
}: BoardResponsePaneProps) {
  const { chatTabs, activeTabIndex, activeTab, handleTabClick } = chatState;
  const messages = activeTab?.messages ?? [];
  const bottomRef = useRef<HTMLDivElement>(null);

  // Auto-scroll to bottom on new messages
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages.length]);

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

      {/* Scrollable message area */}
      <div className="flex-1 overflow-y-auto min-h-0">
        <div className="px-4 py-4 space-y-4">
          {messages.length === 0 && (
            <motion.div
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              className="flex flex-col items-center justify-center py-16 text-center text-muted-foreground"
            >
              <p className="text-sm">
                Add materials or ask a question to begin.
              </p>
            </motion.div>
          )}

          {messages.map((msg, i) => (
            <motion.div
              key={`${msg.role}-${i}-${msg.timestamp}`}
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.2 }}
            >
              <BoardChatMessage
                role={msg.role}
                content={msg.content}
                agent={activeTab?.agent}
                projectId={projectId}
                onSelectContext={(nodeType, nodeId) => {
                  onHighlightNode?.(nodeType, nodeId);
                }}
              />
            </motion.div>
          ))}

          <div ref={bottomRef} />
        </div>
      </div>
    </div>
  );
}
