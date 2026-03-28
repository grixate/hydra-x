import { useState, useEffect } from "react";
import { useParams, useNavigate } from "react-router-dom";
import { api, type TrailNode, type TrailChainNode, type TrailFlag } from "@/lib/api";
import { TrailView } from "@/components/trail/trail-view";
import { Skeleton } from "@/components/ui/skeleton";

export function TrailPage() {
  const { projectId, nodeType, nodeId } = useParams<{
    projectId: string;
    nodeType: string;
    nodeId: string;
  }>();
  const navigate = useNavigate();
  const [center, setCenter] = useState<TrailNode | null>(null);
  const [upstream, setUpstream] = useState<TrailChainNode[]>([]);
  const [downstream, setDownstream] = useState<TrailChainNode[]>([]);
  const [flags, setFlags] = useState<TrailFlag[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!projectId || !nodeType || !nodeId) return;
    setLoading(true);
    api
      .getTrail(Number(projectId), nodeType, Number(nodeId))
      .then((data) => {
        setCenter(data.center);
        setUpstream(data.upstream);
        setDownstream(data.downstream);
        setFlags(data.flags);
      })
      .finally(() => setLoading(false));
  }, [projectId, nodeType, nodeId]);

  if (loading) {
    return (
      <div className="space-y-4 p-6">
        <Skeleton className="h-8 w-48" />
        <Skeleton className="h-32 w-full" />
        <Skeleton className="h-48 w-full" />
        <Skeleton className="h-32 w-full" />
      </div>
    );
  }

  return (
    <div className="space-y-6 p-6">
      <h1 className="font-display text-xl font-semibold">Trail</h1>
      <TrailView
        center={center}
        upstream={upstream}
        downstream={downstream}
        flags={flags}
        onNodeClick={(type, id) =>
          navigate(`/product/${projectId}/trail/${type}/${id}`)
        }
      />
    </div>
  );
}
