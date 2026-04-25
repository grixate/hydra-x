import { useLocation, useParams, Outlet } from "react-router-dom";
import { ProjectRail } from "./project-rail";
import { WorkspaceSidebar } from "./workspace-sidebar";
import { ToastContainer } from "@/components/ui/toast-notification";
import { TooltipProvider } from "@/components/ui/tooltip";
import {
  AgentChatPane,
  CHAT_PANE_OPEN_EVENT,
  classifySurface,
  dispatchAgentChatPaneSwitch,
  dispatchChatPaneOpen,
  onboardingOpeningKey,
  setPendingSend,
  type ChatSurface,
} from "@/components/chat/agent-chat-pane";
import { CollapsedChatBar } from "@/components/chat/collapsed-chat-bar";
import { ForkScreen, type OnboardingScenario } from "@/components/onboarding/fork-screen";
import { ExploreCarousel } from "@/components/onboarding/explore-carousel";
import { IdeaPrompt } from "@/components/onboarding/idea-prompt";
import { MaterialsDropZone } from "@/components/onboarding/materials-drop-zone";
import { useOnboarding } from "@/hooks/use-onboarding";
import { api } from "@/lib/api";
import type { Project } from "@/types";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { motion } from "motion/react";

const DEFAULT_PANE_WIDTH = 480;
const MIN_PANE_WIDTH = 360;
const MIN_MAIN_WIDTH = 480;

const MORPH_TRANSITION = {
  type: "spring" as const,
  stiffness: 320,
  damping: 34,
  mass: 0.9,
};

function collapsedKey(surface: ChatSurface) {
  return `app-chat:collapsed:${surface}`;
}

