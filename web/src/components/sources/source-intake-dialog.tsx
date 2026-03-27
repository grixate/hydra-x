import type { FormEvent } from "react";
import { useEffect, useState } from "react";
import { FileUp, LoaderCircle, NotebookPen } from "lucide-react";

import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Textarea } from "@/components/ui/textarea";

export function SourceIntakeDialog({
  open,
  onClose,
  onSubmit,
}: {
  open: boolean;
  onClose: () => void;
  onSubmit: (payload: {
    title: string;
    sourceType: string;
    content?: string;
    file?: File | null;
  }) => Promise<void>;
}) {
  const [mode, setMode] = useState<"paste" | "upload">("paste");
  const [title, setTitle] = useState("");
  const [sourceType, setSourceType] = useState("markdown");
  const [content, setContent] = useState("");
  const [file, setFile] = useState<File | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!open) {
      return;
    }

    setMode("paste");
    setTitle("");
    setSourceType("markdown");
    setContent("");
    setFile(null);
    setError(null);
  }, [open]);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSubmitting(true);
    setError(null);

    try {
      await onSubmit({
        title: title.trim() || (file ? file.name : "Untitled source"),
        sourceType: mode === "upload" && file ? inferSourceType(file.name) : sourceType,
        content: mode === "paste" ? content.trim() : undefined,
        file: mode === "upload" ? file : null,
      });
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to ingest source");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={(next) => !next && onClose()}>
      <DialogContent className="max-w-2xl">
        <DialogHeader>
          <DialogTitle>Ingest source material</DialogTitle>
          <DialogDescription>
            Add notes or upload documents to feed the grounded product evidence graph.
          </DialogDescription>
        </DialogHeader>

        <form className="mt-6 space-y-5" onSubmit={handleSubmit}>
          <div className="space-y-2">
            <Label htmlFor="source-title">Title</Label>
            <Input
              id="source-title"
              value={title}
              onChange={(event) => setTitle(event.target.value)}
              placeholder="User interview synthesis"
            />
          </div>

          <Tabs value={mode} onValueChange={(value) => setMode(value as "paste" | "upload")}>
            <TabsList className="grid w-full grid-cols-2">
              <TabsTrigger value="paste">Paste notes</TabsTrigger>
              <TabsTrigger value="upload">Upload file</TabsTrigger>
            </TabsList>

            <TabsContent value="paste" className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="source-type">Source type</Label>
                <Input
                  id="source-type"
                  value={sourceType}
                  onChange={(event) => setSourceType(event.target.value)}
                  placeholder="markdown"
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="source-content">Content</Label>
                <Textarea
                  id="source-content"
                  value={content}
                  onChange={(event) => setContent(event.target.value)}
                  placeholder="Paste interview notes, debriefs, support logs, or synthesis markdown."
                  className="min-h-[18rem]"
                />
              </div>
            </TabsContent>

            <TabsContent value="upload" className="space-y-4">
              <label className="flex cursor-pointer flex-col gap-4 rounded-xl border border-dashed border-border bg-muted/40 p-6 transition hover:border-ring hover:bg-muted">
                <span className="inline-flex items-center gap-3 text-sm font-medium text-foreground">
                  <FileUp className="h-4 w-4" />
                  {file ? file.name : "Choose a markdown, text, json, or pdf file"}
                </span>
                <span className="text-sm text-muted-foreground">
                  The backend will parse, chunk, embed, and stream the source into the project corpus.
                </span>
                <input
                  className="hidden"
                  type="file"
                  onChange={(event) => setFile(event.target.files?.[0] ?? null)}
                />
              </label>
            </TabsContent>
          </Tabs>

          <div className="rounded-xl border border-border bg-muted/40 p-4">
            <div className="flex items-center gap-3">
              <NotebookPen className="h-4 w-4 text-muted-foreground" />
              <p className="text-sm text-muted-foreground">
                Every source becomes retrieval chunks that can later be cited inside chat, insights, and requirements.
              </p>
            </div>
          </div>

          {error ? <p className="text-sm text-destructive">{error}</p> : null}

          <div className="flex justify-end gap-3">
            <Button type="button" variant="outline" onClick={onClose}>
              Cancel
            </Button>
            <Button
              disabled={
                submitting ||
                (mode === "paste" ? !content.trim() : !file)
              }
            >
              {submitting ? <LoaderCircle className="h-4 w-4 animate-spin" /> : null}
              Ingest source
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}

function inferSourceType(filename: string) {
  const lower = filename.toLowerCase();

  if (lower.endsWith(".md")) {
    return "markdown";
  }

  if (lower.endsWith(".json")) {
    return "json";
  }

  if (lower.endsWith(".pdf")) {
    return "pdf";
  }

  return "text";
}
