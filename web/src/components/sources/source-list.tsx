import { ChevronRight, FileText } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { ScrollArea } from "@/components/ui/scroll-area";
import type { Source } from "@/types";
import { cn, formatDate } from "@/lib/utils";

export function SourceList({
  sources,
  selectedSourceId,
  onSelectSource,
}: {
  sources: Source[];
  selectedSourceId: number | null;
  onSelectSource: (sourceId: number) => void;
}) {
  return (
    <Card>
      <CardHeader className="pb-4">
        <div className="flex items-end justify-between">
          <div>
            <p className="text-[10px] font-bold uppercase tracking-[0.3em] text-muted-foreground">
              Corpus
            </p>
            <CardTitle className="mt-2">Indexed sources</CardTitle>
          </div>
          <Badge variant="neutral">{sources.length} total</Badge>
        </div>
      </CardHeader>

      <CardContent>
        <ScrollArea className="h-[28rem] pr-2">
          <div className="space-y-3">
            {sources.map((source) => (
              <button
                key={source.id}
                type="button"
                onClick={() => onSelectSource(source.id)}
                className={cn(
                  "flex w-full items-start gap-4 rounded-[1.5rem] border p-4 text-left transition",
                  selectedSourceId === source.id
                    ? "border-foreground bg-foreground text-background"
                    : "border-border bg-white/55 text-foreground hover:border-primary hover:bg-white",
                )}
              >
                <div
                  className={cn(
                    "rounded-[1.1rem] p-3",
                    selectedSourceId === source.id ? "bg-white/10" : "bg-[var(--paper-strong)]",
                  )}
                >
                  <FileText className="h-4 w-4" />
                </div>
                <div className="min-w-0 flex-1">
                  <div className="flex items-center justify-between gap-3">
                    <p className="truncate font-semibold">{source.title}</p>
                    <ChevronRight className="h-4 w-4 shrink-0" />
                  </div>
                  <div
                    className={cn(
                      "mt-2 flex flex-wrap items-center gap-2 text-xs",
                      selectedSourceId === source.id ? "text-white/70" : "text-muted-foreground",
                    )}
                  >
                    <Badge
                      variant={source.processing_status === "completed" ? "success" : "warning"}
                    >
                      {source.processing_status}
                    </Badge>
                    <span>{source.source_type}</span>
                    <span>{source.source_chunk_count} chunks</span>
                    <span>{formatDate(source.updated_at)}</span>
                  </div>
                  <p
                    className={cn(
                      "mt-3 line-clamp-2 text-sm",
                      selectedSourceId === source.id ? "text-white/85" : "text-muted-foreground",
                    )}
                  >
                    {source.content}
                  </p>
                </div>
              </button>
            ))}
          </div>
        </ScrollArea>
      </CardContent>
    </Card>
  );
}
