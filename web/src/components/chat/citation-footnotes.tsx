import type { Citation } from "@/types";

import { EvidenceLink } from "@/components/shared/evidence-link";

export function CitationFootnotes({
  citations,
  onReveal,
}: {
  citations: Citation[];
  onReveal?: (citation: Citation) => void;
}) {
  if (citations.length === 0) {
    return null;
  }

  return (
    <div className="mt-4 space-y-3 rounded-[1.3rem] bg-black/5 p-3">
      {citations.map((citation, index) => (
        <div key={`${citation.source_chunk_id ?? index}-${index}`} className="space-y-2 text-sm">
          <EvidenceLink label={`[${index + 1}] ${citation.source_chunk?.source_title ?? "Source"}`} onClick={() => onReveal?.(citation)} />
          <p className="text-muted-foreground">
            {citation.quote ?? citation.source_chunk?.content ?? citation.content}
          </p>
        </div>
      ))}
    </div>
  );
}