function widthKey(surface: ChatSurface) {
  return `app-chat:width:${surface}`;
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

function readStoredWidth(surface: ChatSurface): number {
  if (typeof window === "undefined") return DEFAULT_PANE_WIDTH;
  try {
    const raw = window.localStorage.getItem(widthKey(surface));
    const parsed = raw ? parseFloat(raw) : NaN;
    if (!Number.isFinite(parsed)) return DEFAULT_PANE_WIDTH;
    return parsed;
  } catch {
    return DEFAULT_PANE_WIDTH;
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

  const { status: onboarding, markCompleted } = useOnboarding(pid);
  const [project, setProject] = useState<Project | null>(null);
  const [forkChoice, setForkChoice] = useState<OnboardingScenario | null>(null);

  useEffect(() => {
    if (!pid) {
      setProject(null);
      return;
    }
    let cancelled = false;
    api
      .getProject(pid)
      .then((p) => {
        if (!cancelled) setProject(p);
      })
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, [pid]);

  const handleForkSelect = useCallback(
    async (scenario: OnboardingScenario) => {
      if (scenario === "just_start" || scenario === "skip") {
        if (pid !== null) {
          try {
            window.localStorage.setItem(onboardingOpeningKey(pid), scenario);
          } catch {
            /* ignore */
          }
        }
        await markCompleted();
        dispatchChatPaneOpen();
        dispatchAgentChatPaneSwitch("strategist");
        return;
      }

      if (scenario === "explore" || scenario === "idea" || scenario === "materials") {
        setForkChoice(scenario);
        return;
      }

      await markCompleted();
    },
    [markCompleted, pid],
  );

  const handleCarouselDismiss = useCallback(async () => {
    await markCompleted();
    setForkChoice(null);
  }, [markCompleted]);

  const handleIdeaSubmit = useCallback(
    async (text: string) => {
      if (pid !== null) {
        setPendingSend(pid, text);
      }
      await markCompleted();
      setForkChoice(null);
      dispatchChatPaneOpen();
      dispatchAgentChatPaneSwitch("strategist");
    },
    [markCompleted, pid],
  );

  const handleIdeaBack = useCallback(() => {
    setForkChoice(null);
  }, []);

  const handleMaterialsComplete = useCallback(
    async (_count: number) => {
      if (pid !== null) {
        try {
          window.localStorage.setItem(onboardingOpeningKey(pid), "materials");
        } catch {
          /* ignore */
        }
      }
      await markCompleted();
      setForkChoice(null);
      dispatchChatPaneOpen();
      dispatchAgentChatPaneSwitch("strategist");
    },
    [markCompleted, pid],
  );

  const showFork =
    pid !== null && onboarding !== null && !onboarding.has_completed_first_session;

  const [chatCollapsed, setChatCollapsed] = useState<boolean>(() =>
    readStoredCollapsed(surface),
  );
  const [paneWidth, setPaneWidth] = useState<number>(() => readStoredWidth(surface));
  const [dragging, setDragging] = useState(false);

  // Track which surface the current state belongs to, so a surface change
  // doesn't write the previous surface's value under the new surface's key
  // before the new value lands.
  const syncedSurfaceRef = useRef(surface);

  useEffect(() => {
    if (syncedSurfaceRef.current !== surface) {
      syncedSurfaceRef.current = surface;
      setChatCollapsed(readStoredCollapsed(surface));
      setPaneWidth(readStoredWidth(surface));
      return;
    }
    try {
      window.localStorage.setItem(collapsedKey(surface), chatCollapsed ? "1" : "0");
      window.localStorage.setItem(widthKey(surface), String(paneWidth));
    } catch {
      // Ignore quota / privacy-mode failures.
    }
  }, [chatCollapsed, paneWidth, surface]);

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

  useEffect(() => {
    function onOpen() {
      setChatCollapsed(false);
    }
    window.addEventListener(CHAT_PANE_OPEN_EVENT, onOpen);
    return () => window.removeEventListener(CHAT_PANE_OPEN_EVENT, onOpen);
  }, []);

  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!dragging) return;
    const el = containerRef.current;
    if (!el) return;

    function onMove(e: MouseEvent) {
      if (!el) return;
      const rect = el.getBoundingClientRect();
      const fromRight = rect.right - e.clientX;
      const maxWidth = Math.max(MIN_PANE_WIDTH, rect.width - MIN_MAIN_WIDTH);
      const next = Math.max(MIN_PANE_WIDTH, Math.min(maxWidth, fromRight));
      setPaneWidth(next);
    }
    function onUp() {
      setDragging(false);
    }

    window.addEventListener("mousemove", onMove);
    window.addEventListener("mouseup", onUp);
    document.body.style.userSelect = "none";
    document.body.style.cursor = "col-resize";

    return () => {
      window.removeEventListener("mousemove", onMove);
      window.removeEventListener("mouseup", onUp);
      document.body.style.userSelect = "";
      document.body.style.cursor = "";
    };
  }, [dragging]);

  const expandChat = useCallback(() => setChatCollapsed(false), []);
  const paneOpen = !!pid && !chatCollapsed;

  // While dragging, skip the spring so width tracks the cursor 1:1.
  const marginTransition = dragging ? { duration: 0 } : MORPH_TRANSITION;

  if (showFork && forkChoice === "explore") {
    return <ExploreCarousel onDismiss={handleCarouselDismiss} />;
  }

  if (showFork && forkChoice === "idea") {
    return (
      <IdeaPrompt
        projectName={project?.name ?? ""}
        onSubmit={handleIdeaSubmit}
        onBack={handleIdeaBack}
      />
    );
  }

  if (showFork && forkChoice === "materials" && pid !== null) {
    return (
      <MaterialsDropZone
        projectName={project?.name ?? ""}
        projectId={pid}
        onComplete={handleMaterialsComplete}
        onBack={() => setForkChoice(null)}
      />
    );
  }

  if (showFork) {
    return (
      <ForkScreen
        projectName={project?.name ?? ""}
        onSelect={handleForkSelect}
      />
    );
  }

  return (
    <TooltipProvider delayDuration={200}>
      <div className="flex h-screen bg-background text-foreground">
        <ProjectRail />
        <WorkspaceSidebar />
        <div ref={containerRef} className="flex-1 min-w-0 relative">
          {/* Main content — stays mounted across chat toggles so no remount flash. */}
          <motion.div
            className="h-full"
            animate={{ marginRight: paneOpen ? paneWidth : 0 }}
            transition={marginTransition}
          >
            <main className="h-full overflow-auto">
              <Outlet />
            </main>
          </motion.div>

          {/* Shared-layout morph between the collapsed pill and the open pane. */}
          {pid &&
            (paneOpen ? (
              <motion.div
                key="chat-dock-pane"
                // Drop layoutId while dragging so the shared-layout spring
                // doesn't kick in on every width tick and distort content.
                layoutId={dragging ? undefined : "chat-dock"}
                className="absolute top-0 right-0 bottom-0 z-30 border-l bg-background shadow-xl"
                style={{ width: paneWidth }}
                transition={MORPH_TRANSITION}
              >
                {/* Drag handle on the pane's left edge. */}
                <div
                  role="separator"
                  aria-orientation="vertical"
                  onMouseDown={(e) => {
                    e.preventDefault();
                    setDragging(true);
                  }}
                  onDoubleClick={() => setPaneWidth(DEFAULT_PANE_WIDTH)}
                  className="group absolute top-0 bottom-0 -left-1 z-40 w-2 cursor-col-resize"
                  title="Drag to resize · double-click to reset"
                >
                  <div className="pointer-events-none absolute left-1/2 top-1/2 h-8 w-1 -translate-x-1/2 -translate-y-1/2 rounded-full bg-border transition-colors group-hover:bg-muted-foreground/40 group-active:bg-muted-foreground/60" />
                </div>

                <motion.div
                  className="h-full"
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  transition={{ duration: 0.18, delay: 0.12 }}
                >
                  <AgentChatPane />
                </motion.div>
              </motion.div>
            ) : (
              <motion.div
                key="chat-dock-pill"
                layoutId="chat-dock"
                className="absolute bottom-4 right-4 z-40"
                transition={MORPH_TRANSITION}
              >
                <CollapsedChatBar projectId={pid} onExpand={expandChat} />
              </motion.div>
            ))}
        </div>
        <ToastContainer />
      </div>
    </TooltipProvider>
  );
}
