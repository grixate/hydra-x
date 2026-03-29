import type { Citation, ProductMessage } from "@/types";

import { CitationBadge } from "@/components/chat/citation-badge";
import { CitationFootnotes } from "@/components/chat/citation-footnotes";
import { cn, formatDate } from "@/lib/utils";

export function MessageBubble({
  message,
  onRevealCitation,
}: {
  message: ProductMessage;
  onRevealCitation: (citation: Citation) => void;
}) {
  const assistant = message.role === "assistant";

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
          {message.content}
          {message.citations.map((citation, index) => (
            <CitationBadge
              key={`${message.id}-${citation.source_chunk_id ?? index}`}
              index={index + 1}
              onClick={() => onRevealCitation(citation)}
            />
          ))}
        </p>
        {assistant ? (
          <CitationFootnotes citations={message.citations} onReveal={onRevealCitation} />
        ) : null}
      </div>
    </article>
  );
}
