import { useState, useRef, useCallback, useEffect } from "react";
import { PanelLeftOpen, PanelRightOpen } from "lucide-react";

interface ResizableLayoutProps {
  left: React.ReactNode;
  right: React.ReactNode;
  defaultSplit?: number;
  minLeftWidth?: number;
  minRightWidth?: number;
  storageKey?: string;
  rightCollapsed?: boolean;
  onRightCollapsedChange?: (collapsed: boolean) => void;
  collapsedRail?: React.ReactNode;
  bindGlobalShortcut?: boolean;
}

export function ResizableLayout({
  left,
  right,
  defaultSplit = 0.55,
  minLeftWidth = 320,
  minRightWidth = 320,
  storageKey,
  rightCollapsed: controlledCollapsed,
  onRightCollapsedChange,
  collapsedRail,
  bindGlobalShortcut = true,
}: ResizableLayoutProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [split, setSplit] = useState(() => {
    if (storageKey) {
      const saved = localStorage.getItem(`pane-split-${storageKey}`);
      if (saved) return parseFloat(saved);
    }
    return defaultSplit;
  });
  const [dragging, setDragging] = useState(false);
  const [collapsed, setCollapsed] = useState<"left" | "right" | null>(
    controlledCollapsed ? "right" : null,
  );
  const prevSplitRef = useRef(split);

  // When storageKey changes (e.g. surface navigation), re-read the persisted
  // split for the new key so each surface keeps its own width.
  useEffect(() => {
    if (!storageKey) return;
    const saved = localStorage.getItem(`pane-split-${storageKey}`);
    const next = saved ? parseFloat(saved) : defaultSplit;
    if (Number.isFinite(next)) {
      setSplit(next);
      prevSplitRef.current = next;
    }
  }, [storageKey, defaultSplit]);

  useEffect(() => {
    if (controlledCollapsed !== undefined) {
      setCollapsed(controlledCollapsed ? "right" : null);
    }
  }, [controlledCollapsed]);

  useEffect(() => {
    if (storageKey && !collapsed) {
      localStorage.setItem(`pane-split-${storageKey}`, String(split));
    }
  }, [split, storageKey, collapsed]);

  const handleMouseDown = useCallback(() => {
    prevSplitRef.current = split;
    setDragging(true);
  }, [split]);

  useEffect(() => {
    if (!dragging) return;

    const handleMouseMove = (e: MouseEvent) => {
      if (!containerRef.current) return;
      const rect = containerRef.current.getBoundingClientRect();
      const x = e.clientX - rect.left;
      const ratio = x / rect.width;

      const collapseLeftThreshold = minLeftWidth / rect.width * 0.5;
      const collapseRightThreshold = 1 - (minRightWidth / rect.width * 0.5);

      if (ratio < collapseLeftThreshold) {
        setCollapsed((prev) => {
          if (prev !== "left") onRightCollapsedChange?.(false);
          return "left";
        });
        return;
      }
      if (ratio > collapseRightThreshold) {
        setCollapsed((prev) => {
          if (prev !== "right") onRightCollapsedChange?.(true);
          return "right";
        });
        return;
      }

      setCollapsed((prev) => {
        if (prev !== null) onRightCollapsedChange?.(false);
        return null;
      });
      const newSplit = Math.max(
        minLeftWidth / rect.width,
        Math.min(1 - minRightWidth / rect.width, ratio),
      );
      setSplit(newSplit);
    };

    const handleMouseUp = () => setDragging(false);

    document.addEventListener("mousemove", handleMouseMove);
    document.addEventListener("mouseup", handleMouseUp);
    document.body.style.userSelect = "none";
    document.body.style.cursor = "col-resize";

    return () => {
      document.removeEventListener("mousemove", handleMouseMove);
      document.removeEventListener("mouseup", handleMouseUp);
      document.body.style.userSelect = "";
      document.body.style.cursor = "";
    };
  }, [dragging, minLeftWidth, minRightWidth, onRightCollapsedChange]);

  const handleDoubleClick = useCallback(() => {
    if (collapsed) {
      setCollapsed(null);
      onRightCollapsedChange?.(false);
      setSplit(prevSplitRef.current || defaultSplit);
    } else {
      prevSplitRef.current = split;
      setCollapsed("right");
      onRightCollapsedChange?.(true);
    }
  }, [collapsed, split, defaultSplit, onRightCollapsedChange]);

  useEffect(() => {
    if (!bindGlobalShortcut) return;
    function onKeyDown(e: KeyboardEvent) {
      const isToggle = (e.metaKey || e.ctrlKey) && (e.key === "j" || e.key === "J");
      if (!isToggle) return;
      e.preventDefault();
      if (collapsed === "right") {
        setCollapsed(null);
        onRightCollapsedChange?.(false);
        setSplit(prevSplitRef.current || defaultSplit);
      } else {
        prevSplitRef.current = split;
        setCollapsed("right");
        onRightCollapsedChange?.(true);
      }
    }
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [collapsed, split, defaultSplit, onRightCollapsedChange, bindGlobalShortcut]);

  const leftWidth = collapsed === "left" ? "0%" : collapsed === "right" ? "100%" : `${split * 100}%`;
  const rightWidth = collapsed === "right" ? "0%" : collapsed === "left" ? "100%" : `${(1 - split) * 100}%`;

  const transitionStyle = dragging ? "none" : "width 0.2s ease-out";

  return (
    <div ref={containerRef} className="relative flex h-full min-h-0">
      <div
        className="h-full overflow-hidden"
        style={{ width: leftWidth, transition: transitionStyle }}
      >
        <div className={collapsed === "left" ? "invisible h-full" : "h-full"}>
          {left}
        </div>
      </div>

      {!collapsed && (
        <div
          className="relative w-4 shrink-0 cursor-col-resize flex items-center justify-center group"
          onMouseDown={handleMouseDown}
          onDoubleClick={handleDoubleClick}
        >
          <div className="absolute inset-y-0 left-1/2 w-px -translate-x-1/2 bg-border" />
          <div className="relative z-10 h-8 w-1.5 rounded-full bg-border group-hover:bg-muted-foreground/40 group-active:bg-muted-foreground/60 transition-colors" />
        </div>
      )}

      <div
        className="h-full overflow-hidden"
        style={{ width: rightWidth, transition: transitionStyle }}
      >
        <div className={collapsed === "right" ? "invisible h-full" : "h-full"}>
          {right}
        </div>
      </div>

      {collapsed === "right" && (
        collapsedRail ? (
          <div className="absolute right-0 top-0 bottom-0">
            <button
              type="button"
              className="h-full"
              onClick={() => {
                setCollapsed(null);
                onRightCollapsedChange?.(false);
                setSplit(prevSplitRef.current || defaultSplit);
              }}
              title="Expand (⌘J)"
            >
              {collapsedRail}
            </button>
          </div>
        ) : (
          <button
            className="absolute right-0 top-1/2 -translate-y-1/2 rounded-l-md border border-r-0 bg-background p-1.5 text-muted-foreground hover:text-foreground transition-colors"
            onClick={() => {
              setCollapsed(null);
              onRightCollapsedChange?.(false);
              setSplit(prevSplitRef.current || defaultSplit);
            }}
            title="Show right pane (⌘J)"
          >
            <PanelLeftOpen className="h-4 w-4" />
          </button>
        )
      )}

      {collapsed === "left" && (
        <button
          className="absolute left-0 top-1/2 -translate-y-1/2 rounded-r-md border border-l-0 bg-background p-1.5 text-muted-foreground hover:text-foreground transition-colors"
          onClick={() => {
            setCollapsed(null);
            onRightCollapsedChange?.(false);
            setSplit(prevSplitRef.current || defaultSplit);
          }}
          title="Show left pane"
        >
          <PanelRightOpen className="h-4 w-4" />
        </button>
      )}
    </div>
  );
}
