import type { FormEvent } from "react";
import { useEffect, useMemo, useState } from "react";

import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { Checkbox } from "@/components/ui/checkbox";
import { Badge } from "@/components/ui/badge";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import type { Insight, Source } from "@/types";

const statuses = ["draft", "accepted", "rejected"] as const;

export function InsightDialog({
  open,
  mode,
  insight,
  sources,
  onClose,
  onSubmit,
}: {
  open: boolean;
  mode: "create" | "edit";
  insight: Insight | null;
  sources: Source[];
  onClose: () => void;
  onSubmit: (payload: {
    title: string;
    body: string;
    status: string;
    evidenceChunkIds: number[];
  }) => Promise<void>;
}) {
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [status, setStatus] = useState<string>("draft");
  const [selectedChunkIds, setSelectedChunkIds] = useState<number[]>([]);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!open) {
      return;
    }

    setTitle(insight?.title ?? "");
    setBody(insight?.body ?? "");
    setStatus(insight?.status ?? "draft");
    setSelectedChunkIds(
      insight?.evidence.map((item) => item.source_chunk_id).filter(Boolean) as number[] ?? [],
    );
    setError(null);
  }, [insight, open]);

  const chunkOptions = useMemo(
    () =>
      sources.flatMap((source) =>
        (source.chunks ?? []).map((chunk) => ({
          id: chunk.id,
          label: source.title,
          content: chunk.content,
          ordinal: chunk.ordinal,
        })),
      ),
    [sources],
  );

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSubmitting(true);
    setError(null);

    try {
      await onSubmit({
        title: title.trim(),
        body: body.trim(),
        status,
        evidenceChunkIds: selectedChunkIds,
      });
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to save insight");
    } finally {
      setSubmitting(false);
    }
  }

  function toggleChunk(chunkId: number, checked: boolean) {
    setSelectedChunkIds((current) =>
      checked ? Array.from(new Set([...current, chunkId])) : current.filter((id) => id !== chunkId),
    );
  }

  return (
    <Dialog open={open} onOpenChange={(next) => !next && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{mode === "create" ? "Create insight" : "Edit insight"}</DialogTitle>
          <DialogDescription>
            Turn grounded source material into a reusable research finding with explicit evidence.
          </DialogDescription>
        </DialogHeader>

        <form className="mt-6 space-y-5" onSubmit={handleSubmit}>
          <div className="space-y-2">
            <Label htmlFor="insight-title">Title</Label>
            <Input
              id="insight-title"
              value={title}
              onChange={(event) => setTitle(event.target.value)}
              placeholder="Summarize the finding"
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor="insight-status">Status</Label>
            <Select value={status} onValueChange={setStatus}>
              <SelectTrigger id="insight-status">
                <SelectValue placeholder="Select status" />
              </SelectTrigger>
              <SelectContent>
                {statuses.map((item) => (
                  <SelectItem key={item} value={item}>
                    {item}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-2">
            <Label htmlFor="insight-body">Narrative</Label>
            <Textarea
              id="insight-body"
              value={body}
              onChange={(event) => setBody(event.target.value)}
              placeholder="Describe the pattern or user behavior this evidence supports."
            />
          </div>

          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <Label>Evidence chunks</Label>
              <Badge variant="accent">{selectedChunkIds.length} selected</Badge>
            </div>
            <ScrollArea className="h-[18rem] rounded-[1.4rem] border border-border bg-white/60 p-4">
              <div className="space-y-3">
                {chunkOptions.map((chunk) => {
                  const checked = selectedChunkIds.includes(chunk.id);

                  return (
                    <label
                      key={chunk.id}
                      className="flex items-start gap-3 rounded-[1.1rem] border border-border bg-[var(--paper-strong)] p-3"
                    >
                      <Checkbox
                        checked={checked}
                        onCheckedChange={(next) => toggleChunk(chunk.id, next === true)}
                      />
                      <div className="space-y-1">
                        <p className="text-sm font-semibold text-foreground">
                          {chunk.label}
                          <span className="ml-2 text-xs font-normal text-muted-foreground">
                            chunk {chunk.ordinal + 1}
                          </span>
                        </p>
                        <p className="line-clamp-3 text-sm text-muted-foreground">{chunk.content}</p>
                      </div>
                    </label>
                  );
                })}
              </div>
            </ScrollArea>
          </div>

          {error ? <p className="text-sm text-rose-700">{error}</p> : null}

          <div className="flex justify-end gap-3">
            <Button type="button" variant="secondary" onClick={onClose}>
              Cancel
            </Button>
            <Button disabled={submitting}>
              {submitting ? "Saving..." : mode === "create" ? "Create insight" : "Save insight"}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}
