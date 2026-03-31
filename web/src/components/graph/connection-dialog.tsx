import { useState } from "react";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import type { GraphDataNode } from "@/types";
import { NODE_COLORS } from "./graph-constants";
import { cn } from "@/lib/utils";

const EDGE_KINDS = [
  { value: "lineage", label: "Lineage", description: "Derived from" },
  { value: "supports", label: "Supports", description: "Evidence for" },
  { value: "contradicts", label: "Contradicts", description: "Conflicts with" },
  { value: "blocks", label: "Blocks", description: "Prevents progress" },
  { value: "enables", label: "Enables", description: "Makes possible" },
  { value: "dependency", label: "Dependency", description: "Depends on" },
] as const;

interface ConnectionDialogProps {
  sourceNode: GraphDataNode;
  targetNode: GraphDataNode;
  onConfirm: (kind: string, reason: string) => void;
  onCancel: () => void;
}

export function ConnectionDialog({
  sourceNode,
  targetNode,
  onConfirm,
  onCancel,
}: ConnectionDialogProps) {
  const [kind, setKind] = useState<string>("lineage");
  const [reason, setReason] = useState("");
  const [submitting, setSubmitting] = useState(false);

  const handleConfirm = async () => {
    setSubmitting(true);
    await onConfirm(kind, reason);
    setSubmitting(false);
  };

  return (
    <Dialog open onOpenChange={(open) => !open && onCancel()}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Connect nodes</DialogTitle>
        </DialogHeader>

        <div className="space-y-4">
          {/* Source → Target */}
          <div className="flex items-center gap-2 text-sm">
            <div className="flex items-center gap-1.5">
              <span
                className="h-2 w-2 rounded-full"
                style={{ backgroundColor: NODE_COLORS[sourceNode.node_type] }}
              />
              <span className="font-medium truncate max-w-[140px]">
                {sourceNode.title}
              </span>
            </div>
            <span className="text-muted-foreground">→</span>
            <div className="flex items-center gap-1.5">
              <span
                className="h-2 w-2 rounded-full"
                style={{ backgroundColor: NODE_COLORS[targetNode.node_type] }}
              />
              <span className="font-medium truncate max-w-[140px]">
                {targetNode.title}
              </span>
            </div>
          </div>

          {/* Kind selector */}
          <div>
            <Label className="text-xs text-muted-foreground mb-2 block">
              Relationship
            </Label>
            <div className="grid grid-cols-2 gap-1.5">
              {EDGE_KINDS.map((ek) => (
                <button
                  key={ek.value}
                  type="button"
                  onClick={() => setKind(ek.value)}
                  className={cn(
                    "rounded-lg border px-3 py-2 text-left text-xs transition-colors",
                    kind === ek.value
                      ? "border-primary bg-primary/10 text-primary"
                      : "border-border hover:bg-muted/50",
                  )}
                >
                  <div className="font-medium">{ek.label}</div>
                  <div className="text-muted-foreground text-[10px]">
                    {ek.description}
                  </div>
                </button>
              ))}
            </div>
          </div>

          {/* Reason */}
          <div>
            <Label className="text-xs text-muted-foreground mb-1 block">
              Reason (optional)
            </Label>
            <Textarea
              rows={2}
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              placeholder="Why are these connected?"
              className="text-sm resize-none"
            />
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" size="sm" onClick={onCancel}>
            Cancel
          </Button>
          <Button size="sm" onClick={handleConfirm} disabled={submitting}>
            {submitting ? "Connecting..." : "Connect"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
