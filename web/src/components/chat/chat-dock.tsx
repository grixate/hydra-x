import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useLocation, useParams } from "react-router-dom";
import { MessageSquare, X } from "lucide-react";

import { Skeleton } from "@/components/ui/skeleton";
import { Button } from "@/components/ui/button";
import { api } from "@/lib/api";
import { subscribeToProject } from "@/lib/project-channel";
import { getSocket } from "@/lib/socket";
import type { Channel } from "phoenix";
import type { AgentTask, ProductConversation, ProductMessage } from "@/types";

import { AGENTS, UniversalInput } from "./universal-input";
import { BoardChatMessage } from "@/components/board/board-chat-message";
import { SurfaceSuggestionChips, type ChipSurface } from "./surface-suggestion-chips";
import { OnboardingChips } from "@/components/onboarding/onboarding-chips";
import { useOnboarding } from "@/hooks/use-onboarding";
import { ProposalCard } from "@/components/command-center/proposal-card";
import { useNavigate } from "react-router-dom";

type ChatSurface =
  | "stream"
  | "command_center"
  | "library"
  | "graph"
  | "board"
  | "agent"
  | "other";

type SurfaceConfig = {
  defaultAgent: string;
  defaultExpanded: boolean;
  chipSurface: ChipSurface | null;
};

const SURFACE_CONFIG: Record<ChatSurface, SurfaceConfig> = {
  stream: { defaultAgent: "strategist", defaultExpanded: false, chipSurface: "stream" },
  command_center: { defaultAgent: "strategist", defaultExpanded: false, chipSurface: "command_center" },
  library: { defaultAgent: "researcher", defaultExpanded: true, chipSurface: "library" },
  graph: { defaultAgent: "strategist", defaultExpanded: true, chipSurface: "graph" },
  board: { defaultAgent: "strategist", defaultExpanded: true, chipSurface: "board" },
  agent: { defaultAgent: "strategist", defaultExpanded: true, chipSurface: null },
  other: { defaultAgent: "strategist", defaultExpanded: false, chipSurface: null },
};

// Surfaces where ChatDock is the canonical chat primitive for Cycle 1.
// Graph and Board still own their own chat integration (Cycle-2 migration).
const DOCK_ENABLED: Record<ChatSurface, boolean> = {
  stream: true,
  command_center: true,
  library: true,
  agent: true,
  graph: false,
  board: false,
  other: false,
};

const EMBEDDED_CHAT_EXTERNAL_REF = "chat_dock";
const AGENT_SWITCH_EVENT = "chat-dock:switch-agent";

