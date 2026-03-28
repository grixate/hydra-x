import { useState, useEffect, useRef } from "react";
import { useParams, useNavigate } from "react-router-dom";
import {
  api,
  type TrailNode,
  type TrailChainNode,
  type TrailFlag,
} from "@/lib/api";
import { TrailView } from "@/components/trail/trail-view";
import { Skeleton } from "@/components/ui/skeleton";
import { Card, CardContent } from "@/components/ui/card";

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
  const [error, setError] = useState<string | null>(null);
  const mountedRef = useRef(true);

  useEffect(() => {
    const pid = Number(projectId);
    const nid = Number(nodeId);
    if (!projectId || !nodeType || !nodeId || isNaN(pid) || isNaN(nid)) return;

    mountedRef.current = true;
    setLoading(true);
    setError(null);

    api
      .getTrail(pid, nodeType, nid)
      .then((data) => {
        if (!mountedRef.current) return;
        setCenter(data.center);
        setUpstream(data.upstream);
        setDownstream(data.downstream);
        setFlags(data.flags);
      })
      .catch((err) => {
        if (mountedRef.current) setError(err.message ?? "Failed to load trail");
      })
      .finally(() => {
        if (mountedRef.current) setLoading(false);
      });

    return () => {
      mountedRef.current = false;
    };
  }, [projectId, nodeType, nodeId]);

  if (error) {
    return (
      <div className="p-6">
        <Card>
          <CardContent className="py-8 text-center text-sm text-[var(--ink-soft)]">
            {error}
          </CardContent>
        </Card>
      </div>
    );
  }

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
