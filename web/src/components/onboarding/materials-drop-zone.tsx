import { useCallback, useRef, useState } from "react";
import { Upload, FileText, Link as LinkIcon, ArrowRight, X, Check, Loader2 } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { api } from "@/lib/api";
import { cn } from "@/lib/utils";

const MAX_ITEMS = 20;
const MAX_TOTAL_BYTES = 50 * 1024 * 1024;

const ACCEPTED_EXTS = [".txt", ".md", ".pdf", ".docx"];

type ItemStatus = "queued" | "uploading" | "done" | "failed";

type Item =
  | { kind: "file"; file: File; status: ItemStatus; error?: string }
  | { kind: "url"; url: string; status: ItemStatus; error?: string };

function totalBytes(items: Item[]) {
  return items
    .filter((i) => i.kind === "file")
    .reduce((sum, i) => sum + (i as Extract<Item, { kind: "file" }>).file.size, 0);
}

function isAcceptedFile(file: File) {
  const lower = file.name.toLowerCase();
  return ACCEPTED_EXTS.some((ext) => lower.endsWith(ext));
}

export function MaterialsDropZone({
  projectName,
  projectId,
  onComplete,
  onBack,
}: {
  projectName: string;
  projectId: number;
  onComplete: (count: number) => void | Promise<void>;
  onBack: () => void;
}) {
  const [items, setItems] = useState<Item[]>([]);
  const [urlText, setUrlText] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [dragActive, setDragActive] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const addFiles = useCallback(
    (files: FileList | File[]) => {
      setError(null);
      const incoming = Array.from(files).filter(isAcceptedFile);
      const rejected = Array.from(files).length - incoming.length;
      setItems((prev) => {
        const combined: Item[] = [
          ...prev,
          ...incoming.map<Item>((file) => ({ kind: "file", file, status: "queued" })),
        ];
        if (combined.length > MAX_ITEMS) {
          setError(`Up to ${MAX_ITEMS} items at once.`);
          return combined.slice(0, MAX_ITEMS);
        }
        if (totalBytes(combined) > MAX_TOTAL_BYTES) {
          setError("Total size exceeds 50 MB.");
          return prev;
        }
        return combined;
      });
      if (rejected > 0) {
        setError(`${rejected} file(s) ignored — only ${ACCEPTED_EXTS.join(", ")} supported.`);
      }
    },
    [],
  );

  function removeItem(index: number) {
    setItems((prev) => prev.filter((_, i) => i !== index));
  }

  function parseUrlLines(text: string): string[] {
    return text
      .split(/\r?\n/)
      .map((s) => s.trim())
      .filter(Boolean);
  }

  function commitUrls() {
    const lines = parseUrlLines(urlText);
    if (lines.length === 0) return;
    setItems((prev) => {
      const combined: Item[] = [
        ...prev,
        ...lines.map<Item>((url) => ({ kind: "url", url, status: "queued" })),
      ];
      if (combined.length > MAX_ITEMS) {
        setError(`Up to ${MAX_ITEMS} items at once.`);
        return combined.slice(0, MAX_ITEMS);
      }
      return combined;
    });
    setUrlText("");
  }

  async function handleSubmit() {
    if (submitting) return;
    // Commit any URLs still sitting in the textarea before checking.
    const trailingUrls = parseUrlLines(urlText);
    const allItems: Item[] =
      trailingUrls.length > 0
        ? [
            ...items,
            ...trailingUrls.map<Item>((url) => ({ kind: "url", url, status: "queued" })),
          ]
        : items;

    if (allItems.length === 0) {
      setError("Drop a file or paste a URL first.");
      return;
    }
    setItems(allItems);
    setUrlText("");
    setSubmitting(true);
    setError(null);

    // Materials ingestion needs the substrate schema (source/evidence
    // types). Apply the built-in product_development pretrained before
    // ingesting. Idempotent.
    try {
      await api.applyPretrainedSchema(projectId);
    } catch {
      /* surface per-item errors below */
    }

    let successCount = 0;
    for (let i = 0; i < allItems.length; i++) {
      const item = allItems[i];
      setItems((prev) => prev.map((x, idx) => (idx === i ? { ...x, status: "uploading" } : x)));
      try {
        if (item.kind === "file") {
          await api.createSource(projectId, {
            title: item.file.name,
            sourceType: inferTypeFromName(item.file.name),
            file: item.file,
          });
        } else {
          await api.createSource(projectId, {
            title: `Link: ${item.url}`,
            sourceType: "text",
            content: item.url,
          });
        }
        successCount++;
        setItems((prev) => prev.map((x, idx) => (idx === i ? { ...x, status: "done" } : x)));
      } catch (err) {
        setItems((prev) =>
          prev.map((x, idx) =>
            idx === i
              ? { ...x, status: "failed", error: err instanceof Error ? err.message : "failed" }
              : x,
          ),
        );
      }
    }

    setSubmitting(false);
    if (successCount > 0) {
      await onComplete(successCount);
    } else {
      setError("Nothing was ingested. Check the errors above.");
    }
  }

  function onDragOver(e: React.DragEvent) {
    e.preventDefault();
    setDragActive(true);
  }
  function onDragLeave() {
    setDragActive(false);
  }
  function onDrop(e: React.DragEvent) {
    e.preventDefault();
    setDragActive(false);
    addFiles(e.dataTransfer.files);
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
          disabled={submitting}
          className="text-xs text-muted-foreground"
        >
          Back
        </Button>
      </header>

      <div className="flex flex-1 items-center justify-center px-6 pb-12">
        <div className="w-full max-w-2xl">
          <div className="mb-6 text-center">
            <h1 className="text-2xl font-semibold tracking-tight">
              Drop files or paste links
            </h1>
            <p className="mt-2 text-sm text-muted-foreground">
              We'll read everything before proposing structure.
            </p>
          </div>

          <div
            onDragOver={onDragOver}
            onDragLeave={onDragLeave}
            onDrop={onDrop}
            onClick={() => fileInputRef.current?.click()}
            className={cn(
              "flex cursor-pointer flex-col items-center justify-center rounded-xl border border-dashed bg-card px-6 py-10 text-center transition",
              dragActive ? "border-primary bg-accent/40" : "hover:border-primary/60",
            )}
          >
            <Upload className="mb-3 h-6 w-6 text-muted-foreground" />
            <p className="text-sm font-medium">Drop files here, or click to browse</p>
            <p className="mt-1 text-xs text-muted-foreground">
              {ACCEPTED_EXTS.join(", ")} · up to {MAX_ITEMS} items, 50 MB total
            </p>
            <input
              ref={fileInputRef}
              type="file"
              multiple
              accept={ACCEPTED_EXTS.join(",")}
              className="hidden"
              onChange={(e) => {
                if (e.target.files) addFiles(e.target.files);
                e.target.value = "";
              }}
            />
          </div>

          <div className="mt-4">
            <label className="text-xs font-medium uppercase tracking-widest text-muted-foreground">
              URLs (one per line)
            </label>
            <Textarea
              value={urlText}
              onChange={(e) => setUrlText(e.target.value)}
              onBlur={commitUrls}
              placeholder="https://example.com/article"
              rows={3}
              disabled={submitting}
              className="mt-2 resize-none text-sm"
            />
          </div>

          {items.length > 0 ? (
            <ul className="mt-4 space-y-1.5">
              {items.map((item, i) => (
                <li
                  key={i}
                  className="flex items-center gap-2 rounded-md border bg-background px-2 py-1.5 text-xs"
                >
                  {item.kind === "file" ? (
                    <FileText className="h-3.5 w-3.5 text-muted-foreground" />
                  ) : (
                    <LinkIcon className="h-3.5 w-3.5 text-muted-foreground" />
                  )}
                  <span className="flex-1 truncate">
                    {item.kind === "file" ? item.file.name : item.url}
                  </span>
                  <StatusGlyph status={item.status} />
                  {item.status === "queued" ? (
                    <button
                      type="button"
                      onClick={() => removeItem(i)}
                      className="text-muted-foreground/70 hover:text-foreground"
                      aria-label="Remove"
                    >
                      <X className="h-3.5 w-3.5" />
                    </button>
                  ) : null}
                </li>
              ))}
            </ul>
          ) : null}

          {error ? (
            <p className="mt-3 text-xs text-destructive">{error}</p>
          ) : null}

          <div className="mt-6 flex justify-end">
            <Button
              onClick={handleSubmit}
              disabled={submitting || (items.length === 0 && urlText.trim().length === 0)}
              size="lg"
            >
              {submitting ? "Reading…" : "Read everything"}
              <ArrowRight className="ml-2 h-4 w-4" />
            </Button>
          </div>
        </div>
      </div>
    </div>
  );
}

function StatusGlyph({ status }: { status: ItemStatus }) {
  if (status === "uploading")
    return <Loader2 className="h-3.5 w-3.5 animate-spin text-muted-foreground" />;
  if (status === "done") return <Check className="h-3.5 w-3.5 text-emerald-500" />;
  if (status === "failed") return <X className="h-3.5 w-3.5 text-destructive" />;
  return null;
}

function inferTypeFromName(name: string): string {
  const lower = name.toLowerCase();
  if (lower.endsWith(".md")) return "markdown";
  if (lower.endsWith(".pdf")) return "pdf";
  if (lower.endsWith(".docx")) return "text";
  return "text";
}
