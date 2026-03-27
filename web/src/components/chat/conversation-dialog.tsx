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
import type { ProductConversation } from "@/types";

export function ConversationDialog({
  open,
  projectName,
  conversationCount,
  onClose,
  onSubmit,
}: {
  open: boolean;
  projectName?: string | null;
  conversationCount: number;
  onClose: () => void;
  onSubmit: (payload: {
    persona: ProductConversation["persona"];
    title: string;
    externalRef?: string;
  }) => Promise<void>;
}) {
  const [persona, setPersona] = useState<ProductConversation["persona"]>("researcher");
  const [title, setTitle] = useState("");
  const [externalRef, setExternalRef] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!open) {
      return;
    }

    const nextIndex = conversationCount + 1;
    setPersona("researcher");
    setTitle(`${projectName ?? "Project"} research thread ${nextIndex}`);
    setExternalRef(`product-web-thread-${Date.now()}`);
    setError(null);
  }, [conversationCount, open, projectName]);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSubmitting(true);
    setError(null);

    try {
      await onSubmit({
        persona,
        title: title.trim(),
        externalRef: externalRef.trim() || undefined,
      });
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to create conversation");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={(next) => !next && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>New grounded conversation</DialogTitle>
          <DialogDescription>
            Start a new product thread and choose which agent persona should anchor the conversation.
          </DialogDescription>
        </DialogHeader>

        <form className="mt-6 space-y-5" onSubmit={handleSubmit}>
          <div className="space-y-2">
            <Label htmlFor="conversation-persona">Persona</Label>
            <Select value={persona} onValueChange={(value) => setPersona(value as ProductConversation["persona"])}>
              <SelectTrigger id="conversation-persona">
                <SelectValue placeholder="Select agent persona" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="researcher">researcher</SelectItem>
                <SelectItem value="strategist">strategist</SelectItem>
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-2">
            <Label htmlFor="conversation-title">Title</Label>
            <Input
              id="conversation-title"
              value={title}
              onChange={(event) => setTitle(event.target.value)}
              placeholder="User onboarding friction synthesis"
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor="conversation-external-ref">External reference</Label>
            <Input
              id="conversation-external-ref"
              value={externalRef}
              onChange={(event) => setExternalRef(event.target.value)}
              placeholder="Optional stable identifier"
            />
          </div>

          {error ? <p className="text-sm text-destructive">{error}</p> : null}

          <div className="flex justify-end gap-3">
            <Button type="button" variant="outline" onClick={onClose}>
              Cancel
            </Button>
            <Button disabled={submitting || !title.trim()}>
              {submitting ? "Creating..." : "Create conversation"}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}
