import { Archive, ArchiveRestore, ArrowUpRight, Compass, Link2, RefreshCw, Sparkles } from "lucide-react";
import { useEffect, useMemo, useState } from "react";

import { ChunkPreviewDialog } from "@/components/sources/chunk-preview-dialog";
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from "@/components/ui/accordion";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Separator } from "@/components/ui/separator";
import type { Insight, Requirement, Source, SourceChunk, SourceReferenceSummary } from "@/types";
import { api } from "@/lib/api";
import { formatDate } from "@/lib/utils";

export function SourceDetail({
  source,
  relatedInsights,
  relatedRequirements,
  onSelectInsight,
  onSelectRequirement,
  onReanalyze,
  onPromoted,
  onDemoted,
  onArchived,
  onUnarchived,
}: {
  source: Source | null;
  relatedInsights: Insight[];
  relatedRequirements: Requirement[];
  onSelectInsight: (insightId: number) => void;
  onSelectRequirement: (requirementId: number) => void;
  onReanalyze?: (sourceId: number) => Promise<void> | void;
  onPromoted?: (source: Source) => void;
  onDemoted?: (source: Source) => void;
  onArchived?: (source: Source) => void;
  onUnarchived?: (source: Source) => void;
}) {
  const [selectedChunk, setSelectedChunk] = useState<SourceChunk | null>(null);
  const [reanalyzing, setReanalyzing] = useState(false);
  const [busy, setBusy] = useState(false);
  const [referencedBy, setReferencedBy] = useState<SourceReferenceSummary[]>([]);

  async function handleReanalyze() {
    if (!source || !onReanalyze || reanalyzing) return;
    setReanalyzing(true);
    try {
      await onReanalyze(source.id);
    } finally {
      setReanalyzing(false);
    }
  }

  // Source-as-Data §6: show "Referenced by" summary — which graph nodes cite
  // this source. Refetch whenever the selected source changes.
  useEffect(() => {
    if (!source) {
      setReferencedBy([]);
      return;
    }
    let cancelled = false;
    api
      .getLibraryReferencedBy(source.project_id, source.id)
      .then((summary) => {
        if (!cancelled) setReferencedBy(summary);
      })
      .catch(() => {
        if (!cancelled) setReferencedBy([]);
      });
    return () => {
      cancelled = true;
    };
  }, [source?.id, source?.project_id]);

  async function handlePromote() {
    if (!source || busy) return;
    setBusy(true);
    try {
      const updated = await api.promoteSource(source.project_id, source.id);
      onPromoted?.(updated);
    } finally {
      setBusy(false);
    }
  }

  async function handleDemote() {
    if (!source || busy) return;
    if (
      !confirm(
        "Demote this source from the graph? Existing graph edges will be replaced with source references on the connected nodes.",
      )
    ) {
      return;
    }
    setBusy(true);
    try {
      const updated = await api.demoteSource(source.project_id, source.id);
      onDemoted?.(updated);
    } finally {
      setBusy(false);
    }
  }

  async function handleArchive() {
    if (!source || busy) return;
    setBusy(true);
    try {
      const updated = source.archived_at
        ? await api.unarchiveSource(source.project_id, source.id)
        : await api.archiveSource(source.project_id, source.id);
      if (source.archived_at) onUnarchived?.(updated);
      else onArchived?.(updated);
    } finally {
      setBusy(false);
    }
  }

  if (!source) {
    return (
      <Card>
        <CardContent className="p-8">
          <p className="text-3xl text-foreground">Select a source</p>
          <p className="mt-3 text-sm text-muted-foreground">
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
            <div className="flex flex-wrap items-center gap-2">
              <span className="text-xs text-muted-foreground">
                {source.source_chunk_count} chunks · {formatDate(source.updated_at)}
              </span>
              {source.promoted_to_graph ? (
                <Button
                  variant="outline"
                  size="sm"
                  onClick={handleDemote}
                  disabled={busy}
                  title="Demote from graph — existing edges become source references"
                >
                  <ArrowUpRight className="mr-1.5 h-3.5 w-3.5 rotate-180" />
                  Demote from graph
                </Button>
              ) : (
                <Button
                  variant="outline"
                  size="sm"
                  onClick={handlePromote}
                  disabled={busy}
                  title="Promote to graph — for foundational or pivotal sources only"
                >
                  <Sparkles className="mr-1.5 h-3.5 w-3.5" />
                  Promote to graph
                </Button>
              )}
              <Button
                variant="outline"
                size="sm"
                onClick={handleArchive}
                disabled={busy}
                title={source.archived_at ? "Unarchive" : "Archive — stays queryable, de-emphasized"}
              >
                {source.archived_at ? (
                  <>
                    <ArchiveRestore className="mr-1.5 h-3.5 w-3.5" />
                    Unarchive
                  </>
                ) : (
                  <>
                    <Archive className="mr-1.5 h-3.5 w-3.5" />
                    Archive
                  </>
                )}
              </Button>
              {onReanalyze ? (
                <Button
                  variant="outline"
                  size="sm"
                  onClick={handleReanalyze}
                  disabled={reanalyzing}
                >
                  <RefreshCw
                    className={`mr-1.5 h-3.5 w-3.5 ${reanalyzing ? "animate-spin" : ""}`}
                  />
                  {reanalyzing ? "Re-analyzing…" : "Re-analyze"}
                </Button>
              ) : null}
            </div>
          </div>
          <div className="mt-2 flex flex-wrap gap-2">
            {source.promoted_to_graph && (
              <Badge variant="neutral" className="text-[10px]">
                visible in graph
              </Badge>
            )}
            {source.archived_at && (
              <Badge variant="neutral" className="text-[10px]">
                archived
              </Badge>
            )}
          </div>
          <CardTitle className="text-4xl">{source.title}</CardTitle>
          <CardDescription>
            Trace this source into linked insights and requirements, or inspect the exact indexed chunks below.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="grid gap-4 lg:grid-cols-2">
            <div className="rounded-[1.4rem] border border-border bg-[var(--paper-strong)] p-4">
              <p className="text-[10px] font-bold uppercase tracking-[0.3em] text-muted-foreground">
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
                        <p className="font-medium text-foreground">{insight.title}</p>
                        <p className="mt-1 text-sm text-muted-foreground">
                          {insight.evidence.length} evidence links
                        </p>
                      </div>
                      <Link2 className="mt-1 h-4 w-4 shrink-0 text-muted-foreground" />
                    </button>
                  ))
                ) : (
                  <p className="text-sm text-muted-foreground">
                    No insight has cited this source yet.
                  </p>
                )}
              </div>
            </div>

            <div className="rounded-[1.4rem] border border-border bg-[var(--paper-strong)] p-4">
              <p className="text-[10px] font-bold uppercase tracking-[0.3em] text-muted-foreground">
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
                        <p className="font-medium text-foreground">{requirement.title}</p>
                        <p className="mt-1 text-sm text-muted-foreground">
                          {requirement.grounded ? "Grounded requirement" : "Needs review"}
                        </p>
                      </div>
                      <Link2 className="mt-1 h-4 w-4 shrink-0 text-muted-foreground" />
                    </button>
                  ))
                ) : (
                  <p className="text-sm text-muted-foreground">
                    No requirement currently depends on this source.
                  </p>
                )}
              </div>
            </div>
          </div>

          {referencedBy.length > 0 && (
            <>
              <Separator className="my-6" />
              <div className="rounded-[1.4rem] border border-border bg-[var(--paper-strong)] p-4">
                <p className="text-[10px] font-bold uppercase tracking-[0.3em] text-muted-foreground">
                  Referenced by
                </p>
                <p className="mt-1 text-xs text-muted-foreground">
                  Graph nodes that cite this source via source references.
                </p>
                <div className="mt-3 flex flex-wrap gap-2">
                  {referencedBy.map((group) => (
                    <div
                      key={group.node_type}
                      className="rounded-xl border border-border bg-white/60 px-3 py-2"
                    >
                      <span className="text-[10px] font-semibold uppercase tracking-wide text-muted-foreground">
                        {group.node_type.replace(/_/g, " ")}
                      </span>
                      <span className="ml-2 text-sm font-semibold text-foreground">
                        {group.count}
                      </span>
                    </div>
                  ))}
                </div>
              </div>
            </>
          )}

          <Separator className="my-6" />

          <div className="rounded-[1.4rem] border border-border bg-white/60 p-4">
            <p className="text-[10px] font-bold uppercase tracking-[0.3em] text-muted-foreground">
              Raw source
            </p>
            <ScrollArea className="mt-4 h-[14rem] pr-4">
              <p className="whitespace-pre-wrap text-sm leading-8 text-muted-foreground">
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
                  className="rounded-[1.4rem] border border-border bg-[var(--paper-strong)] px-4"
                >
                  <AccordionTrigger className="hover:no-underline">
                    <div className="flex flex-col items-start text-left">
                      <span className="font-medium text-foreground">Chunk {chunk.ordinal + 1}</span>
                      <span className="text-xs text-muted-foreground">
                        {chunk.token_count} tokens
                      </span>
                    </div>
                  </AccordionTrigger>
                  <AccordionContent className="pb-4">
                    <p className="whitespace-pre-wrap text-sm leading-7 text-muted-foreground">
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
            <div className="rounded-[1.4rem] border border-dashed border-border bg-[var(--paper-strong)] p-6">
              <p className="inline-flex items-center gap-2 text-sm text-muted-foreground">
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
