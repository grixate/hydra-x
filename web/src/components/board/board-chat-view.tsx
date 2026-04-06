import { useRef, useEffect, useState, useCallback } from "react";
import type { useChatState } from "@/hooks/use-chat-state";
import { UniversalInput } from "@/components/chat/universal-input";
import { BoardChatMessage } from "./board-chat-message";
import type { GraphDataNode } from "@/types";

type BoardChatViewProps = {
  projectId: number;
  chatState: ReturnType<typeof useChatState>;
};

function makeContextNode(nodeType: string, nodeId: number): GraphDataNode {
  return {
    id: `${nodeType}-${nodeId}`,
    node_type: nodeType,
    node_id: nodeId,
    title: `${nodeType}#${nodeId}`,
    status: "",
    body: "",
    connection_count: 0,
    upstream_count: 0,
    downstream_count: 0,
    flag_count: 0,
  };
}

export function BoardChatView({ projectId, chatState }: BoardChatViewProps) {
  const {
    activeTab,
    handleChatSubmit,
    handleAgentChange,
  } = chatState;

  const messages = activeTab?.messages ?? [];
  const bottomRef = useRef<HTMLDivElement>(null);

  // Context nodes selected by clicking inline node cards
  const [contextNodes, setContextNodes] = useState<GraphDataNode[]>([]);

  const handleSelectContext = useCallback((nodeType: string, nodeId: number) => {
    setContextNodes((prev) => {
      const key = `${nodeType}-${nodeId}`;
      const exists = prev.some((n) => n.id === key);
      if (exists) {
        return prev.filter((n) => n.id !== key);
      }
      return [...prev, makeContextNode(nodeType, nodeId)];
    });
  }, []);

  const handleClearContext = useCallback(() => {
    setContextNodes([]);
  }, []);

  // Auto-scroll to bottom on new messages
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages.length]);

  return (
    <div className="flex h-full flex-col">
      {/* Scrollable message area */}
      <div className="flex-1 overflow-y-auto">
        <div className="mx-auto max-w-3xl px-4 py-6 space-y-5">
          {messages.length === 0 && (
            <div className="flex flex-col items-center justify-center py-24 text-center text-muted-foreground">
              <p className="text-lg font-medium">Start a conversation</p>
              <p className="mt-1 text-sm">
                Ask a question or explore an idea with the agent.
              </p>
            </div>
          )}

          {messages.map((msg, i) => (
            <BoardChatMessage
              key={`${msg.role}-${i}-${msg.timestamp}`}
              role={msg.role}
              content={msg.content}
              agent={activeTab?.agent}
              projectId={projectId}
              onSelectContext={handleSelectContext}
            />
          ))}

          {/* Scroll anchor */}
          <div ref={bottomRef} />
        </div>
      </div>

      {/* Input — positioned at bottom */}
      <div className="relative mx-auto w-full max-w-3xl" style={{ minHeight: 80 }}>
        <UniversalInput
          surface="board"
          projectId={projectId}
          onSubmit={handleChatSubmit}
          currentAgent={activeTab?.agent ?? "strategist"}
          onAgentChange={handleAgentChange}
          selectedNodes={contextNodes}
          onClearSelection={handleClearContext}
        />
      </div>
    </div>
  );
}
