import { useCallback, useEffect, useState } from "react";
import { useParams, useSearchParams } from "react-router-dom";

import { GraphView } from "@/components/graph/graph-view";
import { LibraryEmptyOverlay } from "@/components/library/library-empty-overlay";
import {
  LibraryViewSelector,
  type LibraryView,
} from "@/components/library/library-view-selector";
import { TopicBrowser } from "@/components/library/topic-browser";
import { SourceList } from "@/components/sources/source-list";
import { Skeleton } from "@/components/ui/skeleton";
import { api } from "@/lib/api";
import type { Source } from "@/types";

// Library spec §5 + §7 — graph view is the default Library surface. The
// view selector lets users switch to a flat source list or a topic browser
// without losing selection or filter state. Switches survive reload via the
// `?view=` query param.

export function LibraryPage() {
  const { projectId } = useParams<{ projectId: string }>();
  const pid = Number(projectId);
  const [searchParams, setSearchParams] = useSearchParams();
  const view = (searchParams.get("view") as LibraryView | null) ?? "graph";

  const [sourceCount, setSourceCount] = useState<number | null>(null);

  const refreshCount = useCallback(async () => {
    if (!pid || isNaN(pid)) return;
    try {
      const data = await api.getLibraryGraphData(pid);
      const count = data.nodes.filter((n) => n.node_type === "source").length;
      setSourceCount(count);
    } catch {
      setSourceCount(0);
    }
  }, [pid]);

  useEffect(() => {
    void refreshCount();
  }, [refreshCount]);

  const setView = useCallback(
    (next: LibraryView) => {
      const params = new URLSearchParams(searchParams);
      if (next === "graph") {
        params.delete("view");
      } else {
        params.set("view", next);
      }
      setSearchParams(params, { replace: true });
    },
    [searchParams, setSearchParams],
  );

  if (!pid || isNaN(pid)) {
    return (
      <div className="flex h-full items-center justify-center">
        <p className="text-sm text-muted-foreground">No project selected.</p>
      </div>
    );
  }

  if (sourceCount === null) {
    return (
      <div className="flex h-full items-center justify-center">
        <Skeleton className="h-96 w-96 rounded-xl" />
      </div>
    );
  }

  return (
    <div className="relative h-full w-full">
      {view === "graph" ? (
        <>
          <GraphView projectId={pid} lens="library" />
          {/* Spec §5.4 — overlay collapses to a status pill at threshold. */}
          <div className="pointer-events-none absolute right-4 top-20 z-30 flex flex-col items-end gap-2">
            <LibraryEmptyOverlay
              projectId={pid}
              sourceCount={sourceCount}
              onSourceAdded={refreshCount}
            />
          </div>
        </>
      ) : (
        <div className="h-full overflow-y-auto px-4 py-6">
          <div className="mx-auto max-w-4xl">
            {view === "list" ? <ListPane projectId={pid} /> : null}
            {view === "topics" ? (
              <TopicBrowser
                projectId={pid}
                onFocusTopic={(topicGraphId) => {
                  // Switch back to graph and let the focus param drive the
                  // existing GraphView focus path.
                  const params = new URLSearchParams(searchParams);
                  params.delete("view");
                  params.set("focus", topicGraphId);
                  setSearchParams(params, { replace: true });
                }}
              />
            ) : null}
          </div>
        </div>
      )}

      {/* View selector — top-left. Sits above the graph but below other
          chrome (smart views, filter chips). */}
      <div className="pointer-events-none absolute left-4 top-4 z-30">
        <LibraryViewSelector active={view} onChange={setView} />
      </div>
    </div>
  );
}

function ListPane({ projectId }: { projectId: number }) {
  const [sources, setSources] = useState<Source[] | null>(null);
  const [selectedId, setSelectedId] = useState<number | null>(null);

  useEffect(() => {
    let cancelled = false;
    api
      .listLibraryRecent(projectId, 200)
      .then((s) => {
        if (!cancelled) setSources(s);
      })
      .catch(() => {
        if (!cancelled) setSources([]);
      });
    return () => {
      cancelled = true;
    };
  }, [projectId]);

  if (sources === null) {
    return (
      <div className="flex h-64 items-center justify-center">
        <Skeleton className="h-48 w-full rounded-xl" />
      </div>
    );
  }

  return (
    <SourceList
      sources={sources}
      selectedSourceId={selectedId}
      onSelectSource={setSelectedId}
    />
  );
}
