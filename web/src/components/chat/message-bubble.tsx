import type { Citation, ProductMessage } from "@/types";

import { CitationBadge } from "@/components/chat/citation-badge";
import { CitationFootnotes } from "@/components/chat/citation-footnotes";
import { parseContentWithCites } from "@/components/chat/cite-parser";
import { useGraphChatContext } from "@/components/chat/graph-chat-context";
import { cn, formatDate } from "@/lib/utils";

export function MessageBubble({
  message,
  onRevealCitation,
}: {
  message: ProductMessage;
  onRevealCitation: (citation: Citation) => void;
}) {
  const assistant = message.role === "assistant";

  // Library spec §6.3 — parse inline `<cite node_type=... node_id=...>` cites
  // out of the message body and render them as clickable graph-focus badges.
  const { parts, citations: nodeCitations } = parseContentWithCites(message.content);
  const graphChat = useGraphChatContext();

  // Merge backend-provided chunk citations + parser-extracted node citations
  // for the footnotes row. Backend chunks first, then node cites; deduped by
  // identity.
  const allCitations: Citation[] = [...message.citations, ...nodeCitations];

  const handleCiteClick = (citation: Citation) => {
    if (citation.node_type && citation.node_id != null) {
      // Library spec §6.2 — clicking an inline cite focuses + highlights the
      // cited node on the graph.
      const graphId = `${citation.node_type}-${citation.node_id}`;
      graphChat?.onGraphCommand?.({ type: "focus", nodeId: graphId });
      graphChat?.onGraphCommand?.({ type: "highlight", nodeIds: [graphId] });
    }
    onRevealCitation(citation);
  };

  return (
    <article className={cn("flex", assistant ? "justify-start" : "justify-end")}>
      <div
        className={cn(
          "max-w-3xl rounded-[1.7rem] px-5 py-4 shadow-[0_16px_40px_rgba(26,20,16,0.08)]",
          assistant
            ? "bg-white text-foreground"
            : "bg-foreground text-background",
        )}
      >
        <div className="mb-3 flex items-center justify-between gap-6 text-[10px] font-bold uppercase tracking-[0.24em]">
          <span>{assistant ? "Hydra agent" : "Operator"}</span>
          <span className={assistant ? "text-muted-foreground" : "text-white/60"}>
            {formatDate(message.inserted_at)}
          </span>
        </div>
        <p className="whitespace-pre-wrap text-sm leading-7">
          {parts.length > 0
            ? parts.map((part, idx) =>
                part.kind === "text" ? (
                  <span key={`t-${idx}`}>{part.text}</span>
                ) : (
                  <CitationBadge
                    key={`c-${idx}`}
                    index={part.index}
                    onClick={() => handleCiteClick(part.citation)}
                  />
                ),
              )
            : message.content}
          {message.citations.map((citation, index) => (
            <CitationBadge
              key={`${message.id}-${citation.source_chunk_id ?? index}`}
              index={index + 1 + nodeCitations.length}
              onClick={() => handleCiteClick(citation)}
            />
          ))}
        </p>
        {assistant ? (
          <CitationFootnotes citations={allCitations} onReveal={handleCiteClick} />
        ) : null}
      </div>
    </article>
  );
}
