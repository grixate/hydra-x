import { Compass, Link2 } from "lucide-react";
import { useMemo, useState } from "react";

import { ChunkPreviewDialog } from "@/components/sources/chunk-preview-dialog";
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from "@/components/ui/accordion";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Separator } from "@/components/ui/separator";
import type { Insight, Requirement, Source, SourceChunk } from "@/types";
import { formatDate } from "@/lib/utils";

export function SourceDetail({
  source,
  relatedInsights,
  relatedRequirements,
  onSelectInsight,
  onSelectRequirement,
}: {
  source: Source | null;
  relatedInsights: Insight[];
  relatedRequirements: Requirement[];
  onSelectInsight: (insightId: number) => void;
  onSelectRequirement: (requirementId: number) => void;
}) {
  const [selectedChunk, setSelectedChunk] = useState<SourceChunk | null>(null);

  if (!source) {
    return (
      <Card>
        <CardContent className="p-8">
          <p className="font-display text-3xl text-[var(--ink)]">Select a source</p>
          <p className="mt-3 text-sm text-[var(--ink-soft)]">
            Choose a source to inspect chunked evidence, processing state, and everything downstream that depends on it.
          </p>
        </CardContent>
      </Card>
    );
  }

  const chunkInsights = useMemo(() => {
    const map = new Map<number, Insight[]>();

    source.chunks?.forEach((chunk) => {
      map.set(
        chunk.id,
        relatedInsights.filter((insight) =>
          insight.evidence.some((evidence) => evidence.source_chunk_id === chunk.id),
        ),
      );
    });

    return map;
  }, [relatedInsights, source.chunks]);

  const chunkRequirements = useMemo(() => {
    const map = new Map<number, Requirement[]>();

    source.chunks?.forEach((chunk) => {
      const insightIds = new Set((chunkInsights.get(chunk.id) ?? []).map((insight) => insight.id));

      map.set(
        chunk.id,
        relatedRequirements.filter((requirement) =>
          requirement.insights.some((insight) => insightIds.has(insight.id)),
        ),
      );
    });

    return map;
  }, [chunkInsights, relatedRequirements, source.chunks]);

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader className="pb-4">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div className="flex flex-wrap items-center gap-2">
              <Badge variant="accent">{source.source_type}</Badge>
              <Badge variant={source.processing_status === "completed" ? "success" : "warning"}>
                {source.processing_status}
              </Badge>
            </div>
            <span className="text-xs text-[var(--ink-soft)]">
              {source.source_chunk_count} chunks · {formatDate(source.updated_at)}
            </span>
          </div>
          <CardTitle className="font-display text-4xl">{source.title}</CardTitle>
          <CardDescription>
            Trace this source into linked insights and requirements, or inspect the exact indexed chunks below.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="grid gap-4 lg:grid-cols-2">
            <div className="rounded-[1.4rem] border border-[var(--line)] bg-[var(--paper-strong)] p-4">
              <p className="text-[10px] font-bold uppercase tracking-[0.3em] text-[var(--ink-soft)]">
                Related insights
              </p>
              <div className="mt-3 space-y-3">
                {relatedInsights.length > 0 ? (
                  relatedInsights.map((insight) => (
                    <button
                      key={insight.id}
                      type="button"
                      onClick={() => onSelectInsight(insight.id)}
                      className="flex w-full items-start justify-between gap-3 rounded-xl bg-white/70 px-4 py-3 text-left transition hover:bg-white"
                    >
                      <div>
                        <p className="font-medium text-[var(--ink)]">{insight.title}</p>
                        <p className="mt-1 text-sm text-[var(--ink-soft)]">
                          {insight.evidence.length} evidence links
                        </p>
                      </div>
                      <Link2 className="mt-1 h-4 w-4 shrink-0 text-[var(--ink-soft)]" />
                    </button>
                  ))
                ) : (
                  <p className="text-sm text-[var(--ink-soft)]">
                    No insight has cited this source yet.
                  </p>
                )}
              </div>
            </div>

            <div className="rounded-[1.4rem] border border-[var(--line)] bg-[var(--paper-strong)] p-4">
              <p className="text-[10px] font-bold uppercase tracking-[0.3em] text-[var(--ink-soft)]">
                Related requirements
              </p>
              <div className="mt-3 space-y-3">
                {relatedRequirements.length > 0 ? (
                  relatedRequirements.map((requirement) => (
                    <button
                      key={requirement.id}
                      type="button"
                      onClick={() => onSelectRequirement(requirement.id)}
                      className="flex w-full items-start justify-between gap-3 rounded-xl bg-white/70 px-4 py-3 text-left transition hover:bg-white"
                    >
                      <div>
                        <p className="font-medium text-[var(--ink)]">{requirement.title}</p>
                        <p className="mt-1 text-sm text-[var(--ink-soft)]">
                          {requirement.grounded ? "Grounded requirement" : "Needs review"}
                        </p>
                      </div>
                      <Link2 className="mt-1 h-4 w-4 shrink-0 text-[var(--ink-soft)]" />
                    </button>
                  ))
                ) : (
                  <p className="text-sm text-[var(--ink-soft)]">
                    No requirement currently depends on this source.
                  </p>
                )}
              </div>
            </div>
          </div>

          <Separator className="my-6" />

          <div className="rounded-[1.4rem] border border-[var(--line)] bg-white/60 p-4">
            <p className="text-[10px] font-bold uppercase tracking-[0.3em] text-[var(--ink-soft)]">
              Raw source
            </p>
            <ScrollArea className="mt-4 h-[14rem] pr-4">
              <p className="whitespace-pre-wrap text-sm leading-8 text-[var(--ink-soft)]">
                {source.content}
              </p>
            </ScrollArea>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="pb-4">
          <CardTitle>Indexed chunks</CardTitle>
          <CardDescription>
            Inspect the exact retrieval units available to grounded chat and evidence-backed synthesis.
          </CardDescription>
        </CardHeader>
        <CardContent>
          {(source.chunks?.length ?? 0) > 0 ? (
            <Accordion type="single" collapsible className="w-full space-y-3">
              {source.chunks?.map((chunk) => (
                <AccordionItem
                  key={chunk.id}
                  value={String(chunk.id)}
                  className="rounded-[1.4rem] border border-[var(--line)] bg-[var(--paper-strong)] px-4"
                >
                  <AccordionTrigger className="hover:no-underline">
                    <div className="flex flex-col items-start text-left">
                      <span className="font-medium text-[var(--ink)]">Chunk {chunk.ordinal + 1}</span>
                      <span className="text-xs text-[var(--ink-soft)]">
                        {chunk.token_count} tokens
                      </span>
                    </div>
                  </AccordionTrigger>
                  <AccordionContent className="pb-4">
                    <p className="whitespace-pre-wrap text-sm leading-7 text-[var(--ink-soft)]">
                      {chunk.content}
                    </p>
                    <div className="mt-4 flex flex-wrap items-center gap-2">
                      <Badge variant="neutral">
                        {(chunkInsights.get(chunk.id) ?? []).length} insights
                      </Badge>
                      <Badge variant="neutral">
                        {(chunkRequirements.get(chunk.id) ?? []).length} requirements
                      </Badge>
                      <Button variant="outline" size="sm" onClick={() => setSelectedChunk(chunk)}>
                        Review chunk
                      </Button>
                    </div>
                  </AccordionContent>
                </AccordionItem>
              ))}
            </Accordion>
          ) : (
            <div className="rounded-[1.4rem] border border-dashed border-[var(--line)] bg-[var(--paper-strong)] p-6">
              <p className="inline-flex items-center gap-2 text-sm text-[var(--ink-soft)]">
                <Compass className="h-4 w-4" />
                Chunks will appear here when processing completes.
              </p>
            </div>
          )}
        </CardContent>
      </Card>

      <ChunkPreviewDialog
        open={Boolean(selectedChunk)}
        chunk={selectedChunk}
        sourceTitle={source.title}
        insights={selectedChunk ? chunkInsights.get(selectedChunk.id) ?? [] : []}
        requirements={selectedChunk ? chunkRequirements.get(selectedChunk.id) ?? [] : []}
        onClose={() => setSelectedChunk(null)}
        onSelectInsight={onSelectInsight}
        onSelectRequirement={onSelectRequirement}
      />
    </div>
  );
}
