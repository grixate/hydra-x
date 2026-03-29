import { Link2, MessagesSquare, Telescope } from "lucide-react";
import { useMemo } from "react";

import { EvidenceLink } from "@/components/shared/evidence-link";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { ScrollArea } from "@/components/ui/scroll-area";
import type { Insight, ProductConversation, Requirement } from "@/types";

export function ConversationGroundingRail({
  conversation,
  insights,
  requirements,
  onSelectSource,
  onSelectInsight,
  onSelectRequirement,
}: {
  conversation: ProductConversation | null;
  insights: Insight[];
  requirements: Requirement[];
  onSelectSource: (sourceId: number) => void;
  onSelectInsight: (insightId: number) => void;
  onSelectRequirement: (requirementId: number) => void;
}) {
  const citedSources = useMemo(() => {
    const seen = new Map<
      number,
      {
        sourceId: number;
        sourceTitle: string;
        chunkIds: Set<number>;
        citationCount: number;
      }
    >();

    conversation?.messages?.forEach((message) => {
      message.citations.forEach((citation) => {
        const sourceId = citation.source_chunk?.source_id;
        if (!sourceId) {
          return;
        }

        const entry = seen.get(sourceId) ?? {
          sourceId,
          sourceTitle: citation.source_chunk?.source_title ?? "Source",
          chunkIds: new Set<number>(),
          citationCount: 0,
        };

        if (citation.source_chunk_id) {
          entry.chunkIds.add(citation.source_chunk_id);
        }

        entry.citationCount += 1;
        seen.set(sourceId, entry);
      });
    });

    return Array.from(seen.values());
  }, [conversation]);

  const linkedInsightIds = useMemo(() => {
    const chunkIds = new Set<number>();
    citedSources.forEach((source) => {
      source.chunkIds.forEach((chunkId) => chunkIds.add(chunkId));
    });

    return new Set(
      insights
        .filter((insight) => insight.evidence.some((evidence) => chunkIds.has(evidence.source_chunk_id)))
        .map((insight) => insight.id),
    );
  }, [citedSources, insights]);

  const linkedInsights = insights.filter((insight) => linkedInsightIds.has(insight.id));
  const linkedRequirements = requirements.filter((requirement) =>
    requirement.insights.some((insight) => linkedInsightIds.has(insight.id)),
  );

  return (
    <Card className="flex min-h-[44rem] flex-col">
      <CardHeader className="pb-4">
        <p className="text-[10px] font-bold uppercase tracking-[0.3em] text-muted-foreground">
          Grounding rail
        </p>
        <CardTitle>Evidence in this thread</CardTitle>
      </CardHeader>

      <CardContent className="min-h-0 flex-1">
        {conversation ? (
          <ScrollArea className="h-[38rem] pr-2">
            <div className="space-y-6">
              <section className="space-y-3">
                <div className="flex items-center justify-between">
                  <p className="text-sm font-semibold text-foreground">Cited sources</p>
                  <Badge variant="neutral">{citedSources.length}</Badge>
                </div>
                {citedSources.length > 0 ? (
                  citedSources.map((source) => (
                    <div key={source.sourceId} className="rounded-[1.2rem] border border-border bg-[var(--paper-strong)] p-4">
                      <EvidenceLink label={source.sourceTitle} onClick={() => onSelectSource(source.sourceId)} />
                      <div className="mt-3 flex flex-wrap gap-2">
                        <Badge variant="accent">{source.citationCount} citations</Badge>
                        <Badge variant="neutral">{source.chunkIds.size} chunks</Badge>
                      </div>
                    </div>
                  ))
                ) : (
                  <EmptyRail
                    icon={<Link2 className="h-4 w-4" />}
                    text="Citations will accumulate here as the conversation grounds itself in sources."
                  />
                )}
              </section>

              <section className="space-y-3">
                <div className="flex items-center justify-between">
                  <p className="text-sm font-semibold text-foreground">Linked insights</p>
                  <Badge variant="neutral">{linkedInsights.length}</Badge>
                </div>
                {linkedInsights.length > 0 ? (
                  linkedInsights.map((insight) => (
                    <button
                      key={insight.id}
                      type="button"
                      onClick={() => onSelectInsight(insight.id)}
                      className="w-full rounded-[1.2rem] border border-border bg-white/70 p-4 text-left transition hover:bg-white"
                    >
                      <div className="flex items-center justify-between gap-3">
                        <p className="font-medium text-foreground">{insight.title}</p>
                        <Badge variant={insight.status === "accepted" ? "success" : "neutral"}>
                          {insight.status}
                        </Badge>
                      </div>
                      <p className="mt-2 line-clamp-2 text-sm text-muted-foreground">{insight.body}</p>
                    </button>
                  ))
                ) : (
                  <EmptyRail
                    icon={<Telescope className="h-4 w-4" />}
                    text="No saved insights are linked to the cited evidence yet."
                  />
                )}
              </section>

              <section className="space-y-3">
                <div className="flex items-center justify-between">
                  <p className="text-sm font-semibold text-foreground">Downstream requirements</p>
                  <Badge variant="neutral">{linkedRequirements.length}</Badge>
                </div>
                {linkedRequirements.length > 0 ? (
                  linkedRequirements.map((requirement) => (
                    <button
                      key={requirement.id}
                      type="button"
                      onClick={() => onSelectRequirement(requirement.id)}
                      className="w-full rounded-[1.2rem] border border-border bg-white/70 p-4 text-left transition hover:bg-white"
                    >
                      <div className="flex items-center justify-between gap-3">
                        <p className="font-medium text-foreground">{requirement.title}</p>
                        <Badge variant={requirement.grounded ? "success" : "warning"}>
                          {requirement.grounded ? "grounded" : "review"}
                        </Badge>
                      </div>
                      <p className="mt-2 line-clamp-2 text-sm text-muted-foreground">{requirement.body}</p>
                    </button>
                  ))
                ) : (
                  <EmptyRail
                    icon={<MessagesSquare className="h-4 w-4" />}
                    text="No requirements currently trace back to the evidence in this thread."
                  />
                )}
              </section>
            </div>
          </ScrollArea>
        ) : (
          <EmptyRail
            icon={<MessagesSquare className="h-4 w-4" />}
            text="Open a conversation to see the live grounding graph for that thread."
          />
        )}
      </CardContent>
    </Card>
  );
}

function EmptyRail({
  icon,
  text,
}: {
  icon: React.ReactNode;
  text: string;
}) {
  return (
    <div className="rounded-[1.2rem] border border-dashed border-border bg-[var(--paper-strong)] p-4 text-sm text-muted-foreground">
      <p className="inline-flex items-center gap-2">
        {icon}
        {text}
      </p>
    </div>
  );
}
