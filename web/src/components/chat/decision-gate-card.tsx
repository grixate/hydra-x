import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";

interface DecisionGateCardProps {
  title: string;
  onRecord?: (title: string) => void;
  onSkip?: () => void;
}

export function DecisionGateCard({
  title,
  onRecord,
  onSkip,
}: DecisionGateCardProps) {
  return (
    <Card className="my-2 border-accent bg-accent/10">
      <CardContent className="p-3">
        <p className="text-[10px] font-bold uppercase tracking-[0.3em] text-ink-soft">
          Decision point
        </p>
        <p className="mt-1 text-sm font-medium">{title}</p>
        <div className="mt-2 flex gap-2">
          <Button size="xs" onClick={() => onRecord?.(title)}>
            Record decision
          </Button>
          <Button size="xs" variant="ghost" onClick={onSkip}>
            Skip
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
