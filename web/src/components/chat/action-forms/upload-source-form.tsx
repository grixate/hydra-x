import { useState, useRef } from "react";
import { api } from "@/lib/api";
import { showToast } from "@/components/ui/toast-notification";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { FileUp, X } from "lucide-react";

interface UploadSourceFormProps {
  projectId: number;
  onClose: () => void;
}

export function UploadSourceForm({ projectId, onClose }: UploadSourceFormProps) {
  const [files, setFiles] = useState<File[]>([]);
  const [submitting, setSubmitting] = useState(false);
  const [progress, setProgress] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);

  const removeFile = (index: number) => {
    setFiles((prev) => prev.filter((_, i) => i !== index));
  };

  const handleSubmit = async () => {
    if (files.length === 0) return;
    setSubmitting(true);
    setProgress(0);

    let successCount = 0;
    for (let i = 0; i < files.length; i++) {
      setProgress(i + 1);
      try {
        const file = files[i];
        const source = await api.createSource(projectId, {
          title: file.name,
          sourceType: "document",
          file,
        });
        api.analyzeSource(projectId, source.id).catch(() => {});
        successCount++;
      } catch {
        // Continue with remaining files
      }
    }
    if (successCount > 0) {
      showToast(`${successCount} file${successCount > 1 ? "s" : ""} uploaded — analysis starting`);
    }
    if (successCount < files.length) {
      showToast(`${files.length - successCount} file${files.length - successCount > 1 ? "s" : ""} failed to upload`);
    }
    setSubmitting(false);
    onClose();
  };

  return (
    <Dialog open onOpenChange={(open) => { if (!open && !submitting) onClose(); }}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Upload sources</DialogTitle>
        </DialogHeader>
        <div className="space-y-4">
          <div
            className="flex cursor-pointer items-center justify-center rounded-lg border-2 border-dashed p-8 text-muted-foreground hover:border-primary/50 transition-colors"
            onClick={() => inputRef.current?.click()}
          >
            <div className="text-center">
              <FileUp className="mx-auto h-8 w-8 mb-2" />
              <p className="text-sm">Click to select files</p>
              <p className="text-[11px]">PDF, DOCX, TXT, MD, CSV</p>
            </div>
          </div>
          <input
            ref={inputRef}
            type="file"
            multiple
            accept=".pdf,.docx,.txt,.md,.csv"
            className="hidden"
            onChange={(e) => {
              const selected = Array.from(e.target.files ?? []);
              if (selected.length > 0) {
                setFiles((prev) => [...prev, ...selected]);
              }
              if (inputRef.current) inputRef.current.value = "";
            }}
          />

          {/* File list */}
          {files.length > 0 && (
            <div className="space-y-1 max-h-48 overflow-y-auto">
              {files.map((f, i) => (
                <div key={`${f.name}-${i}`} className="flex items-center gap-2 rounded-md px-2 py-1.5 text-sm">
                  <span className="flex-1 truncate">{f.name}</span>
                  <span className="shrink-0 text-xs text-muted-foreground">
                    {(f.size / 1024).toFixed(0)} KB
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
          )}
          <p className="text-xs text-muted-foreground leading-relaxed">
            Agents will analyze uploaded files and create insights automatically.
            For 10+ files, use bulk import from the + menu.
          </p>
        </div>
        <DialogFooter>
          <Button variant="outline" size="sm" onClick={onClose} disabled={submitting}>Cancel</Button>
          <Button size="sm" onClick={handleSubmit} disabled={files.length === 0 || submitting}>
            {submitting
              ? `Uploading ${progress} of ${files.length}...`
              : `Upload${files.length > 0 ? ` (${files.length})` : ""}`}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
