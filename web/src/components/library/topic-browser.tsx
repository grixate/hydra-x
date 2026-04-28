import { useEffect, useMemo, useState } from "react";
import { ArrowDownAZ, ArrowDownNarrowWide, Loader2, Tag } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { ScrollArea } from "@/components/ui/scroll-area";
import { api } from "@/lib/api";
import type { GraphData, GraphDataNode } from "@/types";

// Library spec §7: Topic browser. Lists topics with source counts; sortable
// by count (find dense topics) or by sparsity (find gaps). Clicking a topic
// will narrow the graph view in a future iteration; for now it dispatches a
// `hydra:focus-topic` event the LibraryPage can pick up.

type SortMode = "count_desc" | "sparsity";

export function TopicBrowser({
  projectId,
  onFocusTopic,
}: {
  projectId: number;
  onFocusTopic?: (topicGraphId: string) => void;
}) {
  const [data, setData] = useState<GraphData | null>(null);
  const [loading, setLoading] = useState(true);
  const [sort, setSort] = useState<SortMode>("count_desc");

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    api
      .getLibraryGraphData(projectId)
      .then((d) => {
        if (cancelled) return;
        setData(d);
      })
      .catch(() => {
        if (!cancelled) setData({ nodes: [], edges: [], flags: [], density: {} });
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [projectId]);

  const topics = useMemo(() => {
    if (!data) return [];

    // Source counts per topic via `is_about` edges from sources.
    const sourceCounts = new Map<string, number>();
    for (const edge of data.edges) {
      if (edge.kind !== "is_about") continue;
      // is_about edges go source → topic (or excerpt → topic).
      const sourceNode = data.nodes.find((n) => n.id === edge.source);
      if (sourceNode?.node_type !== "source") continue;
      sourceCounts.set(edge.target, (sourceCounts.get(edge.target) ?? 0) + 1);
    }

    return data.nodes
      .filter((n) => n.node_type === "topic")
      .map((topic) => ({
        topic,
        sourceCount: sourceCounts.get(topic.id) ?? 0,
      }))
      .sort((a, b) =>
        sort === "count_desc"
          ? b.sourceCount - a.sourceCount
          : a.sourceCount - b.sourceCount,
      );
  }, [data, sort]);

  if (loading) {
    return (
      <div className="flex h-64 items-center justify-center">
        <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
      </div>
    );
  }

  if (topics.length === 0) {
    return (
      <Card>
        <CardContent className="py-12 text-center">
          <Tag className="mx-auto mb-3 h-6 w-6 text-muted-foreground" />
          <p className="text-sm font-medium">No topics yet</p>
          <p className="mt-1 text-xs text-muted-foreground">
            Topics are extracted automatically as new sources are ingested.
          </p>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader className="pb-4">
        <div className="flex items-end justify-between">
          <div>
            <p className="text-[10px] font-bold uppercase tracking-[0.3em] text-muted-foreground">
              Library
            </p>
            <CardTitle className="mt-2">Topics</CardTitle>
          </div>
          <div className="flex items-center gap-1.5">
            <Button
              size="xs"
              variant={sort === "count_desc" ? "default" : "outline"}
              onClick={() => setSort("count_desc")}
            >
              <ArrowDownNarrowWide className="h-3 w-3" />
              Most sources
            </Button>
            <Button
              size="xs"
              variant={sort === "sparsity" ? "default" : "outline"}
              onClick={() => setSort("sparsity")}
            >
              <ArrowDownAZ className="h-3 w-3" />
              Sparse first
            </Button>
          </div>
        </div>
      </CardHeader>

      <CardContent>
        <ScrollArea className="h-[28rem] pr-2">
          <div className="space-y-2">
            {topics.map(({ topic, sourceCount }) => (
              <TopicRow
                key={topic.id}
                topic={topic}
                sourceCount={sourceCount}
                onClick={() => onFocusTopic?.(topic.id)}
              />
            ))}
          </div>
        </ScrollArea>
      </CardContent>
    </Card>
  );
}

function TopicRow({
  topic,
  sourceCount,
  onClick,
}: {
  topic: GraphDataNode;
  sourceCount: number;
  onClick?: () => void;
}) {
  // Spec §8.1 — sparse-topic threshold default N=2. Below this, the topic is
  // a gap candidate.
  const sparse = sourceCount < 2;

  return (
    <button
      type="button"
      onClick={onClick}
      className="flex w-full items-center gap-3 rounded-md border bg-background px-3 py-2 text-left transition-colors hover:border-foreground hover:bg-muted/40"
    >
      <Tag className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <span className="truncate text-sm font-medium">{topic.title}</span>
          {topic.granularity ? (
            <Badge variant="neutral" className="text-[9px] uppercase tracking-wider">
              {topic.granularity}
            </Badge>
          ) : null}
        </div>
        {topic.body ? (
          <p className="mt-0.5 truncate text-xs text-muted-foreground">{topic.body}</p>
        ) : null}
      </div>
      <span
        className={`shrink-0 text-xs ${
          sparse ? "text-amber-600" : "text-muted-foreground"
        }`}
      >
        {sourceCount} source{sourceCount === 1 ? "" : "s"}
        {sparse ? " · sparse" : ""}
      </span>
    </button>
  );
}
