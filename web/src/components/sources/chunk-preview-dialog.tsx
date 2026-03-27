import { Link2 } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import type { Requirement, SourceChunk, Insight } from "@/types";

export function ChunkPreviewDialog({
  open,
  chunk,
  sourceTitle,
  insights,
  requirements,
  onClose,
  onSelectInsight,
  onSelectRequirement,
}: {
  open: boolean;
  chunk: SourceChunk | null;
  sourceTitle: string;
  insights: Insight[];
  requirements: Requirement[];
  onClose: () => void;
  onSelectInsight: (insightId: number) => void;
  onSelectRequirement: (requirementId: number) => void;
}) {
  return (
    <Dialog open={open} onOpenChange={(next) => !next && onClose()}>
      <DialogContent className="max-w-3xl">
        <DialogHeader>
          <div className="flex flex-wrap items-center gap-2">
            <Badge variant="accent">{sourceTitle}</Badge>
            {chunk ? <Badge variant="neutral">Chunk {chunk.ordinal + 1}</Badge> : null}
            {chunk ? <Badge variant="neutral">{chunk.token_count} tokens</Badge> : null}
          </div>
          <DialogTitle>Indexed evidence unit</DialogTitle>
          <DialogDescription>
            Review the exact retrieval chunk and follow everything downstream that cites it.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-5">
          <div className="rounded-xl border border-border bg-muted/40 p-5">
            <p className="whitespace-pre-wrap text-sm leading-7 text-muted-foreground">
              {chunk?.content}
            </p>
          </div>

          <div className="grid gap-4 lg:grid-cols-2">
            <div className="rounded-xl border border-border bg-card p-4">
              <p className="text-[10px] font-bold uppercase tracking-[0.3em] text-muted-foreground">
                Linked insights
              </p>
              <div className="mt-3 space-y-3">
                {insights.length > 0 ? (
                  insights.map((insight) => (
                    <Button
                      key={insight.id}
                      variant="outline"
                      className="h-auto w-full justify-between px-4 py-3 text-left"
                      onClick={() => {
                        onClose();
                        onSelectInsight(insight.id);
                      }}
                    >
                      <span>
                        <span className="block font-medium text-foreground">{insight.title}</span>
                        <span className="mt-1 block text-xs text-muted-foreground">{insight.status}</span>
                      </span>
                      <Link2 className="h-4 w-4 shrink-0 text-muted-foreground" />
                    </Button>
                  ))
                ) : (
                  <p className="text-sm text-muted-foreground">No insights cite this chunk yet.</p>
                )}
              </div>
            </div>

            <div className="rounded-xl border border-border bg-card p-4">
              <p className="text-[10px] font-bold uppercase tracking-[0.3em] text-muted-foreground">
                Downstream requirements
              </p>
              <div className="mt-3 space-y-3">
                {requirements.length > 0 ? (
                  requirements.map((requirement) => (
                    <Button
                      key={requirement.id}
                      variant="outline"
                      className="h-auto w-full justify-between px-4 py-3 text-left"
                      onClick={() => {
                        onClose();
                        onSelectRequirement(requirement.id);
                      }}
                    >
                      <span>
                        <span className="block font-medium text-foreground">{requirement.title}</span>
                        <span className="mt-1 block text-xs text-muted-foreground">
                          {requirement.grounded ? "grounded" : "needs review"}
                        </span>
                      </span>
                      <Link2 className="h-4 w-4 shrink-0 text-muted-foreground" />
                    </Button>
                  ))
                ) : (
                  <p className="text-sm text-muted-foreground">
                    No requirements currently depend on this chunk.
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
