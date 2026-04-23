import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useLocation, useNavigate, useParams } from "react-router-dom";
import type { Channel } from "phoenix";
import { X } from "lucide-react";

import { Skeleton } from "@/components/ui/skeleton";
import { Button } from "@/components/ui/button";
import { api } from "@/lib/api";
import { subscribeToProject } from "@/lib/project-channel";
import { getSocket } from "@/lib/socket";
import type { AgentTask, ProductConversation, ProductMessage } from "@/types";

import { AGENTS, UniversalInput } from "./universal-input";
import { BoardChatMessage } from "@/components/board/board-chat-message";
import type { ChipSurface } from "./surface-suggestion-chips";
import { OnboardingChips } from "@/components/onboarding/onboarding-chips";
import { useOnboarding } from "@/hooks/use-onboarding";
import { ProposalCard } from "@/components/command-center/proposal-card";
import { useGraphChatContext } from "./graph-chat-context";

export type ChatSurface =
  | "stream"
  | "command_center"
  | "library"
  | "graph"
  | "board"
  | "agent"
  | "other";

type SurfaceConfig = {
  defaultAgent: string;
  chipSurface: ChipSurface | null;
};

export const SURFACE_CONFIG: Record<ChatSurface, SurfaceConfig> = {
  stream: { defaultAgent: "strategist", chipSurface: "stream" },
  command_center: { defaultAgent: "strategist", chipSurface: "command_center" },
  library: { defaultAgent: "researcher", chipSurface: "library" },
  graph: { defaultAgent: "strategist", chipSurface: "graph" },
  board: { defaultAgent: "strategist", chipSurface: "board" },
  agent: { defaultAgent: "strategist", chipSurface: null },
  other: { defaultAgent: "strategist", chipSurface: null },
};

const EMBEDDED_CHAT_EXTERNAL_REF = "chat_dock";
const AGENT_SWITCH_EVENT = "agent-chat-pane:switch-agent";

export function classifySurface(pathname: string, projectId: string | undefined): ChatSurface {
  if (!projectId) return "other";
  const base = `/projects/${projectId}`;
  if (pathname === base || pathname === `${base}/stream`) return "stream";
  if (pathname.startsWith(`${base}/command-center`)) return "command_center";
  if (pathname.startsWith(`${base}/library`)) return "library";
  if (pathname.startsWith(`${base}/graph`)) return "graph";
  if (pathname.startsWith(`${base}/board`)) return "board";
  if (pathname.startsWith(`${base}/agents`)) return "agent";
  return "other";
}

function agentStorageKey(projectId: string, surface: ChatSurface) {
  return `agent-chat-pane:${projectId}:${surface}`;
}

function loadPersistedAgent(projectId: string | undefined, surface: ChatSurface): string | null {
  if (!projectId) return null;
  try {
    const raw = localStorage.getItem(agentStorageKey(projectId, surface));
    if (!raw) return null;
    return JSON.parse(raw).agent ?? null;
  } catch {
    return null;
  }
}

function persistAgent(projectId: string, surface: ChatSurface, agent: string) {
  try {
    localStorage.setItem(agentStorageKey(projectId, surface), JSON.stringify({ agent }));
  } catch {
    /* ignore */
  }
}

export function dispatchAgentChatPaneSwitch(agent: string) {
  if (typeof window === "undefined") return;
  window.dispatchEvent(new CustomEvent(AGENT_SWITCH_EVENT, { detail: { agent } }));
}