function classifySurface(pathname: string, projectId: string | undefined): ChatSurface {
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

function storageKey(projectId: string, surface: ChatSurface) {
  return `chat-dock:${projectId}:${surface}`;
}

function loadPersisted(projectId: string | undefined, surface: ChatSurface) {
  if (!projectId) return null;
  try {
    const raw = localStorage.getItem(storageKey(projectId, surface));
    if (!raw) return null;
    return JSON.parse(raw) as { expanded?: boolean; agent?: string };
  } catch {
    return null;
  }
}

function persistChatState(projectId: string, surface: ChatSurface, next: { expanded: boolean; agent: string }) {
  try {
    localStorage.setItem(storageKey(projectId, surface), JSON.stringify(next));
  } catch {
    // ignore quota errors
  }
}

/**
 * Fired by a system-message row ("view" link) to switch the dock's active
 * agent tab to the mentioned target. Listened to inside `ChatDockInner`.
 */
export function dispatchChatDockAgentSwitch(agent: string) {
  if (typeof window === "undefined") return;
  window.dispatchEvent(new CustomEvent(AGENT_SWITCH_EVENT, { detail: { agent } }));
}

export function ChatDock() {
  const { projectId } = useParams<{ projectId: string }>();
  const location = useLocation();

  const surface = classifySurface(location.pathname, projectId);
  const enabled = DOCK_ENABLED[surface];
  const config = SURFACE_CONFIG[surface];

  const persisted = useMemo(
    () => loadPersisted(projectId, surface),
    // Re-read when surface or project changes.
    [projectId, surface],
  );

  const [expanded, setExpanded] = useState<boolean>(persisted?.expanded ?? config.defaultExpanded);
  const [agent, setAgent] = useState<string>(persisted?.agent ?? config.defaultAgent);

  // Reset state when surface flips (config/defaults may differ).
  useEffect(() => {
    setExpanded(persisted?.expanded ?? config.defaultExpanded);
    setAgent(persisted?.agent ?? config.defaultAgent);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [surface, projectId]);

  // Persist per-(project, surface).
  useEffect(() => {
    if (!projectId) return;
    persistChatState(projectId, surface, { expanded, agent });
  }, [projectId, surface, expanded, agent]);

  // Global agent-switch bridge — system-message rows fire an event to swap
  // the active agent without needing to route through a context.
  useEffect(() => {
    function handler(event: Event) {
      const detail = (event as CustomEvent).detail as { agent?: string } | undefined;
      if (!detail?.agent) return;
      setAgent(detail.agent);
      setExpanded(true);
    }
    window.addEventListener(AGENT_SWITCH_EVENT, handler);
    return () => window.removeEventListener(AGENT_SWITCH_EVENT, handler);
  }, []);

  if (!projectId || !enabled) return null;

  return (
    <ChatDockInner
      projectId={Number(projectId)}
      surface={surface}
      agent={agent}
      expanded={expanded}
      chipSurface={config.chipSurface}
      onAgentChange={setAgent}
      onToggleExpanded={() => setExpanded((value) => !value)}
    />
  );
}

function ChatDockInner({
  projectId,
  surface,
  agent,
  expanded,
  chipSurface,
  onAgentChange,
  onToggleExpanded,
}: {
  projectId: number;
  surface: ChatSurface;
  agent: string;
  expanded: boolean;
  chipSurface: ChipSurface | null;
  onAgentChange: (agent: string) => void;
  onToggleExpanded: () => void;
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
    if (!expanded) return;
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
  }, [projectId, agent, expanded]);

  useEffect(() => {
    if (!conversation) return;

    const socket = getSocket();
    const ch = socket.channel(`product_conversation:${conversation.id}`, {});
    ch.join();

    // Backend pushes `stream_chunk` / `stream_done`. Keep the old
    // `message_delta` / `message_complete` listeners too so any migration
    // still lands on the same handlers.
    const onDelta = ({ delta }: { delta?: string }) => {
      if (delta) setStreamDelta((prev) => prev + delta);
    };
    ch.on("stream_chunk", onDelta);
    ch.on("message_delta", onDelta);

    const onDone = async () => {
      // Re-fetch the conversation to get the newly-persisted assistant
      // message (server pushes `stream_done` with the conversation
      // refreshed but we already load via getConversation for safety).
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
  }, [conversation?.id]);

  // Cross-thread system-message surfacing. Broadcast from the backend when
  // e.g. one agent @-mentions another with intent=request_task — the source
  // thread gets a "view" reference, the target gets the task.
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

  // B1.4 — surface open proposals from the active agent inline in the
  // thread so the user can review without bouncing to the Command Center.
  useEffect(() => {
    if (!expanded) return;
    let cancelled = false;

    // Reset stale proposals from the previous agent so the user doesn't
    // briefly see another agent's cards while this agent's list loads.
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
  }, [projectId, agent, expanded]);

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

  if (!expanded) {
    return (
      <aside className="flex w-10 shrink-0 flex-col items-center gap-2 border-l bg-card/40 py-2">
        <button
          type="button"
          onClick={onToggleExpanded}
          aria-label="Expand chat"
          className="flex h-8 w-8 items-center justify-center rounded-md border bg-background text-muted-foreground transition-colors hover:text-foreground"
        >
          <MessageSquare className="h-4 w-4" />
        </button>
        <div
          className="flex h-8 w-8 items-center justify-center rounded-md border bg-background text-muted-foreground"
          title={agentMeta.label}
        >
          <AgentIcon className="h-4 w-4" />
        </div>
      </aside>
    );
  }

  return (
    <aside className="flex w-[420px] shrink-0 flex-col border-l bg-background">
      <div className="flex items-center justify-between border-b px-3 py-2">
        <div className="flex items-center gap-2">
          <AgentIcon className="h-4 w-4 text-muted-foreground" />
          <span className="text-sm font-medium">{agentMeta.label}</span>
          <span className="text-[10px] uppercase tracking-widest text-muted-foreground">
            {surface.replace(/_/g, " ")}
          </span>
        </div>
        <Button
          variant="ghost"
          size="icon"
          className="h-7 w-7"
          onClick={onToggleExpanded}
          aria-label="Collapse chat"
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
                navigate(`/projects/${projectId}/command-center?agent=${task.agent_id}`)
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

      <DockChipsAndInput
        projectId={projectId}
        agent={agent}
        chipSurface={chipSurface}
        onAgentChange={onAgentChange}
        onSubmit={handleSubmit}
      />
    </aside>
  );
}

function DockChipsAndInput({
  projectId,
  agent,
  chipSurface,
  onAgentChange,
  onSubmit,
}: {
  projectId: number;
  agent: string;
  chipSurface: ChipSurface | null;
  onAgentChange: (agent: string) => void;
  onSubmit: (text: string, agent: string) => void;
}) {
  const { status: onboarding, skip, refresh } = useOnboarding(projectId);
  const [prefill, setPrefill] = useState<string>("");

  const showOnboardingChips =
    onboarding?.state === "pending" && agent === "strategist";

  async function handleSkip() {
    await skip();
    refresh();
  }

  return (
    <div className="relative border-t">
      {showOnboardingChips ? (
        <OnboardingChips
          onPrefill={(text) => setPrefill(text)}
          onSend={(text) => onSubmit(text, agent)}
          onSkip={handleSkip}
        />
      ) : chipSurface ? (
        <SurfaceSuggestionChips
          projectId={String(projectId)}
          surface={chipSurface}
          onSelect={(prompt) => onSubmit(prompt, agent)}
        />
      ) : null}
      <UniversalInput
        surface="stream"
        initialValue={prefill}
        onSubmit={(text, ag) => {
          onSubmit(text, ag);
          setPrefill("");
        }}
        currentAgent={agent}
        onAgentChange={onAgentChange}
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
                onClick={() => dispatchChatDockAgentSwitch(targetAgent)}
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
