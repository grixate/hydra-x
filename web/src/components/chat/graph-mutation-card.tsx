import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";

interface GraphMutationCardProps {
  nodeType: string;
  nodeId: number;
  title: string;
  action: string;
  onApprove?: () => void;
  onReject?: () => void;
  onNavigate?: (nodeType: string, nodeId: number) => void;
}

export function GraphMutationCard({
  nodeType,
  nodeId,
  title,
  action,
  onApprove,
  onReject,
  onNavigate,
}: GraphMutationCardProps) {
  return (
    <Card className="my-2 border-accent/30 bg-accent/5">
      <CardContent className="flex items-center gap-3 p-3">
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2">
            <Badge variant="secondary" className="text-[9px]">
              {nodeType}
            </Badge>
            <span className="text-[10px] text-ink-soft">{action}</span>
          </div>
          <button
            type="button"
            className="mt-1 text-sm font-medium hover:underline"
            onClick={() => onNavigate?.(nodeType, nodeId)}
          >
            {title}
          </button>
        </div>
        <div className="flex shrink-0 gap-1">
          {onApprove && (
            <Button size="xs" onClick={onApprove}>
              Approve
            </Button>
          )}
          {onReject && (
            <Button size="xs" variant="ghost" onClick={onReject}>
              Reject
            </Button>
          )}
        </div>
      </CardContent>
    </Card>
  );
}
