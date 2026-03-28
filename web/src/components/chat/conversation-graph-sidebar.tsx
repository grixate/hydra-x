import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { TrailLink } from "@/components/trail/trail-link";

interface ConversationNode {
  nodeType: string;
  nodeId: number;
  title?: string;
}

interface ConversationGraphSidebarProps {
  nodes: ConversationNode[];
  onNavigateToNode?: (nodeType: string, nodeId: number) => void;
}

export function ConversationGraphSidebar({
  nodes,
  onNavigateToNode,
}: ConversationGraphSidebarProps) {
  if (nodes.length === 0) return null;

  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-xs">
          Conversation artifacts
          <Badge variant="secondary" className="ml-2 text-[9px]">
            {nodes.length}
          </Badge>
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-1">
        {nodes.map((node) => (
          <TrailLink
            key={`${node.nodeType}-${node.nodeId}`}
            nodeType={node.nodeType}
            nodeId={node.nodeId}
            title={node.title}
            onClick={onNavigateToNode}
          />
        ))}
      </CardContent>
    </Card>
  );
}
