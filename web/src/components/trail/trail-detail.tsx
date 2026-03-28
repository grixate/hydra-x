import type { TrailNode } from "@/lib/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";

interface TrailDetailProps {
  node: TrailNode;
}

export function TrailDetail({ node }: TrailDetailProps) {
  return (
    <Card className="border-accent">
      <CardHeader className="pb-2">
        <div className="flex items-start justify-between gap-2">
          <CardTitle className="text-base">
            {node.title || `${node.node_type}#${node.node_id}`}
          </CardTitle>
          <div className="flex items-center gap-1">
            <Badge variant="secondary" className="text-[9px]">
              {node.node_type}
            </Badge>
            <Badge
              variant={node.status === "active" ? "default" : "secondary"}
              className="text-[9px]"
            >
              {node.status}
            </Badge>
          </div>
        </div>
      </CardHeader>
      <CardContent>
        {node.body && (
          <p className="whitespace-pre-wrap text-sm text-ink-soft">
            {node.body}
          </p>
        )}
        {node.updated_at && (
          <p className="mt-3 text-[10px] text-ink-soft">
            Updated {new Date(node.updated_at).toLocaleDateString()}
          </p>
        )}
      </CardContent>
    </Card>
  );
}
