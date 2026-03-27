import { LoaderCircle, Sparkles } from "lucide-react";

export function StreamingIndicator({
  preview,
}: {
  preview: string;
}) {
  if (!preview) {
    return null;
  }

  return (
    <div className="rounded-[1.5rem] border border-dashed border-[var(--line)] bg-white/65 p-4">
      <p className="inline-flex items-center gap-2 text-[10px] font-bold uppercase tracking-[0.3em] text-[var(--ink-soft)]">
        <LoaderCircle className="h-3.5 w-3.5 animate-spin" />
        Streaming
      </p>
      <p className="mt-3 text-sm leading-7 text-[var(--ink)]">{preview}</p>
      <p className="mt-3 inline-flex items-center gap-2 text-xs text-[var(--ink-soft)]">
        <Sparkles className="h-3.5 w-3.5" />
        Grounded response is still being composed.
      </p>
    </div>
  );
}
