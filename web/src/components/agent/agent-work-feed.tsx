import { useState, useEffect, useCallback } from "react";
import { api } from "@/lib/api";
import { Button } from "@/components/ui/button";
import { FeedNodeCard } from "./agent-feed-node-card";
import { FeedArtifactCard } from "./agent-feed-artifact-card";

type FeedItem = {
  type: "node" | "artifact";
  node_type?: string;
  node_id?: number;
  artifact_id?: number;
  title: string;
  body?: string;
  status?: string;
  version?: number;
  change_summary?: string;
  upstream_count?: number;
  downstream_count?: number;
  flag_count?: number;
  origin?: string;
  origin_title?: string | null;
  created_at?: string;
  updated_at?: string;
};

interface AgentWorkFeedProps {
  projectId: number;
  persona: string;
}

const PAGE_SIZE = 20;

export function AgentWorkFeed({ projectId, persona }: AgentWorkFeedProps) {
  const [items, setItems] = useState<FeedItem[]>([]);
  const [totalCount, setTotalCount] = useState(0);
  const [loading, setLoading] = useState(true);

  const loadFeed = useCallback(
    (offset: number, append: boolean) => {
      api.getAgentFeed(projectId, persona, PAGE_SIZE, offset)
        .then((data) => {
          setItems((prev) => (append ? [...prev, ...data.items] : data.items));
          setTotalCount(data.total_count);
        })
        .catch(() => {})
        .finally(() => setLoading(false));
    },
    [projectId, persona],
  );

  useEffect(() => {
    setLoading(true);
    loadFeed(0, false);
  }, [loadFeed]);

  const hasMore = items.length < totalCount;

  return (
    <div className="flex h-full flex-col">
      {/* Header */}
      <div className="flex items-center justify-between border-b px-4 py-3 shrink-0">
        <h3 className="text-xs font-semibold uppercase tracking-widest text-muted-foreground">
          Work feed
        </h3>
        <span className="text-xs text-muted-foreground">
          {totalCount} nodes
        </span>
      </div>

      {/* Scrollable feed */}
      <div className="flex-1 overflow-y-auto min-h-0">
        <div className="p-4 space-y-3">
          {loading && items.length === 0 && (
            <p className="text-sm text-muted-foreground text-center py-8">Loading...</p>
          )}

          {!loading && items.length === 0 && (
            <p className="text-sm text-muted-foreground text-center py-8">
              No output from this agent yet.
            </p>
          )}

          {items.map((item, i) => {
            if (item.type === "artifact") {
              return (
                <FeedArtifactCard
                  key={`artifact-${item.artifact_id}`}
                  projectId={projectId}
                  artifactId={item.artifact_id!}
                  title={item.title}
                  version={item.version ?? 1}
                  changeSummary={item.change_summary}
                  updatedAt={item.updated_at}
                  index={i}
                />
              );
            }

            return (
              <FeedNodeCard
                key={`node-${item.node_type}-${item.node_id}`}
                nodeType={item.node_type!}
                nodeId={item.node_id!}
                title={item.title}
                body={item.body}
                status={item.status ?? "draft"}
                upstreamCount={item.upstream_count ?? 0}
                downstreamCount={item.downstream_count ?? 0}
                flagCount={item.flag_count ?? 0}
                origin={item.origin}
                originTitle={item.origin_title}
                createdAt={item.created_at}
                index={i}
              />
            );
          })}

          {/* Load more */}
          {hasMore && (
            <div className="text-center py-2">
              <Button
                variant="ghost"
                size="sm"
                className="text-xs"
                onClick={() => loadFeed(items.length, true)}
              >
                Load more
              </Button>
            </div>
          )}

          {/* Stats moved to header pills */}
        </div>
      </div>
    </div>
  );
}
