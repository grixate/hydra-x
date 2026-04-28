import { useCallback, useEffect, useState } from "react";
import { Check, Sparkles, X } from "lucide-react";

import { Button } from "@/components/ui/button";
import { api } from "@/lib/api";
import type { SchemaProposal } from "@/types";

const KIND_LABEL: Record<string, string> = {
  add_node_type: "node type",
  add_relationship_type: "relationship",
  add_flag_type: "flag",
  extend_node_type: "extend",
};

function readPayloadField(
  payload: Record<string, unknown> | null | undefined,
  key: string,
): string | null {
  if (!payload) return null;
  const value = payload[key];
  return typeof value === "string" ? value : null;
}

function describeProposal(p: SchemaProposal): { label: string; sub: string } {
  const typeKey = readPayloadField(p.payload, "type_key");
  const display = readPayloadField(p.payload, "display_name") ?? typeKey ?? "(unnamed)";
  const kind = KIND_LABEL[p.change_kind] ?? p.change_kind;
  return {
    label: display,
    sub: kind,
  };
}

export function SchemaProposalsCard({ projectId }: { projectId: number }) {
  const [proposals, setProposals] = useState<SchemaProposal[]>([]);
  const [busyId, setBusyId] = useState<number | null>(null);

  const refresh = useCallback(async () => {
    try {
      const data = await api.listSchemaProposals(projectId, { status: "pending" });
      setProposals(data ?? []);
    } catch {
      /* ignore */
    }
  }, [projectId]);

  useEffect(() => {
    refresh();
    const interval = window.setInterval(refresh, 6000);
    return () => window.clearInterval(interval);
  }, [refresh]);

  async function decide(p: SchemaProposal, action: "approve" | "reject") {
    if (busyId !== null) return;
    setBusyId(p.id);
    try {
      await api.decideSchemaProposal(projectId, p.id, action);
      setProposals((prev) => prev.filter((x) => x.id !== p.id));
    } finally {
      setBusyId(null);
    }
  }

  if (proposals.length === 0) return null;

  return (
    <div className="rounded-lg border bg-card p-3 shadow-sm">
      <div className="mb-2 flex items-center gap-2">
        <Sparkles className="h-3.5 w-3.5 text-emerald-500" />
        <p className="text-xs font-medium uppercase tracking-widest text-muted-foreground">
          Proposed schema · {proposals.length}
        </p>
      </div>
      <ul className="space-y-1.5">
        {proposals.map((p) => {
          const { label, sub } = describeProposal(p);
          const busy = busyId === p.id;
          return (
            <li
              key={p.id}
              className="flex items-center gap-2 rounded-md border bg-background px-2 py-1.5"
            >
              <div className="min-w-0 flex-1">
                <p className="truncate text-xs font-medium">{label}</p>
                <p className="text-[10px] uppercase tracking-widest text-muted-foreground">
                  {sub}
                </p>
              </div>
              <Button
                size="sm"
                variant="ghost"
                onClick={() => decide(p, "reject")}
                disabled={busy}
                aria-label="Reject proposal"
                className="h-7 w-7 p-0 text-muted-foreground hover:text-foreground"
              >
                <X className="h-3.5 w-3.5" />
              </Button>
              <Button
                size="sm"
                onClick={() => decide(p, "approve")}
                disabled={busy}
                aria-label="Approve proposal"
                className="h-7 px-2"
              >
                <Check className="h-3.5 w-3.5" />
              </Button>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
