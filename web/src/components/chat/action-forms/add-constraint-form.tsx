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

interface AddConstraintFormProps {
  projectId: number;
  onClose: () => void;
}

export function AddConstraintForm({ projectId, onClose }: AddConstraintFormProps) {
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [scope, setScope] = useState("global");
  const [enforcement, setEnforcement] = useState("strict");
  const [submitting, setSubmitting] = useState(false);

  const handleSubmit = async () => {
    if (!title.trim()) return;
    setSubmitting(true);
    try {
      await api.createConstraint(projectId, {
        title: title.trim(),
        body: body.trim(),
        scope,
        enforcement,
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
          <DialogTitle>Add constraint</DialogTitle>
        </DialogHeader>
        <div className="space-y-3">
          <div>
            <Label className="text-xs mb-1 block">Title</Label>
            <Input
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="e.g., Must support offline mode"
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
              placeholder="Why this constraint exists..."
              className="text-sm resize-none"
            />
          </div>
          <div className="flex gap-3">
            <div className="flex-1">
              <Label className="text-xs mb-1 block">Scope</Label>
              <Select value={scope} onValueChange={setScope}>
                <SelectTrigger className="h-8 text-sm">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="global">Global</SelectItem>
                  <SelectItem value="technical">Technical</SelectItem>
                  <SelectItem value="design">Design</SelectItem>
                  <SelectItem value="process">Process</SelectItem>
                  <SelectItem value="business">Business</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="flex-1">
              <Label className="text-xs mb-1 block">Enforcement</Label>
              <Select value={enforcement} onValueChange={setEnforcement}>
                <SelectTrigger className="h-8 text-sm">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="strict">Strict</SelectItem>
                  <SelectItem value="advisory">Advisory</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" size="sm" onClick={onClose}>Cancel</Button>
          <Button size="sm" onClick={handleSubmit} disabled={!title.trim() || submitting}>
            {submitting ? "Adding..." : "Add constraint"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
