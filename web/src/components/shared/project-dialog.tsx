import type { FormEvent } from "react";
import { useEffect, useState } from "react";

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
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import type { Project } from "@/types";

const statuses = ["active", "archived"] as const;

export function ProjectDialog({
  open,
  mode,
  project,
  onClose,
  onSubmit,
}: {
  open: boolean;
  mode: "create" | "edit";
  project: Project | null;
  onClose: () => void;
  onSubmit: (payload: {
    name: string;
    slug?: string;
    description?: string;
    status: string;
  }) => Promise<void>;
}) {
  const [name, setName] = useState("");
  const [slug, setSlug] = useState("");
  const [description, setDescription] = useState("");
  const [status, setStatus] = useState<string>("active");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!open) {
      return;
    }

    setName(project?.name ?? "");
    setSlug(project?.slug ?? "");
    setDescription(project?.description ?? "");
    setStatus(project?.status ?? "active");
    setError(null);
  }, [open, project]);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSubmitting(true);
    setError(null);

    try {
      await onSubmit({
        name: name.trim(),
        slug: slug.trim() || undefined,
        description: description.trim() || undefined,
        status,
      });
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to save project");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={(next) => !next && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{mode === "create" ? "Create project" : "Edit project"}</DialogTitle>
          <DialogDescription>
            Define the product space that grounded sources, chat threads, insights, and requirements will live in.
          </DialogDescription>
        </DialogHeader>

        <form className="mt-6 space-y-5" onSubmit={handleSubmit}>
          <div className="space-y-2">
            <Label htmlFor="project-name">Name</Label>
            <Input
              id="project-name"
              value={name}
              onChange={(event) => setName(event.target.value)}
              placeholder="Hydra Checkout Redesign"
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor="project-slug">Slug</Label>
            <Input
              id="project-slug"
              value={slug}
              onChange={(event) => setSlug(event.target.value)}
              placeholder="optional-auto-generated"
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor="project-status">Status</Label>
            <Select value={status} onValueChange={setStatus}>
              <SelectTrigger id="project-status">
                <SelectValue placeholder="Select project status" />
              </SelectTrigger>
              <SelectContent>
                {statuses.map((option) => (
                  <SelectItem key={option} value={option}>
                    {option}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-2">
            <Label htmlFor="project-description">Description</Label>
            <Textarea
              id="project-description"
              value={description}
              onChange={(event) => setDescription(event.target.value)}
              placeholder="What are you trying to learn, validate, and ship?"
            />
          </div>

          {error ? <p className="text-sm text-destructive">{error}</p> : null}

          <div className="flex justify-end gap-3">
            <Button type="button" variant="outline" onClick={onClose}>
              Cancel
            </Button>
            <Button disabled={submitting || !name.trim()}>
              {submitting ? "Saving..." : mode === "create" ? "Create project" : "Save project"}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}
