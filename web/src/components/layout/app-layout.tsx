import { useLocation, useParams } from "react-router-dom";
import { Outlet } from "react-router-dom";
import { ProjectRail } from "./project-rail";
import { WorkspaceSidebar } from "./workspace-sidebar";
import { ResizableLayout } from "./resizable-layout";
import { ToastContainer } from "@/components/ui/toast-notification";
import { TooltipProvider } from "@/components/ui/tooltip";
import {
  AgentChatPane,
  classifySurface,
  type ChatSurface,
} from "@/components/chat/agent-chat-pane";
import { CollapsedChatBar } from "@/components/chat/collapsed-chat-bar";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";

function collapsedKey(surface: ChatSurface) {
  return `app-chat:collapsed:${surface}`;
}

function splitKey(surface: ChatSurface) {
  return `app-chat:${surface}`;
}

function readStoredCollapsed(surface: ChatSurface): boolean {
  if (typeof window === "undefined") return true;
  try {
    const raw = window.localStorage.getItem(collapsedKey(surface));
    if (raw === null) return true;
    return raw === "1";
  } catch {
    return true;
  }
}

export function AppLayout() {
  const { projectId } = useParams<{ projectId: string }>();
  const pid = projectId ? Number(projectId) : null;
  const location = useLocation();

  const surface = useMemo(
    () => classifySurface(location.pathname, projectId),
    [location.pathname, projectId],
  );

  const [chatCollapsed, setChatCollapsed] = useState<boolean>(() =>
    readStoredCollapsed(surface),
  );

  // Track which surface the current `chatCollapsed` value belongs to, so a
  // surface change doesn't write the previous surface's value under the new
  // surface's key before the new value lands.
  const syncedSurfaceRef = useRef(surface);

  useEffect(() => {
    if (syncedSurfaceRef.current !== surface) {
      syncedSurfaceRef.current = surface;
      setChatCollapsed(readStoredCollapsed(surface));
      return;
    }
    try {
      window.localStorage.setItem(collapsedKey(surface), chatCollapsed ? "1" : "0");
    } catch {
      // Ignore quota / privacy-mode failures.
    }
  }, [chatCollapsed, surface]);

  // ⌘J (Ctrl+J) toggles the chat pane globally. ResizableLayout has its
  // own binding disabled so we don't double-toggle.
  useEffect(() => {
    function onKeyDown(e: KeyboardEvent) {
      if (!(e.metaKey || e.ctrlKey)) return;
      if (e.key !== "j" && e.key !== "J") return;
      e.preventDefault();
      setChatCollapsed((prev) => !prev);
    }
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, []);

  const expandChat = useCallback(() => setChatCollapsed(false), []);

  return (
    <TooltipProvider delayDuration={200}>
    <div className="flex h-screen bg-background text-foreground">
      <ProjectRail />
      <WorkspaceSidebar />
      <div className="flex-1 min-w-0 relative">
        {pid && !chatCollapsed ? (
          <ResizableLayout
            storageKey={splitKey(surface)}
            defaultSplit={0.62}
            minLeftWidth={480}
            minRightWidth={360}
            bindGlobalShortcut={false}
            rightCollapsed={false}
            onRightCollapsedChange={(collapsed) => setChatCollapsed(collapsed)}
            left={
              <main className="h-full overflow-auto">
                <Outlet />
              </main>
            }
            right={<AgentChatPane />}
          />
        ) : (
          <main className="h-full overflow-auto">
            <Outlet />
          </main>
        )}

        {pid && chatCollapsed && (
          <div className="pointer-events-none absolute bottom-4 right-4 z-40">
            <CollapsedChatBar projectId={pid} onExpand={expandChat} />
          </div>
        )}
      </div>
      <ToastContainer />
    </div>
    </TooltipProvider>
  );
}
