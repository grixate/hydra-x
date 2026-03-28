import { useState, useEffect } from "react";
import { useParams, useNavigate } from "react-router-dom";
import { api } from "@/lib/api";
import type { Decision } from "@/types";
import { NodeList } from "@/components/shared/node-list";
import { StatusBadge } from "@/components/shared/status-badge";
import { TrailLink } from "@/components/trail/trail-link";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from "@/components/ui/accordion";
import { Skeleton } from "@/components/ui/skeleton";

export function DecisionsPage() {
  const { projectId } = useParams<{ projectId: string }>();
  const navigate = useNavigate();
  const [decisions, setDecisions] = useState<Decision[]>([]);
  const [selected, setSelected] = useState<Decision | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!projectId) return;
    setSelected(null);
    setLoading(true);
    setError(null);
    api.listDecisions(Number(projectId))
      .then(setDecisions)
      .catch((err) => setError(err.message ?? "Failed to load decisions"))
      .finally(() => setLoading(false));
  }, [projectId]);

  if (error) {
    return <div className="p-6"><Card><CardContent className="py-8 text-center text-sm text-[var(--ink-soft)]">{error}</CardContent></Card></div>;
  }

  if (loading) {
    return (
      <div className="space-y-4 p-6">
        <Skeleton className="h-8 w-48" />
        <Skeleton className="h-24 w-full" />
        <Skeleton className="h-24 w-full" />
      </div>
    );
  }

  return (
    <div className="p-6">
      <h1 className="font-display text-xl font-semibold mb-6">Decisions</h1>
      <div className="grid gap-6 xl:grid-cols-[360px_minmax(0,1fr)]">
        <NodeList
          items={decisions}
          nodeType="decision"
          selectedId={selected?.id}
          onSelect={setSelected}
          emptyMessage="No decisions recorded yet. Chat with the strategist to start capturing your product decisions."
        />
        {selected ? (
          <DecisionDetail
            decision={selected}
            projectId={projectId!}
            onNavigate={(type, id) => navigate(`/product/${projectId}/trail/${type}/${id}`)}
          />
        ) : (
          <Card>
            <CardContent className="py-12 text-center text-sm text-[var(--ink-soft)]">
              Select a decision to view details.
            </CardContent>
          </Card>
        )}
      </div>
    </div>
  );
}

function DecisionDetail({
  decision,
  projectId,
  onNavigate,
}: {
  decision: Decision;
  projectId: string;
  onNavigate: (type: string, id: number) => void;
}) {
  return (
    <div className="space-y-4">
      <Card>
        <CardHeader className="pb-2">
          <div className="flex items-start justify-between gap-2">
            <CardTitle className="text-base">{decision.title}</CardTitle>
            <StatusBadge status={decision.status} />
          </div>
          {decision.decided_by && (
            <p className="text-xs text-[var(--ink-soft)]">
              Decided by {decision.decided_by}
              {decision.decided_at && ` on ${new Date(decision.decided_at).toLocaleDateString()}`}
            </p>
          )}
        </CardHeader>
        <CardContent>
          <p className="whitespace-pre-wrap text-sm">{decision.body}</p>
        </CardContent>
      </Card>

      {decision.alternatives_considered.length > 0 && (
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm">Alternatives Considered</CardTitle>
          </CardHeader>
          <CardContent>
            <Accordion type="multiple">
              {decision.alternatives_considered.map((alt, i) => (
                <AccordionItem key={i} value={`alt-${i}`}>
                  <AccordionTrigger className="text-sm">{alt.title}</AccordionTrigger>
                  <AccordionContent>
                    <p className="text-sm mb-2">{alt.description}</p>
                    <p className="text-xs text-[var(--ink-soft)]">
                      Rejected: {alt.rejected_reason}
                    </p>
                  </AccordionContent>
                </AccordionItem>
              ))}
            </Accordion>
          </CardContent>
        </Card>
      )}

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-sm">Lineage</CardTitle>
        </CardHeader>
        <CardContent>
          <TrailLink
            nodeType="decision"
            nodeId={decision.id}
            title="View full trail"
            onClick={onNavigate}
          />
        </CardContent>
      </Card>
    </div>
  );
}
