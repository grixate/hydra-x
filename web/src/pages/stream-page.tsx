import { useState, useEffect } from "react";
import { useParams, useNavigate } from "react-router-dom";
import { api, type StreamItem } from "@/lib/api";
import { StreamView } from "@/components/stream/stream-view";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";

export function StreamPage() {
  const { projectId } = useParams<{ projectId: string }>();
  const navigate = useNavigate();
  const [stream, setStream] = useState<{
    right_now: StreamItem[];
    recently: StreamItem[];
    emerging: StreamItem[];
  } | null>(null);
  const [loading, setLoading] = useState(true);

  const fetchStream = () => {
    if (!projectId) return;
    setLoading(true);
    api
      .getStream(Number(projectId))
      .then(setStream)
      .finally(() => setLoading(false));
  };

  useEffect(fetchStream, [projectId]);

  if (loading || !stream) {
    return (
      <div className="space-y-4 p-6">
        <Skeleton className="h-8 w-48" />
        <Skeleton className="h-24 w-full" />
        <Skeleton className="h-24 w-full" />
        <Skeleton className="h-24 w-full" />
      </div>
    );
  }

  return (
    <div className="space-y-6 p-6">
      <div className="flex items-center justify-between">
        <h1 className="font-display text-xl font-semibold">Stream</h1>
        <Button variant="ghost" size="sm" onClick={fetchStream}>
          Refresh
        </Button>
      </div>
      <StreamView
        rightNow={stream.right_now}
        recently={stream.recently}
        emerging={stream.emerging}
        onNavigateToNode={(nodeType, nodeId) =>
          navigate(`/product/${projectId}/trail/${nodeType}/${nodeId}`)
        }
      />
    </div>
  );
}
