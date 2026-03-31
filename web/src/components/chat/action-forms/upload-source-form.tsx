import { useState, useRef } from "react";
import { api } from "@/lib/api";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { FileUp } from "lucide-react";

interface UploadSourceFormProps {
  projectId: number;
  onClose: () => void;
}

export function UploadSourceForm({ projectId, onClose }: UploadSourceFormProps) {
  const [title, setTitle] = useState("");
  const [file, setFile] = useState<File | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  const handleSubmit = async () => {
    if (!file) return;
    setSubmitting(true);
    try {
      await api.createSource(projectId, {
        title: title || file.name,
        sourceType: "document",
        file,
      });
      onClose();
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Dialog open onOpenChange={(open) => !open && onClose()}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Upload source</DialogTitle>
        </DialogHeader>
        <div className="space-y-4">
          <div>
            <Label className="text-xs mb-1 block">File</Label>
            <div
              className="flex cursor-pointer items-center justify-center rounded-lg border-2 border-dashed p-8 text-muted-foreground hover:border-primary/50 transition-colors"
              onClick={() => inputRef.current?.click()}
            >
              <div className="text-center">
                <FileUp className="mx-auto h-8 w-8 mb-2" />
                <p className="text-sm">{file ? file.name : "Click to select a file"}</p>
                <p className="text-[11px]">PDF, DOCX, TXT, MD, CSV</p>
              </div>
            </div>
            <input
              ref={inputRef}
              type="file"
              accept=".pdf,.docx,.txt,.md,.csv"
              className="hidden"
              onChange={(e) => {
                const f = e.target.files?.[0];
                if (f) {
                  setFile(f);
                  if (!title) setTitle(f.name.replace(/\.[^.]+$/, ""));
                }
              }}
            />
          </div>
          <div>
            <Label className="text-xs mb-1 block">Title</Label>
            <Input
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="Source title"
              className="text-sm"
            />
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" size="sm" onClick={onClose}>Cancel</Button>
          <Button size="sm" onClick={handleSubmit} disabled={!file || submitting}>
            {submitting ? "Uploading..." : "Upload"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
