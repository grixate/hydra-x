import { useState } from "react";
import { Sparkles } from "lucide-react";

import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { api } from "@/lib/api";

type Slot = { node_type: string; title: string; body: string };

const INITIAL_SLOTS: Slot[] = [
  { node_type: "identity_fact", title: "", body: "" },
  { node_type: "principle", title: "", body: "" },
  { node_type: "value", title: "", body: "" },
];

const SLOT_COPY: Record<string, { label: string; hint: string }> = {
  identity_fact: {
    label: "Who you are",
    hint: "A stable fact — role, background, expertise. e.g. \"Former ML engineer, ten years in startups.\"",
  },
  principle: {
    label: "A principle you hold",
    hint: "A generalised truth you've internalised. e.g. \"Ship something small every week or momentum decays.\"",
  },
  value: {
    label: "Something you care about",
    hint: "An aesthetic or ethical commitment. e.g. \"Clarity over cleverness in every artefact.\"",
  },
};

export function IdentityBootstrapDialog({
  open,
  onClose,
  onSeeded,
}: {
  open: boolean;
  onClose: () => void;
  onSeeded?: (count: number) => void;
}) {
  const [slots, setSlots] = useState<Slot[]>(INITIAL_SLOTS);
  const [saving, setSaving] = useState(false);

  function update(index: number, field: "title" | "body", value: string) {
    setSlots((prev) => prev.map((slot, i) => (i === index ? { ...slot, [field]: value } : slot)));
  }

  async function submit() {
    const nodes = slots
      .filter((slot) => slot.title.trim() !== "")
      .map((slot) => ({
        node_type: slot.node_type,
        title: slot.title.trim(),
        body: slot.body.trim(),
      }));

    if (nodes.length === 0) {
      onClose();
      return;
    }

    setSaving(true);
    try {
      const { seeded } = await api.seedIdentity(nodes);
      onSeeded?.(seeded);
      setSlots(INITIAL_SLOTS);
      onClose();
    } catch {
      /* network errors surface in-place; user can retry */
    } finally {
      setSaving(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={(v) => !v && onClose()}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Sparkles className="h-4 w-4 text-primary" />
            Tell the agents about you
          </DialogTitle>
          <DialogDescription>
            These seed your personal "You" scope. Every project you start will inherit them, so
            agents stay consistent with how you actually think.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          {slots.map((slot, index) => {
            const copy = SLOT_COPY[slot.node_type];
            return (
              <div key={slot.node_type} className="space-y-1.5">
                <Label className="text-xs font-medium">{copy.label}</Label>
                <Input
                  value={slot.title}
                  onChange={(e) => update(index, "title", e.target.value)}
                  placeholder="One-line summary"
                />
                <Textarea
                  value={slot.body}
                  onChange={(e) => update(index, "body", e.target.value)}
                  placeholder={copy.hint}
                  rows={2}
                  className="text-xs"
                />
              </div>
            );
          })}
        </div>

        <DialogFooter>
          <Button variant="ghost" onClick={onClose} disabled={saving}>
            Skip
          </Button>
          <Button onClick={submit} disabled={saving}>
            {saving ? "Saving…" : "Save"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
