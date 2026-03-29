import type { FormEvent } from "react";
import { useEffect, useState } from "react";

import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { Checkbox } from "@/components/ui/checkbox";
import { Badge } from "@/components/ui/badge";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import type { Insight, Requirement } from "@/types";

const statuses = ["draft", "accepted", "rejected"] as const;

export function RequirementDialog({
  open,
  mode,
  requirement,
  insights,
  onClose,
  onSubmit,
}: {
  open: boolean;
  mode: "create" | "edit";
  requirement: Requirement | null;
  insights: Insight[];
  onClose: () => void;
  onSubmit: (payload: {
    title: string;
    body: string;
    status: string;
    insightIds: number[];
  }) => Promise<void>;
}) {
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [status, setStatus] = useState<string>("draft");
  const [selectedInsightIds, setSelectedInsightIds] = useState<number[]>([]);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!open) {
      return;
    }

    setTitle(requirement?.title ?? "");
    setBody(requirement?.body ?? "");
    setStatus(requirement?.status ?? "draft");
    setSelectedInsightIds(requirement?.insights.map((item) => item.id) ?? []);
    setError(null);
  }, [open, requirement]);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSubmitting(true);
    setError(null);

    try {
      await onSubmit({
        title: title.trim(),
        body: body.trim(),
        status,
        insightIds: selectedInsightIds,
      });
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to save requirement");
    } finally {
      setSubmitting(false);
    }
  }

  function toggleInsight(insightId: number, checked: boolean) {
    setSelectedInsightIds((current) =>
      checked
        ? Array.from(new Set([...current, insightId]))
        : current.filter((id) => id !== insightId),
    );
  }

  return (
    <Dialog open={open} onOpenChange={(next) => !next && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{mode === "create" ? "Create requirement" : "Edit requirement"}</DialogTitle>
          <DialogDescription>
            Link strategy decisions to grounded insights so accepted requirements remain traceable.
          </DialogDescription>
        </DialogHeader>

        <form className="mt-6 space-y-5" onSubmit={handleSubmit}>
          <div className="space-y-2">
            <Label htmlFor="requirement-title">Title</Label>
            <Input
              id="requirement-title"
              value={title}
              onChange={(event) => setTitle(event.target.value)}
              placeholder="Frame the requirement"
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor="requirement-status">Status</Label>
            <Select value={status} onValueChange={setStatus}>
              <SelectTrigger id="requirement-status">
                <SelectValue placeholder="Select status" />
              </SelectTrigger>
              <SelectContent>
                {statuses.map((item) => (
                  <SelectItem key={item} value={item}>
                    {item}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-2">
            <Label htmlFor="requirement-body">Narrative</Label>
            <Textarea
              id="requirement-body"
              value={body}
              onChange={(event) => setBody(event.target.value)}
              placeholder="Describe the product behavior, workflow, or system capability required."
            />
          </div>

          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <Label>Linked insights</Label>
              <Badge variant="accent">{selectedInsightIds.length} selected</Badge>
            </div>
            <ScrollArea className="h-[18rem] rounded-[1.4rem] border border-border bg-white/60 p-4">
              <div className="space-y-3">
                {insights.map((insight) => {
                  const checked = selectedInsightIds.includes(insight.id);

                  return (
                    <label
                      key={insight.id}
                      className="flex items-start gap-3 rounded-[1.1rem] border border-border bg-[var(--paper-strong)] p-3"
                    >
                      <Checkbox
                        checked={checked}
                        onCheckedChange={(next) => toggleInsight(insight.id, next === true)}
                      />
                      <div className="space-y-1">
                        <div className="flex items-center gap-2">
                          <p className="text-sm font-semibold text-foreground">{insight.title}</p>
                          <Badge variant={insight.status === "accepted" ? "success" : "neutral"}>
                            {insight.status}
                          </Badge>
                        </div>
                        <p className="line-clamp-3 text-sm text-muted-foreground">{insight.body}</p>
                      </div>
                    </label>
                  );
                })}
              </div>
            </ScrollArea>
          </div>

          {error ? <p className="text-sm text-rose-700">{error}</p> : null}

          <div className="flex justify-end gap-3">
            <Button type="button" variant="secondary" onClick={onClose}>
              Cancel
            </Button>
            <Button disabled={submitting}>
              {submitting
                ? "Saving..."
                : mode === "create"
                  ? "Create requirement"
                  : "Save requirement"}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}
