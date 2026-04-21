import { useState, useRef } from "react";
import { useParams, useNavigate } from "react-router-dom";
import { motion, AnimatePresence } from "motion/react";
import { api } from "@/lib/api";
import { showToast } from "@/components/ui/toast-notification";
import { Button } from "@/components/ui/button";
import { FileUp, X, Check, Loader2, Circle } from "lucide-react";
import type { Source } from "@/types";

type ImportStep = "select" | "processing" | "complete";

type FileStatus = {
  file: File;
  status: "queued" | "uploading" | "analyzing" | "complete" | "error";
  source?: Source;
  error?: string;
};

export function BulkImportPage() {
  const { projectId } = useParams<{ projectId: string }>();
  const navigate = useNavigate();
  const pid = Number(projectId);

  const [step, setStep] = useState<ImportStep>("select");
  const [fileStatuses, setFileStatuses] = useState<FileStatus[]>([]);
  const [overallProgress, setOverallProgress] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);
  const [dragOver, setDragOver] = useState(false);

  const addFiles = (newFiles: File[]) => {
    const statuses = newFiles.map((file) => ({ file, status: "queued" as const }));
    setFileStatuses((prev) => [...prev, ...statuses]);
  };

  const removeFile = (index: number) => {
    setFileStatuses((prev) => prev.filter((_, i) => i !== index));
  };

  const startImport = async () => {
    setStep("processing");
    const filesToProcess = [...fileStatuses];
    const total = filesToProcess.length;

    for (let i = 0; i < total; i++) {
      setOverallProgress(i);

      setFileStatuses((prev) => {
        const next = [...prev];
        next[i] = { ...next[i], status: "uploading" };
        return next;
      });

      try {
        const file = filesToProcess[i].file;
        const source = await api.createSource(pid, {
          title: file.name,
          sourceType: "document",
          file,
        });

        // Update status to analyzing
        setFileStatuses((prev) => {
          const next = [...prev];
          next[i] = { ...next[i], status: "analyzing", source };
          return next;
        });

        // Trigger analysis (fire and forget)
        api.analyzeSource(pid, source.id).catch(() => {});

        // Mark complete
        setFileStatuses((prev) => {
          const next = [...prev];
          next[i] = { ...next[i], status: "complete" };
          return next;
        });
      } catch (err) {
        setFileStatuses((prev) => {
          const next = [...prev];
          next[i] = { ...next[i], status: "error", error: "Upload failed" };
          return next;
        });
      }
    }

    setOverallProgress(total);
    setStep("complete");
  };

  const completedCount = fileStatuses.filter((f) => f.status === "complete").length;
  const errorCount = fileStatuses.filter((f) => f.status === "error").length;

  const fileIcon = (status: FileStatus["status"]) => {
    switch (status) {
      case "complete": return <Check className="h-3.5 w-3.5 text-green-500" />;
      case "uploading":
      case "analyzing": return <Loader2 className="h-3.5 w-3.5 animate-spin text-primary" />;
      case "error": return <X className="h-3.5 w-3.5 text-destructive" />;
      default: return <Circle className="h-3.5 w-3.5 text-muted-foreground/40" />;
    }
  };

  const fileStatusLabel = (status: FileStatus["status"]) => {
    switch (status) {
      case "complete": return "done";
      case "uploading": return "uploading...";
      case "analyzing": return "analyzing...";
      case "error": return "failed";
      default: return "queued";
    }
  };

  return (
    <div className="mx-auto max-w-2xl px-4 py-8">
      <AnimatePresence mode="wait">
        {/* Step 1: File selection */}
        {step === "select" && (
          <motion.div
            key="select"
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -8 }}
            className="space-y-6"
          >
            <h1 className="text-lg font-semibold">Bulk import</h1>

            {/* Drop zone */}
            <div
              className={`flex cursor-pointer items-center justify-center rounded-xl border-2 border-dashed p-12 transition-colors ${
                dragOver
                  ? "border-primary/50 bg-primary/5"
                  : "border-muted-foreground/20 hover:border-muted-foreground/40"
              }`}
              onClick={() => inputRef.current?.click()}
              onDragOver={(e) => { e.preventDefault(); setDragOver(true); }}
              onDragLeave={() => setDragOver(false)}
              onDrop={(e) => {
                e.preventDefault();
                setDragOver(false);
                addFiles(Array.from(e.dataTransfer.files));
              }}
            >
              <div className="text-center">
                <FileUp className="mx-auto h-10 w-10 text-muted-foreground/40 mb-3" />
                <p className="text-sm font-medium">Drop files here</p>
                <p className="mt-1 text-xs text-muted-foreground">
                  Supports PDF, DOCX, MD, TXT, CSV
                </p>
                <Button variant="outline" size="sm" className="mt-3">
                  Browse files
                </Button>
              </div>
            </div>

            <input
              ref={inputRef}
              type="file"
              multiple
              accept=".pdf,.docx,.txt,.md,.csv"
              className="hidden"
              onChange={(e) => {
                addFiles(Array.from(e.target.files ?? []));
                if (inputRef.current) inputRef.current.value = "";
              }}
            />

            {/* File list */}
            {fileStatuses.length > 0 && (
              <div className="space-y-3">
                <div className="flex items-center justify-between">
                  <p className="text-sm font-medium">{fileStatuses.length} files selected</p>
                </div>
                <div className="space-y-0.5 max-h-64 overflow-y-auto rounded-lg border p-2">
                  {fileStatuses.map((fs, i) => (
                    <div
                      key={`${fs.file.name}-${i}`}
                      className="flex items-center gap-3 rounded-md px-2 py-1.5 text-sm"
                    >
                      <span className="flex-1 truncate">{fs.file.name}</span>
                      <span className="shrink-0 text-xs text-muted-foreground uppercase">
                        {fs.file.name.split(".").pop()}
                      </span>
                      <span className="shrink-0 text-xs text-muted-foreground">
                        {(fs.file.size / 1024).toFixed(0)} KB
                      </span>
                      <button
                        onClick={() => removeFile(i)}
                        className="shrink-0 text-muted-foreground hover:text-foreground"
                      >
                        <X className="h-3.5 w-3.5" />
                      </button>
                    </div>
                  ))}
                </div>

                <div className="flex items-center justify-end gap-2">
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => navigate(`/projects/${projectId}/board`)}
                  >
                    Cancel
                  </Button>
                  <Button size="sm" onClick={startImport}>
                    Start import
                  </Button>
                </div>
              </div>
            )}
          </motion.div>
        )}

        {/* Step 2: Processing */}
        {step === "processing" && (
          <motion.div
            key="processing"
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -8 }}
            className="space-y-6"
          >
            <h1 className="text-lg font-semibold">Importing {fileStatuses.length} files</h1>

            {/* Overall progress */}
            <div className="space-y-2">
              <div className="flex items-center justify-between text-sm text-muted-foreground">
                <span>{overallProgress} of {fileStatuses.length} complete</span>
                <span>{fileStatuses.length > 0 ? Math.round((overallProgress / fileStatuses.length) * 100) : 0}%</span>
              </div>
              <div className="h-2 rounded-full bg-muted overflow-hidden">
                <motion.div
                  className="h-full rounded-full bg-primary"
                  animate={{ width: `${fileStatuses.length > 0 ? (overallProgress / fileStatuses.length) * 100 : 0}%` }}
                  transition={{ duration: 0.3 }}
                />
              </div>
            </div>

            {/* Per-file status */}
            <div className="space-y-0.5 max-h-80 overflow-y-auto">
              {fileStatuses.map((fs, i) => (
                <div key={`${fs.file.name}-${i}`} className="flex items-center gap-3 px-2 py-1.5 text-sm">
                  {fileIcon(fs.status)}
                  <span className="flex-1 truncate">{fs.file.name}</span>
                  <span className="shrink-0 text-xs text-muted-foreground">
                    {fileStatusLabel(fs.status)}
                  </span>
                </div>
              ))}
            </div>
          </motion.div>
        )}

        {/* Step 3: Complete */}
        {step === "complete" && (
          <motion.div
            key="complete"
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            className="space-y-6"
          >
            <h1 className="text-lg font-semibold">Import complete</h1>

            <div className="space-y-2 text-sm">
              <p>{completedCount} sources processed</p>
              {errorCount > 0 && (
                <p className="text-destructive">{errorCount} files failed</p>
              )}
              <p className="text-muted-foreground">
                Analysis is running in the background. Draft insights will appear in the Stream.
              </p>
            </div>

            <div className="flex gap-2">
              <Button
                variant="outline"
                size="sm"
                onClick={() => navigate(`/projects/${projectId}/stream`)}
              >
                View in Stream
              </Button>
              <Button
                variant="outline"
                size="sm"
                onClick={() => navigate(`/projects/${projectId}/graph`)}
              >
                Open Graph
              </Button>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
