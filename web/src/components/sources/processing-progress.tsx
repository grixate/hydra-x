import { Activity, AlertTriangle, Sparkles } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import type { SourceProgress } from "@/types";

export function ProcessingProgress({ progress }: { progress?: SourceProgress | null }) {
  if (!progress) {
    return null;
  }

  return (
    <Card>
      <CardContent className="p-4">
      <div className="flex items-start gap-3">
        <div className="mt-1 rounded-full bg-[var(--accent-faint)] p-2 text-foreground">
          {progress.status === "failed" ? (
            <AlertTriangle className="h-4 w-4" />
          ) : progress.status === "completed" ? (
            <Sparkles className="h-4 w-4" />
          ) : (
            <Activity className="h-4 w-4 animate-pulse" />
          )}
        </div>
        <div className="space-y-2">
          <div className="flex items-center gap-2">
            <Badge variant={progress.status === "failed" ? "danger" : "accent"}>
              {progress.status}
            </Badge>
            {progress.stage ? <span className="text-xs text-muted-foreground">{progress.stage}</span> : null}
            {progress.chunk_count ? (
              <span className="text-xs text-muted-foreground">{progress.chunk_count} chunks</span>
            ) : null}
          </div>
          <p className="text-sm text-muted-foreground">
            {progress.error ??
              (progress.status === "completed"
                ? "Source indexing finished and the research corpus is ready for retrieval."
                : "Processing is flowing through the ingestion pipeline and will update live.")}
          </p>
        </div>
      </div>
      </CardContent>
    </Card>
  );
}
