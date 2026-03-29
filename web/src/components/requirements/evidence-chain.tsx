import type { Requirement } from "@/types";

import { EvidenceLink } from "@/components/shared/evidence-link";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

export function EvidenceChain({
  requirement,
  onSelectInsight,
  onSelectSource,
}: {
  requirement: Requirement;
  onSelectInsight?: (insightId: number) => void;
  onSelectSource?: (sourceId: number) => void;
}) {
  return (
    <Card>
      <CardHeader className="pb-4">
        <p className="text-[10px] font-bold uppercase tracking-[0.3em] text-muted-foreground">
          Traceability chain
        </p>
        <CardTitle>Source → insight → requirement</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        {requirement.insights.map((insight) => (
          <div key={insight.id} className="rounded-[1.5rem] bg-[var(--paper-strong)] p-4">
            <button
              type="button"
              onClick={() => onSelectInsight?.(insight.id)}
              className="text-left"
            >
              <p className="font-semibold text-foreground">{insight.title}</p>
            </button>
            <p className="mt-2 text-sm text-muted-foreground">{insight.body}</p>
            <div className="mt-4 space-y-3 border-l border-border pl-4">
              {insight.evidence.map((evidence, index) => (
                <div key={`${evidence.source_chunk_id}-${index}`} className="text-sm text-muted-foreground">
                  <EvidenceLink
                    label={evidence.source_chunk?.source_title ?? "Source chunk"}
                    onClick={
                      evidence.source_chunk?.source_id && onSelectSource
                        ? () => onSelectSource(evidence.source_chunk!.source_id)
                        : undefined
                    }
                  />
                  <p className="mt-1 leading-7">{evidence.quote}</p>
                </div>
              ))}
            </div>
          </div>
        ))}
      </CardContent>
    </Card>
  );
}
