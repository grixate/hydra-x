import { useCallback, useEffect, useRef, useState } from "react";
import { api } from "@/lib/api";
import { getSocket } from "@/lib/socket";
import type { ProductConversation, ProductMessage } from "@/types";
import { UniversalInput } from "@/components/chat/universal-input";
import { BoardChatMessage } from "@/components/board/board-chat-message";
import { Skeleton } from "@/components/ui/skeleton";
import { Loader2 } from "lucide-react";
import type { Channel } from "phoenix";

const PAGE_SIZE = 30;

interface AgentConversationPaneProps {
  projectId: number;
  persona: string;
}

export function AgentConversationPane({ projectId, persona }: AgentConversationPaneProps) {
  const [conversation, setConversation] = useState<ProductConversation | null>(null);
  const [messages, setMessages] = useState<ProductMessage[]>([]);
  const [loading, setLoading] = useState(true);
  const [sending, setSending] = useState(false);
  const [streamDelta, setStreamDelta] = useState("");
  const [hasMore, setHasMore] = useState(false);
  const [loadingMore, setLoadingMore] = useState(false);

  const scrollRef = useRef<HTMLDivElement>(null);
  const channelRef = useRef<Channel | null>(null);
  const initialScrollDone = useRef(false);

  // Scroll to bottom instantly (no animation)
  const scrollToBottom = useCallback(() => {
    const el = scrollRef.current;
    if (el) el.scrollTop = el.scrollHeight;
  }, []);

  // Load or create conversation — fetch latest page only
  useEffect(() => {
    setLoading(true);
    initialScrollDone.current = false;
    api
      .listConversations(projectId)
      .then(async (convs) => {
        const existing = convs.find(
          (c) => c.persona === persona && (!c.metadata?.channel || c.metadata.channel === "agent_direct"),
        );
        if (existing) {
          const full = await api.getConversation(projectId, existing.id, { limit: PAGE_SIZE });
          setConversation(full);
          setMessages(full.messages ?? []);
          setHasMore(full.has_more ?? false);
        }
      })
      .catch(() => {})
      .finally(() => setLoading(false));
  }, [projectId, persona]);

  // After initial messages load, snap to bottom
  useEffect(() => {
    if (!loading && messages.length > 0 && !initialScrollDone.current) {
      initialScrollDone.current = true;
      // Use rAF to ensure DOM has rendered
      requestAnimationFrame(scrollToBottom);
    }
  }, [loading, messages.length, scrollToBottom]);

  // Join channel for streaming
  useEffect(() => {
    if (!conversation) return;
    const socket = getSocket();
    const ch = socket.channel(`product_conversation:${conversation.id}`, {});
    ch.join();
    ch.on("message_delta", ({ delta }: { delta: string }) => {
      setStreamDelta((prev) => prev + delta);
    });
    ch.on("message_complete", ({ message }: { message: ProductMessage }) => {
      setStreamDelta("");
      setMessages((prev) => [...prev, message]);
    });
    channelRef.current = ch;
    return () => {
      ch.leave();
      channelRef.current = null;
    };
  }, [conversation?.id]);

  // Auto-scroll to bottom on new messages / streaming (only if already near bottom)
  useEffect(() => {
    const el = scrollRef.current;
    if (!el || !initialScrollDone.current) return;
    const distanceFromBottom = el.scrollHeight - el.scrollTop - el.clientHeight;
    // Only auto-scroll if user is near the bottom (within 150px)
    if (distanceFromBottom < 150) {
      scrollToBottom();
    }
  }, [messages.length, streamDelta, scrollToBottom]);

  // Load older messages on scroll to top
  const handleScroll = useCallback(() => {
    const el = scrollRef.current;
    if (!el || !hasMore || loadingMore || !conversation) return;

    if (el.scrollTop < 100) {
      setLoadingMore(true);
      const oldestId = messages[0]?.id;
      api
        .getConversation(projectId, conversation.id, {
          limit: PAGE_SIZE,
          before: oldestId,
        })
        .then((data) => {
          const older = data.messages ?? [];
          if (older.length > 0) {
            // Preserve scroll position: measure before prepend
            const prevHeight = el.scrollHeight;
            setMessages((prev) => [...older, ...prev]);
            setHasMore(data.has_more ?? false);
            // After React renders the new messages, restore scroll position
            requestAnimationFrame(() => {
              el.scrollTop = el.scrollHeight - prevHeight;
            });
          } else {
            setHasMore(false);
          }
        })
        .catch(() => {})
        .finally(() => setLoadingMore(false));
    }
  }, [hasMore, loadingMore, conversation, messages, projectId]);

  const handleSubmit = useCallback(
    async (text: string) => {
      if (!text.trim() || sending) return;
      setSending(true);

      const userMsg: ProductMessage = {
        id: Date.now(),
        role: "user",
        content: text,
        citations: [],
        metadata: {},
        inserted_at: new Date().toISOString(),
      };
      setMessages((prev) => [...prev, userMsg]);
      // Scroll to bottom for new user message
      requestAnimationFrame(scrollToBottom);

      try {
        let convId = conversation?.id;
        if (!convId) {
          const newConv = await api.createConversation(projectId, {
            persona,
            title: `${persona} — direct conversation`,
          });
          setConversation(newConv);
          convId = newConv.id;
        }

        const result = await api.sendConversationMessage(projectId, convId, text);
        const responseContent = result?.response?.content;
        if (responseContent) {
          setMessages((prev) => [
            ...prev,
            {
              id: Date.now() + 1,
              role: "assistant" as const,
              content: responseContent,
              citations: [],
              metadata: {},
              inserted_at: new Date().toISOString(),
            },
          ]);
        }
      } catch {
        // Error handling
      } finally {
        setSending(false);
      }
    },
    [conversation, projectId, persona, sending, scrollToBottom],
  );

  if (loading) {
    return (
      <div className="flex h-full flex-col p-4 space-y-4">
        <Skeleton className="h-16 w-3/4" />
        <Skeleton className="h-12 w-1/2 ml-auto" />
        <Skeleton className="h-16 w-3/4" />
      </div>
    );
  }

  const personaLabel =
    persona === "researcher" ? "Researcher"
    : persona === "strategist" ? "Strategist"
    : persona === "architect" ? "Architect"
    : persona === "designer" ? "Designer"
    : persona === "memory_agent" ? "Memory"
    : persona;

  return (
    <div className="relative h-full">
      <div
        ref={scrollRef}
        className="flex h-full flex-col overflow-y-auto pb-40"
        onScroll={handleScroll}
      >
        {/* Spacer pushes content to the bottom when there are few messages */}
        <div className="flex-1" />

        <div className="px-4 py-4 space-y-4">
          {loadingMore && (
            <div className="flex justify-center py-3">
              <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />
            </div>
          )}

          {messages.length === 0 && !sending && (
            <div className="flex flex-col items-center justify-center py-16 text-center text-muted-foreground">
              <p className="text-sm font-medium">Start a conversation with the {personaLabel}.</p>
              <p className="mt-1 text-xs text-muted-foreground">
                Ask about product strategy, review decisions,<br />
                or get recommendations based on your product graph.
              </p>
            </div>
          )}

          {messages.map((msg, i) => (
            <BoardChatMessage
              key={`${msg.role}-${i}`}
              role={msg.role}
              content={msg.content}
              agent={persona}
              projectId={projectId}
              onSelectContext={() => {}}
            />
          ))}

          {streamDelta && (
            <BoardChatMessage
              role="assistant"
              content={streamDelta}
              agent={persona}
              projectId={projectId}
              onSelectContext={() => {}}
            />
          )}

          {sending && !streamDelta && (
            <div className="text-xs text-muted-foreground animate-pulse">Thinking...</div>
          )}
        </div>
      </div>

      <UniversalInput
        surface="board"
        projectId={projectId}
        onSubmit={(msg) => handleSubmit(msg)}
        currentAgent={persona}
        onAgentChange={() => {}}
      />
    </div>
  );
}
