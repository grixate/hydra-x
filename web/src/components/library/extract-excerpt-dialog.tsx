import { useState } from "react";
import { Loader2, Quote } from "lucide-react";

import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { api } from "@/lib/api";

// Library spec §10 — excerpt extraction. From a source's evidence card,
// the user can select a passage and create a first-class `excerpt` node.
// V1 takes the passage text via paste; rich highlighting on PDFs is V1.1.

export function ExtractExcerptDialog({
  projectId,
  sourceId,
  onCreated,
  triggerLabel = "Extract excerpt",
}: {
  projectId: number;
  sourceId: number;
  onCreated?: (excerptId: number) => void;
  triggerLabel?: string;
}) {
  const [open, setOpen] = useState(false);
  const [passage, setPassage] = useState("");
  const [page, setPage] = useState("");
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);

  const reset = () => {
    setPassage("");
    setPage("");
    setNote("");
  };

  const submit = async () => {
    const text = passage.trim();
    if (!text) return;
    setBusy(true);
    try {
      const result = await api.createExcerpt(projectId, sourceId, {
        passage_text: text,
        position_anchor: page ? { page } : {},
        extraction_note: note.trim() || undefined,
        extracted_by: "user",
      });
      reset();
      setOpen(false);
      onCreated?.(result.id);
    } catch {
      // surfaced via source detail
    } finally {
      setBusy(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button size="xs" variant="outline" className="gap-1">
          <Quote className="h-3 w-3" />
          {triggerLabel}
        </Button>
      </DialogTrigger>
      <DialogContent className="max-w-2xl">
        <DialogHeader>
          <DialogTitle>Extract excerpt</DialogTitle>
        </DialogHeader>
        <div className="space-y-3">
          <textarea
            value={passage}
            onChange={(e) => setPassage(e.target.value)}
            placeholder="Paste the passage you want to extract."
            className="min-h-[180px] w-full resize-y rounded-md border bg-background p-3 text-sm leading-relaxed focus:outline-none focus:ring-1 focus:ring-ring"
            disabled={busy}
          />
          <div className="grid grid-cols-3 gap-2">
            <Input
              value={page}
              onChange={(e) => setPage(e.target.value)}
              placeholder="Page or section"
              className="col-span-1 text-xs"
              disabled={busy}
            />
            <Input
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder="Why does this matter? (optional)"
              className="col-span-2 text-xs"
              disabled={busy}
            />
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" size="sm" onClick={() => setOpen(false)} disabled={busy}>
            Cancel
          </Button>
          <Button size="sm" onClick={submit} disabled={busy || !passage.trim()}>
            {busy ? <Loader2 className="h-3 w-3 animate-spin" /> : null}
            Save excerpt
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
