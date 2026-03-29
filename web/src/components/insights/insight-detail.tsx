import type { Insight } from "@/types";

import { EvidencePanel } from "@/components/insights/evidence-panel";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";

export function InsightDetail({
  insight,
  onEdit,
  onSelectSource,
  onSelectRequirement,
}: {
  insight: Insight | null;
  onEdit?: () => void;
  onSelectSource?: (sourceId: number) => void;
  onSelectRequirement?: (requirementId: number) => void;
}) {
  if (!insight) {
    return (
      <Card>
        <CardContent className="p-8">
          <p className="text-3xl text-foreground">Select an insight</p>
          <p className="mt-3 text-sm text-muted-foreground">
            Insights stay attached to their evidence chain so downstream strategy never floats free of the corpus.
          </p>
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="grid gap-6 xl:grid-cols-[minmax(0,1.25fr)_minmax(20rem,0.9fr)]">
      <Card>
        <CardContent className="p-6">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div className="flex flex-wrap items-center gap-3">
              <Badge variant={insight.status === "accepted" ? "success" : "neutral"}>
                {insight.status}
              </Badge>
              <Badge variant="accent">{insight.evidence.length} evidence links</Badge>
              <Badge variant="neutral">{insight.linked_requirements.length} linked requirements</Badge>
            </div>
            {onEdit ? (
              <Button variant="secondary" onClick={onEdit}>
                Edit insight
              </Button>
            ) : null}
          </div>
          <h2 className="mt-4 text-4xl text-foreground">{insight.title}</h2>
          <p className="mt-5 text-base leading-8 text-muted-foreground">{insight.body}</p>
          {insight.linked_requirements.length > 0 ? (
            <div className="mt-6">
              <p className="text-[10px] font-bold uppercase tracking-[0.3em] text-muted-foreground">
                Downstream requirements
              </p>
              <div className="mt-3 flex flex-wrap gap-2">
                {insight.linked_requirements.map((link) => (
                  <Button
                    key={link.requirement_id}
                    variant="outline"
                    size="sm"
                    onClick={() => onSelectRequirement?.(link.requirement_id)}
                  >
                    Requirement {link.requirement_id}
                  </Button>
                ))}
              </div>
            </div>
          ) : null}
        </CardContent>
      </Card>
      <EvidencePanel evidence={insight.evidence} onSelectSource={onSelectSource} />
    </div>
  );
}
