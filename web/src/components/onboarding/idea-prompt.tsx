import { useState } from "react";
import { Lightbulb, ArrowRight } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";

export function IdeaPrompt({
  projectName,
  onSubmit,
  onBack,
}: {
  projectName: string;
  onSubmit: (text: string) => void | Promise<void>;
  onBack: () => void;
}) {
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);

  async function handleSend() {
    const trimmed = text.trim();
    if (!trimmed || busy) return;
    setBusy(true);
    try {
      await onSubmit(trimmed);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex flex-col bg-background text-foreground">
      <header className="flex items-center justify-between px-6 py-4">
        <p className="text-[11px] font-medium uppercase tracking-[0.2em] text-muted-foreground">
          {projectName}
        </p>
        <Button
          size="sm"
          variant="ghost"
          onClick={onBack}
          disabled={busy}
          className="text-xs text-muted-foreground"
        >
          Back
        </Button>
      </header>

      <div className="flex flex-1 items-center justify-center px-6 pb-12">
        <div className="w-full max-w-2xl">
          <div className="mb-8 text-center">
            <div className="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-full bg-primary/10 text-primary">
              <Lightbulb className="h-5 w-5" />
            </div>
            <h1 className="text-2xl font-semibold tracking-tight">
              What are you trying to figure out?
            </h1>
            <p className="mt-2 text-sm text-muted-foreground">
              Be as rough as you like — a sentence is fine, a paragraph is great.
            </p>
          </div>

          <Textarea
            value={text}
            onChange={(e) => setText(e.target.value)}
            placeholder="I'm exploring..."
            rows={8}
            disabled={busy}
            className="resize-none text-sm leading-relaxed"
            autoFocus
          />

          <div className="mt-6 flex justify-end">
            <Button onClick={handleSend} disabled={!text.trim() || busy} size="lg">
              {busy ? "Sending…" : "Continue"}
              <ArrowRight className="ml-2 h-4 w-4" />
            </Button>
          </div>
        </div>
      </div>
    </div>
  );
}
