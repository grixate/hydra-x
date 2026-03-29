import type { FormEvent } from "react";
import { useState } from "react";
import { FileUp, LoaderCircle, NotebookPen } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";

export function UploadZone({
  onSubmit,
}: {
  onSubmit: (payload: {
    title: string;
    sourceType: string;
    content?: string;
    file?: File | null;
  }) => Promise<void>;
}) {
  const [title, setTitle] = useState("");
  const [content, setContent] = useState("");
  const [file, setFile] = useState<File | null>(null);
  const [submitting, setSubmitting] = useState(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    setSubmitting(true);

    try {
      await onSubmit({
        title: title.trim() || (file ? file.name : "Untitled source"),
        sourceType: file ? inferSourceType(file.name) : "markdown",
        content: file ? undefined : content,
        file,
      });

      setTitle("");
      setContent("");
      setFile(null);
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <Card className="overflow-hidden">
      <CardHeader className="border-b border-border bg-[linear-gradient(135deg,rgba(245,207,124,0.2),rgba(158,98,61,0.04))]">
        <p className="text-[10px] font-bold uppercase tracking-[0.3em] text-muted-foreground">
          Ingestion Desk
        </p>
        <div className="mt-3 flex items-center gap-3">
          <NotebookPen className="h-5 w-5 text-foreground" />
          <CardTitle>Add evidence to the project corpus</CardTitle>
        </div>
        <CardDescription>
          Upload notes or files and let the backend stream them into the project evidence graph.
        </CardDescription>
      </CardHeader>

      <CardContent className="pt-6">
        <form className="space-y-4" onSubmit={handleSubmit}>
        <Input
          value={title}
          onChange={(event) => setTitle(event.target.value)}
          placeholder="Source title"
        />

        <Textarea
          value={content}
          onChange={(event) => setContent(event.target.value)}
          placeholder="Paste interview notes, debriefs, summaries, or markdown. You can also attach a file below."
          disabled={Boolean(file)}
        />

        <label className="flex cursor-pointer items-center justify-between rounded-[1.5rem] border border-dashed border-border bg-[var(--paper-strong)] px-4 py-4 transition hover:border-primary hover:bg-white">
          <span className="inline-flex items-center gap-3 text-sm text-foreground">
            <FileUp className="h-4 w-4" />
            {file ? file.name : "Attach a markdown, text, json, or pdf file"}
          </span>
          <input
            className="hidden"
            type="file"
            onChange={(event) => setFile(event.target.files?.[0] ?? null)}
          />
          <span className="text-xs uppercase tracking-[0.24em] text-muted-foreground">
            Optional
          </span>
        </label>

        <div className="flex items-center justify-between gap-4">
          <p className="max-w-xl text-sm text-muted-foreground">
            Every source is chunked, embedded, and streamed into the evidence graph so chat, insights, and requirements all stay grounded.
          </p>
          <Button disabled={submitting || (!file && !content.trim())}>
            {submitting ? <LoaderCircle className="h-4 w-4 animate-spin" /> : null}
            Ingest source
          </Button>
        </div>
        </form>
      </CardContent>
    </Card>
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
