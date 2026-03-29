import type { InsightEvidence } from "@/types";

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { EvidenceLink } from "@/components/shared/evidence-link";

export function EvidencePanel({
  evidence,
  onSelectSource,
}: {
  evidence: InsightEvidence[];
  onSelectSource?: (sourceId: number) => void;
}) {
  return (
    <Card>
      <CardHeader className="pb-4">
        <p className="text-[10px] font-bold uppercase tracking-[0.3em] text-muted-foreground">
          Evidence panel
        </p>
        <CardTitle>Notebook references</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        {evidence.map((item, index) => (
          <div key={`${item.source_chunk_id}-${index}`} className="rounded-[1.4rem] bg-[var(--paper-strong)] p-4">
            <EvidenceLink
              label={`[${index + 1}] ${item.source_chunk?.source_title ?? "Source"}`}
              onClick={
                item.source_chunk?.source_id && onSelectSource
                  ? () => onSelectSource(item.source_chunk!.source_id)
                  : undefined
              }
            />
            <p className="mt-3 text-sm leading-7 text-muted-foreground">{item.quote}</p>
          </div>
        ))}
      </CardContent>
    </Card>
  );
}
