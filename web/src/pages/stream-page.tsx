import { useState, useEffect, useRef, useCallback } from "react";
import { useParams, useNavigate } from "react-router-dom";
import { api, type StreamItem, type MyWorkData } from "@/lib/api";
import { StreamView } from "@/components/stream/stream-view";
import type { StreamMode } from "@/components/stream/stream-mode-toggle";
import { Skeleton } from "@/components/ui/skeleton";
import { Card, CardContent } from "@/components/ui/card";
import { UniversalInput } from "@/components/chat/universal-input";
import { GraphChatCard } from "@/components/chat/chat-card";
import { useChatState } from "@/hooks/use-chat-state";

function loadMode(): StreamMode {
  const stored = localStorage.getItem("stream-mode");
  return stored === "project" ? "project" : "my-work";
}

type StreamDataShape = {
  right_now: StreamItem[];
  recently: StreamItem[];
  emerging: StreamItem[];
};

export function StreamPage() {
  const { projectId } = useParams<{ projectId: string }>();
  const navigate = useNavigate();
  const pid = Number(projectId);

  const [mode, setMode] = useState<StreamMode>(loadMode);
  const [streamData, setStreamData] = useState<StreamDataShape | null>(null);
  const [myWorkData, setMyWorkData] = useState<MyWorkData | null>(null);
  const [initialLoading, setInitialLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const mountedRef = useRef(true);

  const chat = useChatState(pid, "memory");

  const handleModeChange = (newMode: StreamMode) => {
    setMode(newMode);
    localStorage.setItem("stream-mode", newMode);
  };

  const fetchStream = useCallback(
    (pid: number) =>
      api.getStream(pid).then((data) => {
        if (mountedRef.current) setStreamData(data);
      }),
    [],
  );

  const fetchMyWork = useCallback(
    (pid: number) =>
      api.getMyWork(pid).then((data) => {
        if (mountedRef.current) setMyWorkData(data);
      }),
    [],
  );

  // On mount or project change: fetch BOTH datasets so switching is instant
  useEffect(() => {
    if (!projectId || isNaN(pid)) return;
    mountedRef.current = true;
    setInitialLoading(true);
    setError(null);

    Promise.all([fetchStream(pid), fetchMyWork(pid)])
      .catch((err) => {
        if (mountedRef.current) setError(err.message ?? "Failed to load stream");
      })
      .finally(() => {
        if (mountedRef.current) setInitialLoading(false);
      });

    return () => {
      mountedRef.current = false;
    };
  }, [projectId]);

  // On mode switch: refresh the active dataset in the background (keeps stale data visible)
  useEffect(() => {
    if (!projectId || isNaN(pid) || initialLoading) return;

    if (mode === "project") {
      fetchStream(pid).catch(() => {});
    } else {
      fetchMyWork(pid).catch(() => {});
    }
  }, [mode]);

  if (error && !streamData && !myWorkData) {
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
        <Skeleton className="h-8 w-48" />
        <Skeleton className="h-32 w-full" />
        <Skeleton className="h-8 w-full" />
        <Skeleton className="h-8 w-full" />
        <Skeleton className="h-8 w-full" />
      </div>
    );
  }

  return (
    <div className="relative h-full overflow-hidden">
      <div className="h-full overflow-auto pb-40">
        <StreamView
          mode={mode}
          onModeChange={handleModeChange}
          streamData={streamData}
          myWorkData={myWorkData}
          onNavigateToNode={(nodeType, nodeId) =>
            navigate(`/projects/${projectId}/trail/${nodeType}/${nodeId}`, {
              state: { from: "stream" },
            })
          }
          onNavigateGraph={(nodeType, nodeId, _filterType) =>
            navigate(
              `/projects/${projectId}/graph?focus=${nodeType}-${nodeId}&highlight=${nodeType}-${nodeId}`,
            )
          }
          onAction={(action, item) => {
            console.log("Stream action:", action, item.id);
          }}
          onTalkToStrategist={() =>
            navigate(`/projects/${projectId}/chat/strategist`)
          }
          onUploadResearch={() =>
            navigate(`/projects/${projectId}/sources`)
          }
        />
      </div>

      <UniversalInput
        surface="stream"
        projectId={pid}
        onSubmit={chat.handleChatSubmit}
        currentAgent={chat.activeTab?.agent ?? "memory"}
        onAgentChange={chat.handleAgentChange}
      />

      {chat.chatCardOpen && (
        <GraphChatCard
          tabs={chat.chatTabs}
          activeIndex={chat.activeTabIndex}
          minimized={chat.chatCardMinimized}
          onTabClick={chat.handleTabClick}
          onAddTab={chat.handleAddTab}
          onMinimize={() => chat.setChatCardMinimized((prev) => !prev)}
          onClose={() => chat.setChatCardOpen(false)}
          onGraphCommand={() => {}}
        />
      )}
    </div>
  );
}
