import { useCallback, useEffect, useRef, useState } from "react";
import { useParams } from "react-router-dom";
import { api } from "@/lib/api";
import { getSocket } from "@/lib/socket";
import type { ProductConversation, ProductMessage } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Skeleton } from "@/components/ui/skeleton";
import { Send, Loader2 } from "lucide-react";
import { cn } from "@/lib/utils";
import type { Channel } from "phoenix";

const personaLabels: Record<string, string> = {
  researcher: "Researcher",
  strategist: "Strategist",
  architect: "Architect",
  designer: "Designer",
  memory_agent: "Memory",
};

const personaDescriptions: Record<string, string> = {
  researcher: "Pattern-finding and evidence-backed synthesis",
  strategist: "Decisions, requirements, and strategic direction",
  architect: "System design and technical architecture",
  designer: "User flows, interaction patterns, and UX specs",
  memory_agent: "Answer questions by traversing the product graph",
};

export function AgentChatPage() {
  const { projectId, persona } = useParams<{
    projectId: string;
    persona: string;
  }>();
  const pid = Number(projectId);
  const label = personaLabels[persona ?? ""] ?? persona;

  const [conversation, setConversation] = useState<ProductConversation | null>(
    null,
  );
  const [messages, setMessages] = useState<ProductMessage[]>([]);
  const [loading, setLoading] = useState(true);
  const [sending, setSending] = useState(false);
  const [streamDelta, setStreamDelta] = useState("");
  const [input, setInput] = useState("");
  const [error, setError] = useState<string | null>(null);

  const channelRef = useRef<Channel | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  // Auto-scroll to bottom when messages change
  useEffect(() => {
    const el = scrollRef.current;
    if (el) el.scrollTop = el.scrollHeight;
  }, [messages, streamDelta]);

  // Load or create conversation, join channel
  useEffect(() => {
    if (!projectId || !persona || isNaN(pid)) return;

    let cancelled = false;

    async function init() {
      setLoading(true);
      setError(null);

      try {
        // Find existing conversation for this persona
        const conversations = await api.listConversations(pid);
        let conv = conversations.find(
          (c) => c.persona === persona && c.status !== "archived",
        );

        if (!conv) {
          conv = await api.createConversation(pid, {
            persona: persona!,
            title: `${label} chat`,
          });
        }

        if (cancelled) return;

        // Join the channel to get full conversation with messages
        const socket = getSocket();
        const channel = socket.channel(
          `product_conversation:${conv.id}`,
          {},
        );

        channel.join()
          .receive("ok", (resp: { conversation: ProductConversation }) => {
            if (cancelled) return;
            setConversation(resp.conversation);
            setMessages(resp.conversation.messages ?? []);
            setLoading(false);
          })
          .receive("error", (resp: { reason: string }) => {
            if (cancelled) return;
            setError(resp.reason ?? "Failed to join conversation");
            setLoading(false);
          });

        // Listen for streaming chunks
        channel.on("stream_chunk", (payload: { delta: string }) => {
          setStreamDelta((prev) => prev + payload.delta);
        });

        // Listen for stream completion
        channel.on(
          "stream_done",
          (payload: { conversation: ProductConversation }) => {
            setStreamDelta("");
            setSending(false);
            setConversation(payload.conversation);
            setMessages(payload.conversation.messages ?? []);
          },
        );

        // Listen for conversation updates
        channel.on(
          "conversation_updated",
          (payload: { conversation: ProductConversation }) => {
            setConversation(payload.conversation);
            setMessages(payload.conversation.messages ?? []);
          },
        );

        channelRef.current = channel;
      } catch (err) {
        if (!cancelled) {
          setError(
            err instanceof Error ? err.message : "Failed to load conversation",
          );
          setLoading(false);
        }
      }
    }

    init();

    return () => {
      cancelled = true;
      if (channelRef.current) {
        channelRef.current.leave();
        channelRef.current = null;
      }
    };
  }, [projectId, persona]);

  const handleSend = useCallback(async () => {
    const text = input.trim();
    if (!text || sending) return;

    const channel = channelRef.current;
    if (!channel || !conversation) return;

    setInput("");
    setSending(true);
    setStreamDelta("");

    // Optimistic user message
    const optimistic: ProductMessage = {
      id: Date.now(),
      role: "user",
      content: text,
      citations: [],
      metadata: {},
      inserted_at: new Date().toISOString(),
    };
    setMessages((prev) => [...prev, optimistic]);

    // Send via channel for streaming support
    channel
      .push("message:create", { content: text })
      .receive("ok", (resp: { conversation: ProductConversation }) => {
        setConversation(resp.conversation);
        setMessages(resp.conversation.messages ?? []);
        // If response was synchronous (not streamed), clear sending
        if (!resp.conversation.channel_state?.resumable) {
          setSending(false);
          setStreamDelta("");
        }
      })
      .receive("error", (resp: { reason: string }) => {
        setSending(false);
        setStreamDelta("");
        // Add error as assistant message
        setMessages((prev) => [
          ...prev,
          {
            id: Date.now(),
            role: "assistant",
            content: `Error: ${resp.reason ?? "Something went wrong"}`,
            citations: [],
            metadata: {},
            inserted_at: new Date().toISOString(),
          },
        ]);
      });
  }, [input, sending, conversation]);

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      handleSend();
    }
  };

  if (loading) {
    return (
      <div className="flex h-full flex-col">
        <div className="shrink-0 border-b px-6 py-3">
          <Skeleton className="h-6 w-32" />
          <Skeleton className="mt-2 h-4 w-48" />
        </div>
        <div className="flex-1 p-6 space-y-4">
          <Skeleton className="h-16 w-3/4" />
          <Skeleton className="ml-auto h-16 w-2/3" />
          <Skeleton className="h-16 w-3/4" />
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="flex h-full flex-col">
        <div className="shrink-0 border-b px-6 py-3">
          <h1 className="text-lg font-semibold">{label}</h1>
        </div>
        <div className="flex-1 p-6">
          <Card>
            <CardContent className="py-8 text-center text-sm text-muted-foreground">
              {error}
            </CardContent>
          </Card>
        </div>
      </div>
    );
  }

  return (
    <div className="flex h-full flex-col">
      {/* Header */}
      <div className="shrink-0 border-b px-6 py-3">
        <div className="flex items-center gap-2">
          <h1 className="text-lg font-semibold">{label}</h1>
          <Badge
            variant="outline"
            className={cn(
              "text-[9px]",
              sending && "border-amber-500 text-amber-600",
            )}
          >
            {sending ? "thinking" : "idle"}
          </Badge>
        </div>
        <p className="mt-0.5 text-xs text-muted-foreground">
          {personaDescriptions[persona ?? ""] ?? ""}
        </p>
      </div>

      {/* Messages */}
      <ScrollArea className="flex-1">
        <div ref={scrollRef} className="space-y-4 p-6">
          {messages.length === 0 && !sending && (
            <Card>
              <CardContent className="py-12 text-center text-sm text-muted-foreground">
                Start a conversation with the {label}. Messages and agent
                responses will appear here.
              </CardContent>
            </Card>
          )}

          {messages.map((msg) => (
            <MessageBubble key={msg.id} message={msg} />
          ))}

          {/* Streaming indicator */}
          {sending && streamDelta && (
            <div className="flex gap-3">
              <div className="max-w-[80%] rounded-2xl rounded-bl-md bg-muted px-4 py-3">
                <p className="whitespace-pre-wrap text-sm">{streamDelta}</p>
                <span className="inline-block h-4 w-1 animate-pulse bg-foreground/50" />
              </div>
            </div>
          )}

          {sending && !streamDelta && (
            <div className="flex gap-3">
              <div className="flex items-center gap-2 rounded-2xl rounded-bl-md bg-muted px-4 py-3 text-sm text-muted-foreground">
                <Loader2 className="h-3.5 w-3.5 animate-spin" />
                {label} is thinking...
              </div>
            </div>
          )}
        </div>
      </ScrollArea>

      {/* Input */}
      <div className="shrink-0 border-t px-6 py-4">
        <div className="flex gap-2">
          <textarea
            ref={textareaRef}
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder={`Message ${label}...`}
            rows={1}
            className="flex-1 resize-none rounded-lg border bg-background px-3 py-2 text-sm placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-ring"
          />
          <Button
            size="icon"
            onClick={handleSend}
            disabled={!input.trim() || sending}
          >
            <Send className="h-4 w-4" />
          </Button>
        </div>
      </div>
    </div>
  );
}

function MessageBubble({ message }: { message: ProductMessage }) {
  const isUser = message.role === "user";

  return (
    <div className={cn("flex gap-3", isUser && "justify-end")}>
      <div
        className={cn(
          "max-w-[80%] rounded-2xl px-4 py-3",
          isUser
            ? "rounded-br-md bg-primary text-primary-foreground"
            : "rounded-bl-md bg-muted",
        )}
      >
        <p className="whitespace-pre-wrap text-sm">{message.content}</p>
        {message.citations.length > 0 && (
          <div className="mt-2 flex flex-wrap gap-1">
            {message.citations.map((cit, i) => (
              <Badge key={i} variant="secondary" className="text-[9px]">
                {cit.label ?? cit.source_title ?? `Source ${i + 1}`}
              </Badge>
            ))}
          </div>
        )}
        {message.inserted_at && (
          <p
            className={cn(
              "mt-1 text-[10px]",
              isUser
                ? "text-primary-foreground/60"
                : "text-muted-foreground",
            )}
          >
            {new Date(message.inserted_at).toLocaleTimeString([], {
              hour: "2-digit",
              minute: "2-digit",
            })}
          </p>
        )}
      </div>
    </div>
  );
}
