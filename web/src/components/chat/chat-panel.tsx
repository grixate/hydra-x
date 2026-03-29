import type { FormEvent } from "react";
import { useState } from "react";
import { LoaderCircle, Plus } from "lucide-react";

import { AgentSelector } from "@/components/chat/agent-selector";
import { MessageBubble } from "@/components/chat/message-bubble";
import { SourcePreviewDialog } from "@/components/chat/source-preview-dialog";
import { StreamingIndicator } from "@/components/chat/streaming-indicator";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Separator } from "@/components/ui/separator";
import { Textarea } from "@/components/ui/textarea";
import type { Citation, ProductConversation } from "@/types";
import { cn, relativeLabel } from "@/lib/utils";

export function ChatPanel({
  conversations,
  selectedConversationId,
  onSelectConversation,
  onOpenConversationDialog,
  activeConversation,
  onSendMessage,
  streamPreview,
  persona,
  onChangePersona,
}: {
  conversations: ProductConversation[];
  selectedConversationId: number | null;
  onSelectConversation: (conversationId: number) => void;
  onOpenConversationDialog: () => void;
  activeConversation: ProductConversation | null;
  onSendMessage: (content: string) => Promise<void>;
  streamPreview: string;
  persona: "researcher" | "strategist";
  onChangePersona: (persona: "researcher" | "strategist") => void;
}) {
  const [draft, setDraft] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [revealedCitation, setRevealedCitation] = useState<Citation | null>(null);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!draft.trim()) {
      return;
    }

    setSubmitting(true);

    try {
      await onSendMessage(draft.trim());
      setDraft("");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <>
      <div className="grid gap-6 xl:grid-cols-[340px_minmax(0,1fr)]">
        <Card>
          <CardHeader className="pb-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-[10px] font-bold uppercase tracking-[0.3em] text-muted-foreground">
                  Conversations
                </p>
                <CardTitle className="mt-2">Grounded chat</CardTitle>
                <CardDescription>
                  Stream answers from Hydra agents with source-linked citations.
                </CardDescription>
              </div>
              <Button variant="secondary" size="sm" onClick={onOpenConversationDialog}>
                <Plus className="h-4 w-4" />
                New
              </Button>
            </div>
          </CardHeader>

          <CardContent className="space-y-5">
            <AgentSelector value={persona} onChange={onChangePersona} />

            <Separator />

            <ScrollArea className="h-[33rem] pr-2">
              <div className="space-y-3">
                {conversations.map((conversation) => (
                  <button
                    key={conversation.id}
                    type="button"
                    onClick={() => onSelectConversation(conversation.id)}
                    className={cn(
                      "w-full rounded-[1.4rem] border p-4 text-left transition",
                      selectedConversationId === conversation.id
                        ? "border-foreground bg-foreground text-background"
                        : "border-border bg-white/60 hover:border-primary hover:bg-white",
                    )}
                  >
                    <div className="flex items-center justify-between gap-3">
                      <p className="font-semibold">
                        {conversation.title || "Untitled conversation"}
                      </p>
                      <Badge
                        variant={selectedConversationId === conversation.id ? "accent" : "neutral"}
                      >
                        {conversation.persona}
                      </Badge>
                    </div>
                    <p
                      className={cn(
                        "mt-2 line-clamp-2 text-sm",
                        selectedConversationId === conversation.id
                          ? "text-white/70"
                          : "text-muted-foreground",
                      )}
                    >
                      {conversation.latest_message?.content ?? "No turns yet."}
                    </p>
                    <p
                      className={cn(
                        "mt-3 text-xs",
                        selectedConversationId === conversation.id
                          ? "text-white/60"
                          : "text-muted-foreground",
                      )}
                    >
                      {conversation.message_count} turns · {relativeLabel(conversation.updated_at)}
                    </p>
                  </button>
                ))}
              </div>
            </ScrollArea>
          </CardContent>
        </Card>

        <Card className="flex min-h-[44rem] flex-col overflow-hidden">
          <CardHeader className="border-b border-border pb-5">
            <div className="flex flex-wrap items-center justify-between gap-4">
              <div>
                <p className="text-[10px] font-bold uppercase tracking-[0.3em] text-muted-foreground">
                  Active thread
                </p>
                <CardTitle className="mt-2 text-3xl">
                  {activeConversation?.title || "Create a conversation"}
                </CardTitle>
              </div>
              {activeConversation?.channel_state ? (
                <div className="flex flex-wrap items-center gap-2">
                  <Badge variant="neutral">
                    {activeConversation.channel_state.status ?? "idle"}
                  </Badge>
                  {activeConversation.channel_state.provider ? (
                    <Badge variant="accent">
                      {activeConversation.channel_state.provider}
                    </Badge>
                  ) : null}
                </div>
              ) : null}
            </div>
          </CardHeader>

          <CardContent className="flex min-h-0 flex-1 flex-col pt-6">
            <ScrollArea className="min-h-0 flex-1 pr-4">
              <div className="space-y-4">
                {activeConversation?.messages?.length ? (
                  activeConversation.messages.map((message) => (
                    <MessageBubble
                      key={message.id}
                      message={message}
                      onRevealCitation={setRevealedCitation}
                    />
                  ))
                ) : (
                  <div className="rounded-[1.8rem] border border-dashed border-border bg-[var(--paper-strong)] p-8 text-center">
                    <p className="text-3xl text-foreground">
                      Open a line of inquiry
                    </p>
                    <p className="mt-3 text-sm text-muted-foreground">
                      Ask the researcher for grounded synthesis or the strategist for traceable requirement framing.
                    </p>
                  </div>
                )}

                <StreamingIndicator preview={streamPreview} />
              </div>
            </ScrollArea>

            <Separator className="my-6" />

            <form onSubmit={handleSubmit}>
              <Textarea
                value={draft}
                onChange={(event) => setDraft(event.target.value)}
                placeholder="Ask for a synthesis, request new requirements, or interrogate the evidence graph."
              />
              <div className="mt-4 flex items-center justify-between gap-4">
                <p className="text-sm text-muted-foreground">
                  Product-mode conversations automatically route through the grounded tool path.
                </p>
                <Button disabled={!activeConversation || submitting || !draft.trim()}>
                  {submitting ? <LoaderCircle className="h-4 w-4 animate-spin" /> : null}
                  Send
                </Button>
              </div>
            </form>
          </CardContent>
        </Card>
      </div>

      <SourcePreviewDialog citation={revealedCitation} onClose={() => setRevealedCitation(null)} />
    </>
  );
}
