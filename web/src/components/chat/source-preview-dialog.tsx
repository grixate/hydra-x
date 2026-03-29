import type { Citation } from "@/types";
import type { Insight, Requirement } from "@/types";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";

export function SourcePreviewDialog({
  citation,
  relatedInsights,
  relatedRequirements,
  onSelectSource,
  onSelectInsight,
  onSelectRequirement,
  onClose,
}: {
  citation: Citation | null;
  relatedInsights: Insight[];
  relatedRequirements: Requirement[];
  onSelectSource?: (sourceId: number) => void;
  onSelectInsight?: (insightId: number) => void;
  onSelectRequirement?: (requirementId: number) => void;
  onClose: () => void;
}) {
  return (
    <Dialog open={Boolean(citation)} onOpenChange={(open) => !open && onClose()}>
      <DialogContent className="max-w-3xl">
        <DialogHeader>
          <div className="flex flex-wrap items-center gap-2">
            <Badge variant="accent">Source preview</Badge>
            {citation?.source_chunk ? (
              <Badge variant="neutral">Chunk {citation.source_chunk.ordinal + 1}</Badge>
            ) : null}
          </div>
          <DialogTitle>{citation?.source_chunk?.source_title ?? "Evidence chunk"}</DialogTitle>
          <DialogDescription>
            Inspect the exact passage attached to this grounded response.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-5">
          <div className="mt-6 rounded-[1.5rem] bg-white/65 p-5 text-sm leading-8 text-muted-foreground">
            {citation?.quote ?? citation?.source_chunk?.content ?? citation?.content}
          </div>

          <div className="grid gap-4 lg:grid-cols-3">
            <Button
              variant="outline"
              disabled={!citation?.source_chunk?.source_id}
              onClick={() => {
                if (citation?.source_chunk?.source_id) {
                  onClose();
                  onSelectSource?.(citation.source_chunk.source_id);
                }
              }}
            >
              Open source
            </Button>
            <Button
              variant="outline"
              disabled={relatedInsights.length === 0}
              onClick={() => {
                if (relatedInsights[0]) {
                  onClose();
                  onSelectInsight?.(relatedInsights[0].id);
                }
              }}
            >
              Open linked insight
            </Button>
            <Button
              variant="outline"
              disabled={relatedRequirements.length === 0}
              onClick={() => {
                if (relatedRequirements[0]) {
                  onClose();
                  onSelectRequirement?.(relatedRequirements[0].id);
                }
              }}
            >
              Open requirement
            </Button>
          </div>

          <div className="grid gap-4 lg:grid-cols-2">
            <div className="rounded-xl border border-border bg-muted/40 p-4">
              <div className="flex items-center justify-between">
                <p className="text-sm font-semibold text-foreground">Linked insights</p>
                <Badge variant="neutral">{relatedInsights.length}</Badge>
              </div>
              <div className="mt-3 space-y-2">
                {relatedInsights.length > 0 ? (
                  relatedInsights.map((insight) => (
                    <button
                      key={insight.id}
                      type="button"
                      onClick={() => {
                        onClose();
                        onSelectInsight?.(insight.id);
                      }}
                      className="w-full rounded-lg bg-white/80 px-3 py-3 text-left transition hover:bg-white"
                    >
                      <p className="font-medium text-foreground">{insight.title}</p>
                      <p className="mt-1 line-clamp-2 text-sm text-muted-foreground">{insight.body}</p>
                    </button>
                  ))
                ) : (
                  <p className="text-sm text-muted-foreground">No saved insights cite this evidence yet.</p>
                )}
              </div>
            </div>

            <div className="rounded-xl border border-border bg-muted/40 p-4">
              <div className="flex items-center justify-between">
                <p className="text-sm font-semibold text-foreground">Downstream requirements</p>
                <Badge variant="neutral">{relatedRequirements.length}</Badge>
              </div>
              <div className="mt-3 space-y-2">
                {relatedRequirements.length > 0 ? (
                  relatedRequirements.map((requirement) => (
                    <button
                      key={requirement.id}
                      type="button"
                      onClick={() => {
                        onClose();
                        onSelectRequirement?.(requirement.id);
                      }}
                      className="w-full rounded-lg bg-white/80 px-3 py-3 text-left transition hover:bg-white"
                    >
                      <p className="font-medium text-foreground">{requirement.title}</p>
                      <p className="mt-1 line-clamp-2 text-sm text-muted-foreground">
                        {requirement.body}
                      </p>
                    </button>
                  ))
                ) : (
                  <p className="text-sm text-muted-foreground">
                    No requirements currently trace back to this citation.
                  </p>
                )}
              </div>
            </div>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
