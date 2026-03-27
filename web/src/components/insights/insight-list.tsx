import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { ScrollArea } from "@/components/ui/scroll-area";
import type { Insight } from "@/types";
import { cn, relativeLabel } from "@/lib/utils";

export function InsightList({
  insights,
  selectedInsightId,
  onSelectInsight,
}: {
  insights: Insight[];
  selectedInsightId: number | null;
  onSelectInsight: (insightId: number) => void;
}) {
  const groups: Array<{ label: string; items: Insight[] }> = [
    { label: "Accepted", items: insights.filter((insight) => insight.status == "accepted") },
    { label: "Draft", items: insights.filter((insight) => insight.status == "draft") },
    { label: "Rejected", items: insights.filter((insight) => insight.status == "rejected") },
  ].filter((group) => group.items.length > 0);

  return (
    <Card>
      <CardHeader className="pb-4">
        <div className="flex items-end justify-between">
          <div>
            <p className="text-[10px] font-bold uppercase tracking-[0.3em] text-[var(--ink-soft)]">
              Research synthesis
            </p>
            <CardTitle className="mt-2">Insights</CardTitle>
          </div>
          <Badge variant="neutral">{insights.length}</Badge>
        </div>
      </CardHeader>

      <CardContent>
        <ScrollArea className="h-[34rem] pr-2">
          <div className="space-y-5">
            {groups.map((group) => (
              <div key={group.label} className="space-y-3">
                <div className="flex items-center justify-between">
                  <p className="text-[10px] font-bold uppercase tracking-[0.3em] text-[var(--ink-soft)]">
                    {group.label}
                  </p>
                  <Badge variant="neutral">{group.items.length}</Badge>
                </div>
                {group.items.map((insight) => (
                  <button
                    key={insight.id}
                    type="button"
                    onClick={() => onSelectInsight(insight.id)}
                    className={cn(
                      "w-full rounded-[1.4rem] border p-4 text-left transition",
                      selectedInsightId === insight.id
                        ? "border-[var(--ink)] bg-[var(--ink)] text-[var(--paper)]"
                        : "border-[var(--line)] bg-white/60 hover:border-[var(--accent)] hover:bg-white",
                    )}
                  >
                    <div className="flex items-center justify-between gap-3">
                      <p className="font-semibold">{insight.title}</p>
                      <Badge variant={insight.status === "accepted" ? "success" : "neutral"}>
                        {insight.status}
                      </Badge>
                    </div>
                    <p
                      className={cn(
                        "mt-3 line-clamp-3 text-sm",
                        selectedInsightId === insight.id
                          ? "text-white/75"
                          : "text-[var(--ink-soft)]",
                      )}
                    >
                      {insight.body}
                    </p>
                    <p
                      className={cn(
                        "mt-3 text-xs",
                        selectedInsightId === insight.id
                          ? "text-white/60"
                          : "text-[var(--ink-soft)]",
                      )}
                    >
                      {insight.evidence.length} evidence links · {relativeLabel(insight.updated_at)}
                    </p>
                  </button>
                ))}
              </div>
            ))}
          </div>
        </ScrollArea>
      </CardContent>
    </Card>
  );
}
