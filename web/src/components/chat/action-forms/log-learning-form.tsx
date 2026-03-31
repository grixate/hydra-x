import { useState } from "react";
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
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

interface LogLearningFormProps {
  projectId: number;
  onClose: () => void;
}

export function LogLearningForm({ projectId, onClose }: LogLearningFormProps) {
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [learningType, setLearningType] = useState("retrospective");
  const [submitting, setSubmitting] = useState(false);

  const handleSubmit = async () => {
    if (!title.trim()) return;
    setSubmitting(true);
    try {
      await api.createLearning(projectId, {
        title: title.trim(),
        body: body.trim(),
        learning_type: learningType,
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
          <DialogTitle>Log a learning</DialogTitle>
        </DialogHeader>
        <div className="space-y-3">
          <div>
            <Label className="text-xs mb-1 block">Title</Label>
            <Input
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="What did you learn?"
              className="text-sm"
              autoFocus
            />
          </div>
          <div>
            <Label className="text-xs mb-1 block">Description</Label>
            <Textarea
              rows={3}
              value={body}
              onChange={(e) => setBody(e.target.value)}
              placeholder="Details, context, implications..."
              className="text-sm resize-none"
            />
          </div>
          <div>
            <Label className="text-xs mb-1 block">Type</Label>
            <Select value={learningType} onValueChange={setLearningType}>
              <SelectTrigger className="h-8 text-sm">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="retrospective">Retrospective</SelectItem>
                <SelectItem value="post_mortem">Post-mortem</SelectItem>
                <SelectItem value="usage_data">Usage data</SelectItem>
                <SelectItem value="experiment_result">Experiment result</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" size="sm" onClick={onClose}>Cancel</Button>
          <Button size="sm" onClick={handleSubmit} disabled={!title.trim() || submitting}>
            {submitting ? "Saving..." : "Log learning"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
