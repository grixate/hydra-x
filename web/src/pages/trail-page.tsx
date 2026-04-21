import { useState, useEffect, useRef, useCallback } from "react";
import { useParams, useNavigate, useLocation } from "react-router-dom";
import { AnimatePresence, motion } from "motion/react";
import {
  api,
  type TrailNode,
  type TrailChainNode,
  type TrailFlag,
} from "@/lib/api";
import { TrailPageView } from "@/components/trail/trail-page-view";
import { Skeleton } from "@/components/ui/skeleton";
import { Card, CardContent } from "@/components/ui/card";

export function TrailPage() {
  const { projectId, nodeType, nodeId } = useParams<{
    projectId: string;
    nodeType: string;
    nodeId: string;
  }>();
  const navigate = useNavigate();
  const location = useLocation();
  const pid = Number(projectId);
  const nid = Number(nodeId);

  const [center, setCenter] = useState<TrailNode | null>(null);
  const [upstream, setUpstream] = useState<TrailChainNode[]>([]);
  const [downstream, setDownstream] = useState<TrailChainNode[]>([]);
  const [flags, setFlags] = useState<TrailFlag[]>([]);
  const [initialLoading, setInitialLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const mountedRef = useRef(true);
  const scrollRef = useRef<HTMLDivElement>(null);

  // Determine back label from navigation state
  const from = (location.state as Record<string, string> | null)?.from;
  const backLabel = from === "stream"
    ? "Back to Stream"
    : from === "graph"
      ? "Back to Graph"
      : from?.startsWith("board")
        ? "Back to Board"
        : "Back";

  const fetchTrail = useCallback(() => {
    if (!projectId || !nodeType || !nodeId || isNaN(pid) || isNaN(nid)) return;

    mountedRef.current = true;
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
        if (mountedRef.current) setInitialLoading(false);
      });
  }, [projectId, nodeType, nodeId]);

  useEffect(() => {
    fetchTrail();
    return () => {
      mountedRef.current = false;
    };
  }, [fetchTrail]);

  // Scroll to top when navigating to a new node
  useEffect(() => {
    scrollRef.current?.scrollTo({ top: 0, behavior: "smooth" });
  }, [nodeType, nodeId]);

  if (error && !center) {
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

  if (initialLoading) {
    return (
      <div className="mx-auto max-w-2xl space-y-4 px-4 py-6">
        <Skeleton className="h-6 w-32" />
        <Skeleton className="h-px w-full" />
        <Skeleton className="h-24 w-full" />
        <Skeleton className="h-px w-full" />
        <Skeleton className="h-48 w-full" />
        <Skeleton className="h-px w-full" />
        <Skeleton className="h-24 w-full" />
      </div>
    );
  }

  if (!center) return null;

  return (
    <div ref={scrollRef} className="h-full overflow-auto pb-40">
      <AnimatePresence mode="popLayout">
        <motion.div
          key={`${nodeType}-${nodeId}`}
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          transition={{ duration: 0.15 }}
        >
          <TrailPageView
            center={center}
            upstream={upstream}
            downstream={downstream}
            flags={flags}
            projectId={pid}
            backLabel={backLabel}
            onBack={() => navigate(-1)}
            onNavigate={(type, id) =>
              navigate(`/projects/${projectId}/trail/${type}/${id}`, {
                state: location.state,
                replace: true,
              })
            }
            onNavigateGraph={() =>
              navigate(
                `/projects/${projectId}/graph?focus=${center.node_type}-${center.node_id}&highlight=${center.node_type}-${center.node_id}`,
              )
            }
            onChat={() =>
              navigate(`/projects/${projectId}/agents/strategist`)
            }
            onRefresh={fetchTrail}
          />
        </motion.div>
      </AnimatePresence>
    </div>
  );
}
