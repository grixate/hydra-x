import { useRef, useEffect, useState, useCallback } from "react";
import { ScrollArea } from "@/components/ui/scroll-area";
import { GraphChatTabs, AGENT_COLORS, type ChatTab } from "./chat-tabs";
import { cn } from "@/lib/utils";

function timeAgo(timestamp: string): string {
  const diff = Date.now() - new Date(timestamp).getTime();
  const mins = Math.floor(diff / 60000);
  if (mins < 1) return "now";
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h ago`;
  return `${Math.floor(hrs / 24)}d ago`;
}

interface GraphChatCardProps {
  tabs: ChatTab[];
  activeIndex: number;
  minimized: boolean;
  onTabClick: (index: number) => void;
  onAddTab: (agent: string) => void;
  onMinimize: () => void;
  onClose: () => void;
  onGraphCommand: (command: {
    type: string;
    nodeIds?: string[];
    nodeId?: string;
  }) => void;
}

export function GraphChatCard({
  tabs,
  activeIndex,
  minimized,
  onTabClick,
  onAddTab,
  onMinimize,
  onClose,
  onGraphCommand,
}: GraphChatCardProps) {
  const scrollRef = useRef<HTMLDivElement>(null);
  const cardRef = useRef<HTMLDivElement>(null);
  const activeTab = tabs[activeIndex];

  // Drag state
  const [position, setPosition] = useState<{ x: number; y: number } | null>(null);
  const dragging = useRef(false);
  const dragStart = useRef({ mouseX: 0, mouseY: 0, cardX: 0, cardY: 0 });

  // Auto-scroll when new messages arrive
  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [activeTab?.messages.length]);

  const handleDragStart = useCallback(
    (e: React.MouseEvent) => {
      // Only drag from the tab bar background, not from buttons/tabs
      const target = e.target as HTMLElement;
      if (target.closest("button")) return;

      e.preventDefault();
      dragging.current = true;

      const card = cardRef.current;
      if (!card) return;

      const rect = card.getBoundingClientRect();
      const parentRect = card.offsetParent?.getBoundingClientRect() ?? { left: 0, top: 0 };

      dragStart.current = {
        mouseX: e.clientX,
        mouseY: e.clientY,
        cardX: rect.left - parentRect.left,
        cardY: rect.top - parentRect.top,
      };

      const handleMouseMove = (moveEvent: MouseEvent) => {
        if (!dragging.current) return;
        const dx = moveEvent.clientX - dragStart.current.mouseX;
        const dy = moveEvent.clientY - dragStart.current.mouseY;
        setPosition({
          x: dragStart.current.cardX + dx,
          y: dragStart.current.cardY + dy,
        });
      };

      const handleMouseUp = () => {
        dragging.current = false;
        window.removeEventListener("mousemove", handleMouseMove);
        window.removeEventListener("mouseup", handleMouseUp);
      };

      window.addEventListener("mousemove", handleMouseMove);
      window.addEventListener("mouseup", handleMouseUp);
    },
    [],
  );

  const positionStyle = position
    ? { left: position.x, top: position.y, right: "auto", bottom: "auto" }
    : { right: 16, bottom: 80 };

  return (
    <div
      ref={cardRef}
      className={cn(
        "absolute z-30 flex flex-col rounded-2xl border bg-background shadow-2xl transition-[height] duration-200 overflow-hidden",
        minimized ? "h-10 w-[420px]" : "h-[480px] w-[420px]",
      )}
      style={positionStyle}
    >
      {/* Tab bar — draggable area */}
      <div onMouseDown={handleDragStart} className="cursor-grab active:cursor-grabbing">
        <GraphChatTabs
          tabs={tabs}
          activeIndex={activeIndex}
          minimized={minimized}
          onTabClick={(i) => {
            onTabClick(i);
            if (minimized) onMinimize();
          }}
          onAddTab={onAddTab}
          onMinimize={onMinimize}
          onClose={onClose}
        />
      </div>

      {/* Message area (hidden when minimized) */}
      {!minimized && activeTab && (
        <ScrollArea className="flex-1">
          <div ref={scrollRef} className="space-y-3 p-4">
            {activeTab.messages.length === 0 && (
              <p className="mt-12 text-center text-xs text-muted-foreground">
                Send a message from the input below to start a conversation with{" "}
                {activeTab.agent}.
              </p>
            )}
            {activeTab.messages.map((msg, i) => {
              const isUser = msg.role === "user";
              return (
                <div key={i} className={isUser ? "text-right" : ""}>
                  <div
                    className={cn(
                      "inline-block max-w-[85%] px-3 py-2 text-sm",
                      isUser
                        ? "rounded-2xl rounded-br-md bg-primary text-primary-foreground"
                        : "rounded-2xl rounded-bl-md bg-muted",
                    )}
                  >
                    {!isUser && (
                      <span
                        className="mr-1.5 inline-block h-1.5 w-1.5 rounded-full align-middle"
                        style={{
                          backgroundColor:
                            AGENT_COLORS[activeTab.agent] ?? "#6b7280",
                        }}
                      />
                    )}
                    {msg.content}
                  </div>
                  <div className="mt-0.5 text-[10px] text-muted-foreground">
                    {timeAgo(msg.timestamp)}
                  </div>
                </div>
              );
            })}
          </div>
        </ScrollArea>
      )}
    </div>
  );
}
