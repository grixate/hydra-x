import { useCallback, useRef, useState } from "react";
import { motion } from "motion/react";
import { Bot, Link2, Loader2, Upload } from "lucide-react";

import { NoteEditorDialog } from "@/components/library/note-editor-dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { api } from "@/lib/api";

// Library spec §5.4: when a project has 0–2 sources, the Library tab
// surfaces a primary overlay inviting the user to add material. Once the
// source count rises, the overlay collapses into a small status indicator.

type LibraryEmptyOverlayProps = {
  projectId: number;
  sourceCount: number;
  onSourceAdded: () => void;
  // Spec §5.4 threshold — overlay collapses to a status pill above this.
  collapseThreshold?: number;
};

export function LibraryEmptyOverlay({
  projectId,
  sourceCount,
  onSourceAdded,
  collapseThreshold = 5,
}: LibraryEmptyOverlayProps) {
  const collapsed = sourceCount >= collapseThreshold;

  if (collapsed) {
    return (
      <div className="pointer-events-auto rounded-md border bg-background/88 px-2 py-1 text-[11px] text-muted-foreground shadow-sm backdrop-blur">
        {sourceCount} source{sourceCount === 1 ? "" : "s"}
      </div>
    );
  }

  return (
    <motion.div
      initial={{ opacity: 0, y: -4 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.25 }}
      className="pointer-events-auto w-[340px] rounded-lg border bg-background/95 p-4 shadow-lg backdrop-blur"
    >
      <div className="mb-3">
        <h2 className="text-sm font-semibold text-foreground">Build your Library</h2>
        <p className="mt-1 text-xs leading-relaxed text-muted-foreground">
          Drop documents, paste URLs, or ask Researcher to find sources. The graph
          forms as topics are extracted from new material.
        </p>
      </div>

      <DropZone projectId={projectId} onSourceAdded={onSourceAdded} />
      <UrlPaste projectId={projectId} onSourceAdded={onSourceAdded} />
      <div className="mb-2 flex items-center gap-1.5">
        <NoteEditorDialog
          projectId={projectId}
          onCreated={onSourceAdded}
          triggerLabel="Write a note"
        />
      </div>
      <AskResearcher projectId={projectId} />
    </motion.div>
  );
}

function DropZone({
  projectId,
  onSourceAdded,
}: {
  projectId: number;
  onSourceAdded: () => void;
}) {
  const [busy, setBusy] = useState(false);
  const [hover, setHover] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  const handleFiles = useCallback(
    async (fileList: FileList | null) => {
      if (!fileList || fileList.length === 0) return;
      setBusy(true);
      try {
        await api.bulkCreateSources(projectId, Array.from(fileList));
        onSourceAdded();
      } catch {
        // Ingestion failures surface in the source detail card per spec §4.3.
      } finally {
        setBusy(false);
      }
    },
    [projectId, onSourceAdded],
  );

  return (
    <div
      onDragOver={(e) => {
        e.preventDefault();
        setHover(true);
      }}
      onDragLeave={() => setHover(false)}
      onDrop={(e) => {
        e.preventDefault();
        setHover(false);
        void handleFiles(e.dataTransfer.files);
      }}
      onClick={() => inputRef.current?.click()}
      role="button"
      tabIndex={0}
      className={`mb-2 flex cursor-pointer flex-col items-center gap-1 rounded-md border border-dashed px-3 py-4 text-center text-xs transition-colors ${
        hover ? "border-foreground bg-muted/60" : "border-border hover:bg-muted/40"
      }`}
    >
      <input
        ref={inputRef}
        type="file"
        multiple
        className="hidden"
        accept=".txt,.md,.pdf,.docx,application/pdf,text/plain,text/markdown"
        onChange={(e) => {
          void handleFiles(e.target.files);
          e.target.value = "";
        }}
      />
      {busy ? (
        <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />
      ) : (
        <Upload className="h-4 w-4 text-muted-foreground" />
      )}
      <span className="font-medium text-foreground">
        {busy ? "Uploading…" : "Drop files or click to upload"}
      </span>
      <span className="text-muted-foreground">PDF, DOCX, MD, TXT</span>
    </div>
  );
}

function UrlPaste({
  projectId,
  onSourceAdded,
}: {
  projectId: number;
  onSourceAdded: () => void;
}) {
  const [url, setUrl] = useState("");
  const [busy, setBusy] = useState(false);

  const submit = useCallback(async () => {
    const trimmed = url.trim();
    if (!trimmed) return;
    setBusy(true);
    try {
      await api.addLibrarySource(projectId, {
        title: trimmed,
        kind: "url",
        original_url: trimmed,
        ingestion_status: "pending",
      });
      setUrl("");
      onSourceAdded();
    } catch {
      // Surface via source detail per spec §4.3.
    } finally {
      setBusy(false);
    }
  }, [projectId, url, onSourceAdded]);

  return (
    <div className="mb-2 flex items-center gap-1.5">
      <div className="relative flex-1">
        <Link2 className="absolute left-2 top-1/2 h-3 w-3 -translate-y-1/2 text-muted-foreground" />
        <Input
          value={url}
          onChange={(e) => setUrl(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter") void submit();
          }}
          placeholder="Paste a URL"
          className="h-7 pl-7 text-xs"
          disabled={busy}
        />
      </div>
      <Button size="xs" onClick={submit} disabled={busy || !url.trim()}>
        {busy ? <Loader2 className="h-3 w-3 animate-spin" /> : "Add"}
      </Button>
    </div>
  );
}

function AskResearcher({ projectId }: { projectId: number }) {
  // Spec §10: Researcher-driven discovery is a chat-pane interaction; the
  // overlay just opens chat focused on the prompt. Falls back to a no-op
  // until the chat-pane is wired in Phase 4.
  const handle = () => {
    window.dispatchEvent(
      new CustomEvent("hydra:open-chat", {
        detail: {
          projectId,
          prompt: "Find foundational sources for this project's topic.",
        },
      }),
    );
  };

  return (
    <Button size="xs" variant="outline" className="w-full justify-start" onClick={handle}>
      <Bot className="h-3 w-3" />
      Ask Researcher to find sources
    </Button>
  );
}
