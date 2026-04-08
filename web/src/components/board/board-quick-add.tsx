import { useState, useRef } from "react";
import { motion, AnimatePresence } from "motion/react";
import { Button } from "@/components/ui/button";
import { Plus, Paperclip, Link2, X } from "lucide-react";
import { api } from "@/lib/api";

interface BoardQuickAddProps {
  projectId: number;
  sessionId: number;
  onNodeCreated?: () => void;
}

export function BoardQuickAdd({ projectId, sessionId, onNodeCreated }: BoardQuickAddProps) {
  const [noteOpen, setNoteOpen] = useState(false);
  const [linkOpen, setLinkOpen] = useState(false);
  const [noteText, setNoteText] = useState("");
  const [linkUrl, setLinkUrl] = useState("");
  const [saving, setSaving] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);

  async function saveNote() {
    if (!noteText.trim() || saving) return;
    setSaving(true);
    try {
      await api.createBoardNode(projectId, sessionId, {
        node_type: "source_ref",
        title: noteText.trim().slice(0, 80),
        body: noteText.trim(),
        created_by: "human",
        metadata: { source_type: "note" },
      });
      setNoteText("");
      setNoteOpen(false);
      onNodeCreated?.();
    } catch (err) {
      console.error("Failed to save note:", err);
    } finally {
      setSaving(false);
    }
  }

  async function saveLink() {
    if (!linkUrl.trim() || saving) return;
    setSaving(true);
    try {
      await api.createBoardNode(projectId, sessionId, {
        node_type: "source_ref",
        title: linkUrl.trim(),
        body: linkUrl.trim(),
        created_by: "human",
        metadata: { source_type: "link", url: linkUrl.trim() },
      });
      setLinkUrl("");
      setLinkOpen(false);
      onNodeCreated?.();
    } catch (err) {
      console.error("Failed to save link:", err);
    } finally {
      setSaving(false);
    }
  }

  async function handleFileUpload(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    setSaving(true);
    try {
      // Upload as a source first
      const formData = new FormData();
      formData.append("source[upload]", file);
      formData.append("source[title]", file.name);

      const resp = await fetch(
        `${import.meta.env.VITE_API_BASE ?? "/api/v1"}/projects/${projectId}/sources`,
        { method: "POST", body: formData, credentials: "include" },
      );

      if (!resp.ok) {
        console.error("Source upload failed:", resp.status);
        return;
      }

      // Also create a board node referencing it
      await api.createBoardNode(projectId, sessionId, {
        node_type: "source_ref",
        title: file.name,
        body: `Uploaded file: ${file.name}`,
        created_by: "human",
        metadata: { source_type: "file", filename: file.name },
      });
      onNodeCreated?.();
    } catch (err) {
      console.error("File upload error:", err);
    } finally {
      setSaving(false);
      if (fileRef.current) fileRef.current.value = "";
    }
  }

  return (
    <div className="absolute bottom-32 left-4 z-10">
      <input
        ref={fileRef}
        type="file"
        className="hidden"
        onChange={handleFileUpload}
      />

      {/* Quick-add buttons */}
      <div className="flex items-center gap-1.5">
        <Button
          variant="outline"
          size="sm"
          className="rounded-full text-xs shadow-sm bg-background"
          onClick={() => { setNoteOpen(!noteOpen); setLinkOpen(false); }}
        >
          <Plus className="mr-1 h-3 w-3" /> Note
        </Button>
        <Button
          variant="outline"
          size="sm"
          className="rounded-full text-xs shadow-sm bg-background"
          onClick={() => fileRef.current?.click()}
          disabled={saving}
        >
          <Paperclip className="mr-1 h-3 w-3" /> File
        </Button>
        <Button
          variant="outline"
          size="sm"
          className="rounded-full text-xs shadow-sm bg-background"
          onClick={() => { setLinkOpen(!linkOpen); setNoteOpen(false); }}
        >
          <Link2 className="mr-1 h-3 w-3" /> Link
        </Button>
      </div>

      {/* Note popover */}
      <AnimatePresence>
        {noteOpen && (
          <motion.div
            initial={{ opacity: 0, y: 8, scale: 0.95 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 8, scale: 0.95 }}
            transition={{ duration: 0.15 }}
            className="absolute bottom-10 left-0 w-72 rounded-xl border bg-background p-3 shadow-lg space-y-2"
          >
            <div className="flex items-center justify-between">
              <span className="text-xs font-medium">Quick note</span>
              <button onClick={() => setNoteOpen(false)} className="text-muted-foreground hover:text-foreground">
                <X className="h-3.5 w-3.5" />
              </button>
            </div>
            <textarea
              autoFocus
              rows={3}
              value={noteText}
              onChange={(e) => setNoteText(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) saveNote();
                if (e.key === "Escape") setNoteOpen(false);
              }}
              placeholder="Meeting takeaway, idea, observation..."
              className="w-full resize-none rounded-lg border bg-transparent p-2 text-sm placeholder:text-muted-foreground focus:outline-none focus:border-primary"
            />
            <div className="flex justify-end">
              <Button size="sm" className="text-xs" onClick={saveNote} disabled={saving || !noteText.trim()}>
                {saving ? "Saving..." : "Save"}
              </Button>
            </div>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Link popover */}
      <AnimatePresence>
        {linkOpen && (
          <motion.div
            initial={{ opacity: 0, y: 8, scale: 0.95 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 8, scale: 0.95 }}
            transition={{ duration: 0.15 }}
            className="absolute bottom-10 left-0 w-72 rounded-xl border bg-background p-3 shadow-lg space-y-2"
          >
            <div className="flex items-center justify-between">
              <span className="text-xs font-medium">Add link</span>
              <button onClick={() => setLinkOpen(false)} className="text-muted-foreground hover:text-foreground">
                <X className="h-3.5 w-3.5" />
              </button>
            </div>
            <input
              autoFocus
              value={linkUrl}
              onChange={(e) => setLinkUrl(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter") saveLink();
                if (e.key === "Escape") setLinkOpen(false);
              }}
              placeholder="https://..."
              className="w-full rounded-lg border bg-transparent p-2 text-sm placeholder:text-muted-foreground focus:outline-none focus:border-primary"
            />
            <div className="flex justify-end">
              <Button size="sm" className="text-xs" onClick={saveLink} disabled={saving || !linkUrl.trim()}>
                {saving ? "Saving..." : "Add"}
              </Button>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
