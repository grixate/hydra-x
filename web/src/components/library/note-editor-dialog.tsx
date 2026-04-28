import { useState } from "react";
import { Loader2, NotebookPen } from "lucide-react";

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

// Library spec §10 — note creation: a markdown editor that saves a
// `kind: "note"` source, putting it through the same preprocessing
// pipeline as uploaded documents.

export function NoteEditorDialog({
  projectId,
  onCreated,
  triggerLabel = "New note",
}: {
  projectId: number;
  onCreated?: () => void;
  triggerLabel?: string;
}) {
  const [open, setOpen] = useState(false);
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [busy, setBusy] = useState(false);

  const reset = () => {
    setTitle("");
    setBody("");
  };

  const submit = async () => {
    const t = title.trim();
    const b = body.trim();
    if (!t || !b) return;
    setBusy(true);
    try {
      await api.addLibrarySource(projectId, {
        title: t,
        kind: "note",
        content: b,
        ingestion_status: "pending",
      });
      reset();
      setOpen(false);
      onCreated?.();
    } catch {
      // surfaced via source detail per spec §4.3
    } finally {
      setBusy(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button size="xs" variant="outline" className="gap-1">
          <NotebookPen className="h-3 w-3" />
          {triggerLabel}
        </Button>
      </DialogTrigger>
      <DialogContent className="max-w-2xl">
        <DialogHeader>
          <DialogTitle>New note</DialogTitle>
        </DialogHeader>
        <div className="space-y-3">
          <Input
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="Note title"
            className="text-sm"
            disabled={busy}
          />
          <textarea
            value={body}
            onChange={(e) => setBody(e.target.value)}
            placeholder="Write your note in markdown — it will be ingested into the Library and topics will be extracted."
            className="min-h-[280px] w-full resize-y rounded-md border bg-background p-3 font-mono text-xs leading-relaxed focus:outline-none focus:ring-1 focus:ring-ring"
            disabled={busy}
          />
        </div>
        <DialogFooter>
          <Button variant="outline" size="sm" onClick={() => setOpen(false)} disabled={busy}>
            Cancel
          </Button>
          <Button size="sm" onClick={submit} disabled={busy || !title.trim() || !body.trim()}>
            {busy ? <Loader2 className="h-3 w-3 animate-spin" /> : null}
            Save note
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
