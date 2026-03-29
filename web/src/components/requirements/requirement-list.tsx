import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { ScrollArea } from "@/components/ui/scroll-area";
import type { Requirement } from "@/types";
import { cn, relativeLabel } from "@/lib/utils";

export function RequirementList({
  requirements,
  selectedRequirementId,
  onSelectRequirement,
}: {
  requirements: Requirement[];
  selectedRequirementId: number | null;
  onSelectRequirement: (requirementId: number) => void;
}) {
  const groups: Array<{ label: string; items: Requirement[] }> = [
    { label: "Grounded", items: requirements.filter((requirement) => requirement.grounded) },
    { label: "Needs review", items: requirements.filter((requirement) => !requirement.grounded) },
  ].filter((group) => group.items.length > 0);

  return (
    <Card>
      <CardHeader className="pb-4">
        <div className="flex items-end justify-between">
          <div>
            <p className="text-[10px] font-bold uppercase tracking-[0.3em] text-muted-foreground">
              Strategy map
            </p>
            <CardTitle className="mt-2">Requirements</CardTitle>
          </div>
          <Badge variant="neutral">{requirements.length}</Badge>
        </div>
      </CardHeader>

      <CardContent>
        <ScrollArea className="h-[34rem] pr-2">
          <div className="space-y-5">
            {groups.map((group) => (
              <div key={group.label} className="space-y-3">
                <div className="flex items-center justify-between">
                  <p className="text-[10px] font-bold uppercase tracking-[0.3em] text-muted-foreground">
                    {group.label}
                  </p>
                  <Badge variant="neutral">{group.items.length}</Badge>
                </div>
                {group.items.map((requirement) => (
                  <button
                    key={requirement.id}
                    type="button"
                    onClick={() => onSelectRequirement(requirement.id)}
                    className={cn(
                      "w-full rounded-[1.4rem] border p-4 text-left transition",
                      selectedRequirementId === requirement.id
                        ? "border-foreground bg-foreground text-background"
                        : "border-border bg-white/60 hover:border-primary hover:bg-white",
                    )}
                  >
                    <div className="flex items-center justify-between gap-3">
                      <p className="font-semibold">{requirement.title}</p>
                      <Badge variant={requirement.grounded ? "success" : "warning"}>
                        {requirement.grounded ? "grounded" : "review"}
                      </Badge>
                    </div>
                    <p
                      className={cn(
                        "mt-3 line-clamp-3 text-sm",
                        selectedRequirementId === requirement.id
                          ? "text-white/75"
                          : "text-muted-foreground",
                      )}
                    >
                      {requirement.body}
                    </p>
                    <p
                      className={cn(
                        "mt-3 text-xs",
                        selectedRequirementId === requirement.id
                          ? "text-white/60"
                          : "text-muted-foreground",
                      )}
                    >
                      {requirement.insights.length} linked insights ·{" "}
                      {relativeLabel(requirement.updated_at)}
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
