import { useState, useEffect, useRef } from "react";
import { useParams, useNavigate } from "react-router-dom";
import { api, type StreamItem } from "@/lib/api";
import { StreamView } from "@/components/stream/stream-view";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { Card, CardContent } from "@/components/ui/card";

export function StreamPage() {
  const { projectId } = useParams<{ projectId: string }>();
  const navigate = useNavigate();
  const [stream, setStream] = useState<{
    right_now: StreamItem[];
    recently: StreamItem[];
    emerging: StreamItem[];
  } | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const mountedRef = useRef(true);

  useEffect(() => {
    const pid = Number(projectId);
    if (!projectId || isNaN(pid)) return;

    mountedRef.current = true;
    setLoading(true);
    setError(null);

    api
      .getStream(pid)
      .then((data) => {
        if (mountedRef.current) setStream(data);
      })
      .catch((err) => {
        if (mountedRef.current) setError(err.message ?? "Failed to load stream");
      })
      .finally(() => {
        if (mountedRef.current) setLoading(false);
      });

    return () => {
      mountedRef.current = false;
    };
  }, [projectId]);

  const refreshStream = () => {
    const pid = Number(projectId);
    if (!projectId || isNaN(pid)) return;
    setError(null);
    api
      .getStream(pid)
      .then(setStream)
      .catch((err) => setError(err.message ?? "Failed to refresh"));
  };

  if (error) {
    return (
      <div className="p-6">
        <Card>
          <CardContent className="py-8 text-center text-sm text-muted-foreground">
            {error}
          </CardContent>
        </Card>
      </div>
    );
  }

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
        <h1 className="text-xl font-semibold">Stream</h1>
        <Button variant="ghost" size="sm" onClick={refreshStream}>
          Refresh
        </Button>
      </div>
      <StreamView
        rightNow={stream.right_now}
        recently={stream.recently}
        emerging={stream.emerging}
        onNavigateToNode={(nodeType, nodeId) =>
          navigate(`/projects/${projectId}/trail/${nodeType}/${nodeId}`)
        }
      />
    </div>
  );
}