export function AgentChatPane() {
  const { projectId } = useParams<{ projectId: string }>();
  const location = useLocation();
  const surface = classifySurface(location.pathname, projectId);
  const config = SURFACE_CONFIG[surface];

  const persistedAgent = useMemo(
    () => loadPersistedAgent(projectId, surface),
    [projectId, surface],
  );

  const [agent, setAgent] = useState<string>(persistedAgent ?? config.defaultAgent);

  useEffect(() => {
    setAgent(persistedAgent ?? config.defaultAgent);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [surface, projectId]);

  useEffect(() => {
    if (!projectId) return;
    persistAgent(projectId, surface, agent);
  }, [projectId, surface, agent]);

  useEffect(() => {
    function handler(event: Event) {
      const detail = (event as CustomEvent).detail as { agent?: string } | undefined;
      if (!detail?.agent) return;
      setAgent(detail.agent);
    }
    window.addEventListener(AGENT_SWITCH_EVENT, handler);
    return () => window.removeEventListener(AGENT_SWITCH_EVENT, handler);
  }, []);

  if (!projectId) {
    return (
      <div className="flex h-full items-center justify-center text-xs text-muted-foreground">
        Select a project to chat.
      </div>
    );
  }

  return (
    <AgentChatPaneInner
      projectId={Number(projectId)}
      surface={surface}
      agent={agent}
      chipSurface={config.chipSurface}
      onAgentChange={setAgent}
    />
  );
}

function AgentChatPaneInner({
  projectId,
  surface,
  agent,
  chipSurface,
  onAgentChange,
}: {
  projectId: number;
  surface: ChatSurface;
  agent: string;
  chipSurface: ChipSurface | null;
  onAgentChange: (agent: string) => void;
}) {
  const [conversation, setConversation] = useState<ProductConversation | null>(null);
  const [messages, setMessages] = useState<ProductMessage[]>([]);
  const [loading, setLoading] = useState(true);
  const [sending, setSending] = useState(false);
  const [streamDelta, setStreamDelta] = useState("");
  const [pendingProposals, setPendingProposals] = useState<AgentTask[]>([]);

  const navigate = useNavigate();
  const scrollRef = useRef<HTMLDivElement>(null);
  const channelRef = useRef<Channel | null>(null);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setMessages([]);
    setConversation(null);

    api
      .createConversation(projectId, {
        persona: agent,
        title: `${agent} — chat`,
        externalRef: EMBEDDED_CHAT_EXTERNAL_REF,
        channel: "chat_dock",
      })
      .then(async (conv) => {
        if (cancelled) return;
        const full = await api.getConversation(projectId, conv.id, { limit: 40 });
        if (cancelled) return;
        setConversation(full);
        setMessages(full.messages ?? []);
      })
      .catch(() => {})
      .finally(() => {
        if (!cancelled) setLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [projectId, agent]);

  useEffect(() => {
    if (!conversation) return;
    const socket = getSocket();
    const ch = socket.channel(`product_conversation:${conversation.id}`, {});
    ch.join();

    const onDelta = ({ delta }: { delta?: string }) => {
      if (delta) setStreamDelta((prev) => prev + delta);
    };
    ch.on("stream_chunk", onDelta);
    ch.on("message_delta", onDelta);

    const onDone = async () => {
      try {
        const refreshed = await api.getConversation(projectId, conversation.id, { limit: 40 });
        setConversation(refreshed);
        setMessages(refreshed.messages ?? []);
      } finally {
        setStreamDelta("");
      }
    };
    ch.on("stream_done", onDone);
    ch.on("message_complete", ({ message }: { message: ProductMessage }) => {
      setStreamDelta("");
      setMessages((prev) => [...prev, message]);
    });

    channelRef.current = ch;
    return () => {
      ch.leave();
      channelRef.current = null;
    };
  }, [conversation?.id, projectId]);

  useEffect(() => {
    if (!conversation) return;
    const unsub = subscribeToProject(projectId, [
      {
        event: "chat.message_inserted",
        handler: (payload) => {
          const convId = payload.conversation_id as number | undefined;
          const message = payload.message as ProductMessage | undefined;
          if (!convId || !message) return;
          if (convId !== conversation.id) return;
          setMessages((prev) => [...prev, message]);
        },
      },
    ]);
    return unsub;
  }, [projectId, conversation?.id]);

  useEffect(() => {
    const el = scrollRef.current;
    if (!el) return;
    el.scrollTop = el.scrollHeight;
  }, [messages.length, streamDelta]);

  useEffect(() => {
    let cancelled = false;
    setPendingProposals([]);

    api
      .listProposals(projectId, { agent_id: agent })
      .then((items) => {
        if (!cancelled) setPendingProposals(items ?? []);
      })
      .catch(() => {});

    const unsub = subscribeToProject(projectId, [
      {
        event: "agent_task.state_changed",
        handler: (payload) => {
          const task = payload.task as AgentTask | undefined;
          if (!task || task.agent_id !== agent) return;
          setPendingProposals((prev) => {
            const without = prev.filter((p) => p.id !== task.id);
            return task.state === "proposing" ? [task, ...without] : without;
          });
        },
      },
      {
        event: "agent_task.created",
        handler: (payload) => {
          const task = payload.task as AgentTask | undefined;
          if (!task || task.agent_id !== agent || task.state !== "proposing") return;
          setPendingProposals((prev) =>
            prev.some((p) => p.id === task.id) ? prev : [task, ...prev],
          );
        },
      },
    ]);

    return () => {
      cancelled = true;
      unsub();
    };
  }, [projectId, agent]);

  const handleSubmit = useCallback(
    async (text: string, targetAgent: string) => {
      const trimmed = text.trim();
      if (!trimmed || sending) return;

      if (targetAgent !== agent) onAgentChange(targetAgent);

      setSending(true);
      const optimistic: ProductMessage = {
        id: Date.now(),
        role: "user",
        content: trimmed,
        citations: [],
        metadata: {},
        inserted_at: new Date().toISOString(),
      };
      setMessages((prev) => [...prev, optimistic]);

      try {
        let convId = conversation?.id;
        if (!convId) {
          const created = await api.createConversation(projectId, {
            persona: targetAgent,
            title: `${targetAgent} — chat`,
            externalRef: EMBEDDED_CHAT_EXTERNAL_REF,
            channel: "chat_dock",
          });
          convId = created.id;
          setConversation(created);
        }
        const result = await api.sendConversationMessage(projectId, convId, trimmed);
        const replyContent = result?.response?.content;
        if (replyContent) {
          setMessages((prev) => [
            ...prev,
            {
              id: Date.now() + 1,
              role: "assistant",
              content: replyContent,
              citations: [],
              metadata: {},
              inserted_at: new Date().toISOString(),
            } as ProductMessage,
          ]);
        }
      } finally {
        setSending(false);
      }
    },
    [agent, conversation, onAgentChange, projectId, sending],
  );

  const agentMeta = AGENTS.find((a) => a.slug === agent) ?? AGENTS[0];
  const AgentIcon = agentMeta.icon;

  return (
    <aside className="flex h-full min-w-0 flex-col bg-background">
      <div className="flex items-center justify-between border-b px-3 py-2">
        <div className="flex items-center gap-2 min-w-0">
          <AgentIcon className="h-4 w-4 shrink-0 text-muted-foreground" />
          <span className="text-sm font-medium truncate">{agentMeta.label}</span>
          <span className="text-[10px] uppercase tracking-widest text-muted-foreground truncate">
            {surface.replace(/_/g, " ")}
          </span>
        </div>
        <Button
          variant="ghost"
          size="icon"
          className="h-7 w-7 shrink-0"
          onClick={() => {
            window.dispatchEvent(
              new KeyboardEvent("keydown", { key: "j", metaKey: true, bubbles: true }),
            );
          }}
          aria-label="Collapse chat"
          title="Collapse (⌘J)"
        >
          <X className="h-4 w-4" />
        </Button>
      </div>

      {pendingProposals.length > 0 ? (
        <div className="border-b bg-muted/20 px-3 py-2 space-y-2">
          <p className="text-[10px] font-medium uppercase tracking-widest text-muted-foreground">
            Pending proposals
          </p>
          {pendingProposals.slice(0, 3).map((task) => (
            <ProposalCard
              key={task.id}
              task={task}
              projectId={projectId}
              onReview={() =>
                navigate(`/projects/${projectId}/agents/${task.agent_id}`)
              }
              onDismiss={async () => {
                await api.dismissProposal(projectId, task.id).catch(() => {});
                setPendingProposals((prev) => prev.filter((p) => p.id !== task.id));
              }}
            />
          ))}
        </div>
      ) : null}

      <div ref={scrollRef} className="flex-1 overflow-y-auto px-3 py-3">
        {loading ? (
          <div className="space-y-3">
            <Skeleton className="h-10 w-3/4" />
            <Skeleton className="h-8 w-1/2 ml-auto" />
            <Skeleton className="h-10 w-3/4" />
          </div>
        ) : messages.length === 0 && !sending ? (
          <div className="flex flex-col items-center justify-center py-10 text-center text-xs text-muted-foreground">
            <p className="font-medium">Start a conversation with the {agentMeta.label}.</p>
          </div>
        ) : (
          <div className="space-y-3">
            {messages.map((msg, i) => (
              <ChatMessageRow
                key={`${msg.id ?? i}-${msg.role}`}
                message={msg}
                agent={agent}
                projectId={projectId}
              />
            ))}
            {streamDelta ? (
              <BoardChatMessage
                role="assistant"
                content={streamDelta}
                agent={agent}
                projectId={projectId}
                onSelectContext={() => {}}
              />
            ) : null}
            {sending && !streamDelta ? (
              <div className="text-[11px] text-muted-foreground animate-pulse">Thinking…</div>
            ) : null}
          </div>
        )}
      </div>

      <PaneChipsAndInput
        projectId={projectId}
        agent={agent}
        chipSurface={chipSurface}
        surface={surface}
        onAgentChange={onAgentChange}
        onSubmit={handleSubmit}
      />
    </aside>
  );
}

function PaneChipsAndInput({
  projectId,
  agent,
  surface,
  onAgentChange,
  onSubmit,
}: {
  projectId: number;
  agent: string;
  chipSurface: ChipSurface | null;
  surface: ChatSurface;
  onAgentChange: (agent: string) => void;
  onSubmit: (text: string, agent: string) => void;
}) {
  const { status: onboarding, skip, refresh } = useOnboarding(projectId);
  const [prefill, setPrefill] = useState<string>("");
  const graphCtx = useGraphChatContext();
  const isGraph = surface === "graph" && !!graphCtx;

  const showOnboardingChips =
    onboarding?.state === "pending" && agent === "strategist";

  async function handleSkip() {
    await skip();
    refresh();
  }

  return (
    <div className="relative">
      {showOnboardingChips ? (
        <OnboardingChips
          onPrefill={(text) => setPrefill(text)}
          onSend={(text) => onSubmit(text, agent)}
          onSkip={handleSkip}
        />
      ) : null}
      <UniversalInput
        surface={isGraph ? "graph" : "stream"}
        projectId={projectId}
        initialValue={prefill}
        onSubmit={(text, ag) => {
          onSubmit(text, ag);
          setPrefill("");
        }}
        currentAgent={agent}
        onAgentChange={onAgentChange}
        selectedNodes={isGraph ? graphCtx!.contextNodes : undefined}
        previewNode={isGraph ? graphCtx!.previewNode : undefined}
        onClearSelection={isGraph ? graphCtx!.onClearContext : undefined}
        onRemoveNode={isGraph ? graphCtx!.onRemoveContext : undefined}
        docked
      />
    </div>
  );
}

function ChatMessageRow({
  message,
  agent,
  projectId,
}: {
  message: ProductMessage;
  agent: string;
  projectId: number;
}) {
  if (message.role === "system") {
    const metadata = (message.metadata ?? {}) as {
      kind?: string;
      target_agent?: string;
      target_conversation_id?: number;
    };
    const targetAgent = metadata.target_agent;
    return (
      <div className="flex justify-center">
        <div className="rounded-md border border-dashed bg-muted/30 px-2 py-1 text-[11px] text-muted-foreground">
          {message.content}
          {metadata.target_conversation_id && targetAgent ? (
            <>
              {" "}
              <button
                type="button"
                className="font-medium text-foreground underline decoration-dotted"
                onClick={() => dispatchAgentChatPaneSwitch(targetAgent)}
              >
                view
              </button>
            </>
          ) : null}
        </div>
      </div>
    );
  }

  return (
    <BoardChatMessage
      role={message.role}
      content={message.content}
      agent={agent}
      projectId={projectId}
      onSelectContext={() => {}}
    />
  );
}

