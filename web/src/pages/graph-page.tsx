import { useParams } from "react-router-dom";
import { GraphView } from "@/components/graph/graph-view";

export function GraphPage() {
  const { projectId } = useParams<{ projectId: string }>();

  if (!projectId) return null;

  return (
    <div className="h-full w-full">
      <GraphView projectId={Number(projectId)} />
    </div>
  );
}
