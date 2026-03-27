import type { Requirement } from "@/types";

import { EvidenceChain } from "@/components/requirements/evidence-chain";
import { UngroundedWarning } from "@/components/requirements/ungrounded-warning";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";

export function RequirementDetail({
  requirement,
  onEdit,
  onSelectInsight,
  onSelectSource,
}: {
  requirement: Requirement | null;
  onEdit?: () => void;
  onSelectInsight?: (insightId: number) => void;
  onSelectSource?: (sourceId: number) => void;
}) {
  if (!requirement) {
    return (
      <Card>
        <CardContent className="p-8">
          <p className="font-display text-3xl text-[var(--ink)]">Select a requirement</p>
          <p className="mt-3 text-sm text-[var(--ink-soft)]">
            Requirement decisions should read like the final layer of a traceability graph, not loose product opinion.
          </p>
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="grid gap-6 xl:grid-cols-[minmax(0,1.2fr)_minmax(20rem,0.95fr)]">
      <Card>
        <CardContent className="p-6">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div className="flex flex-wrap items-center gap-3">
              <Badge variant={requirement.grounded ? "success" : "warning"}>
                {requirement.grounded ? "grounded" : "ungrounded"}
              </Badge>
              <Badge variant="neutral">{requirement.status}</Badge>
            </div>
            {onEdit ? (
              <Button variant="secondary" onClick={onEdit}>
                Edit requirement
              </Button>
            ) : null}
          </div>
          <h2 className="mt-4 font-display text-4xl text-[var(--ink)]">{requirement.title}</h2>
          <p className="mt-5 text-base leading-8 text-[var(--ink-soft)]">{requirement.body}</p>
          {!requirement.grounded ? <div className="mt-6"><UngroundedWarning /></div> : null}
        </CardContent>
      </Card>
      <EvidenceChain
        requirement={requirement}
        onSelectInsight={onSelectInsight}
        onSelectSource={onSelectSource}
      />
    </div>
  );
}
