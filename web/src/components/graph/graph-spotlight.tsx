import { useState, useEffect, useRef, useMemo, useCallback } from "react";
import { useNavigate, useParams } from "react-router-dom";
import type { GraphDataNode } from "@/types";
import { NODE_COLORS } from "./graph-constants";
import type { SmartView } from "./graph-smart-views";
import { Search, Zap, BarChart3, GitBranch, Clock, AlertTriangle, Link2, Globe, Maximize2, LayoutDashboard, Activity } from "lucide-react";
import { cn } from "@/lib/utils";

interface SpotlightItem {
  id: string;
  type: "node" | "action" | "navigate";
  label: string;
  description?: string;
  icon?: typeof Search;
  color?: string;
  shortcut?: string;
  onSelect: () => void;
}

interface GraphSpotlightProps {
  open: boolean;
  onClose: () => void;
  nodes: GraphDataNode[];
  onFocusNode: (nodeId: string) => void;
  onSmartView: (view: SmartView | null) => void;
  onFitToScreen: () => void;
  onSearch: (query: string) => void;
}

export function GraphSpotlight({
  open,
  onClose,
  nodes,
  onFocusNode,
  onSmartView,
  onFitToScreen,
  onSearch,
}: GraphSpotlightProps) {
  const navigate = useNavigate();
  const { projectId } = useParams<{ projectId: string }>();
  const [query, setQuery] = useState("");
  const [selectedIndex, setSelectedIndex] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (open) {
      setQuery("");
      setSelectedIndex(0);
      setTimeout(() => inputRef.current?.focus(), 50);
    }
  }, [open]);

  // Build items list
  const items = useMemo((): SpotlightItem[] => {
    const result: SpotlightItem[] = [];
    const q = query.toLowerCase();

    // Node results
    const matchingNodes = q
      ? nodes.filter((n) => n.title.toLowerCase().includes(q)).slice(0, 8)
      : nodes.slice(0, 5);

    for (const node of matchingNodes) {
      result.push({
        id: node.id,
        type: "node",
        label: node.title,
        description: node.node_type.replace(/_/g, " "),
        color: NODE_COLORS[node.node_type] ?? NODE_COLORS.default,
        onSelect: () => {
          onFocusNode(node.id);
          onClose();
        },
      });
    }

    // Actions (show when no query or query matches)
    if (!q || "next actions".includes(q)) {
      result.push({
        id: "sv-next",
        type: "action",
        label: "Next actions view",
        icon: Zap,
        shortcut: "⌘⇧1",
        onSelect: () => { onSmartView("next_actions"); onClose(); },
      });
    }
    if (!q || "coverage".includes(q)) {
      result.push({
        id: "sv-coverage",
        type: "action",
        label: "Coverage view",
        icon: BarChart3,
        shortcut: "⌘⇧2",
        onSelect: () => { onSmartView("coverage"); onClose(); },
      });
    }
    if (!q || "orphans".includes(q)) {
      result.push({
        id: "sv-orphans",
        type: "action",
        label: "Show orphans",
        icon: Link2,
        shortcut: "⌘⇧3",
        onSelect: () => { onSmartView("orphans"); onClose(); },
      });
    }
    if (!q || "fit screen zoom".includes(q)) {
      result.push({
        id: "act-fit",
        type: "action",
        label: "Fit to screen",
        icon: Maximize2,
        shortcut: "F",
        onSelect: () => { onFitToScreen(); onClose(); },
      });
    }
    if (!q || "all nodes reset".includes(q)) {
      result.push({
        id: "sv-all",
        type: "action",
        label: "Show all nodes",
        icon: Globe,
        onSelect: () => { onSmartView(null); onClose(); },
      });
    }

    // Navigation
    if (!q || "board tasks".includes(q)) {
      result.push({
        id: "nav-board",
        type: "navigate",
        label: "Go to Board",
        icon: LayoutDashboard,
        shortcut: "B",
        onSelect: () => { navigate(`/projects/${projectId}/board`); onClose(); },
      });
    }
    if (!q || "stream activity".includes(q)) {
      result.push({
        id: "nav-stream",
        type: "navigate",
        label: "Go to Stream",
        icon: Activity,
        shortcut: "S",
        onSelect: () => { navigate(`/projects/${projectId}/stream`); onClose(); },
      });
    }

    return result;
  }, [query, nodes, onFocusNode, onSmartView, onFitToScreen, onClose, navigate, projectId]);

  // Clamp selected index
  useEffect(() => {
    setSelectedIndex(0);
  }, [query]);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (e.key === "Escape") {
        onClose();
      } else if (e.key === "ArrowDown") {
        e.preventDefault();
        setSelectedIndex((i) => Math.min(i + 1, items.length - 1));
      } else if (e.key === "ArrowUp") {
        e.preventDefault();
        setSelectedIndex((i) => Math.max(i - 1, 0));
      } else if (e.key === "Enter") {
        e.preventDefault();
        items[selectedIndex]?.onSelect();
      }
    },
    [items, selectedIndex, onClose],
  );

  // Also apply search highlighting as user types
  useEffect(() => {
    onSearch(query);
  }, [query]);

  if (!open) return null;

  // Group items by type
  const nodeItems = items.filter((i) => i.type === "node");
  const actionItems = items.filter((i) => i.type === "action");
  const navItems = items.filter((i) => i.type === "navigate");

  let flatIndex = 0;

  return (
    <>
      {/* Backdrop */}
      <div
        className="fixed inset-0 z-40 bg-black/20 backdrop-blur-[2px]"
        onClick={onClose}
      />

      {/* Spotlight */}
      <div className="fixed left-1/2 top-[20%] z-50 w-full max-w-lg -translate-x-1/2">
        <div className="rounded-2xl border bg-background shadow-2xl overflow-hidden">
          {/* Search input */}
          <div className="flex items-center gap-3 border-b px-4 py-3">
            <Search className="h-5 w-5 shrink-0 text-muted-foreground" />
            <input
              ref={inputRef}
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              onKeyDown={handleKeyDown}
              placeholder="Search nodes, actions, views..."
              className="flex-1 bg-transparent text-sm outline-none placeholder:text-muted-foreground"
            />
            <kbd className="rounded bg-muted px-1.5 py-0.5 text-[10px] text-muted-foreground font-mono">
              ⌘K
            </kbd>
          </div>

          {/* Results */}
          <div className="max-h-[360px] overflow-y-auto p-2">
            {items.length === 0 && (
              <p className="py-6 text-center text-sm text-muted-foreground">
                No results
              </p>
            )}

            {nodeItems.length > 0 && (
              <div className="mb-1">
                <p className="px-2 py-1 text-[10px] font-semibold uppercase tracking-wider text-muted-foreground">
                  Nodes
                </p>
                {nodeItems.map((item) => {
                  const idx = flatIndex++;
                  return (
                    <SpotlightRow
                      key={item.id}
                      item={item}
                      selected={idx === selectedIndex}
                      onSelect={item.onSelect}
                      onHover={() => setSelectedIndex(idx)}
                    />
                  );
                })}
              </div>
            )}

            {actionItems.length > 0 && (
              <div className="mb-1">
                <p className="px-2 py-1 text-[10px] font-semibold uppercase tracking-wider text-muted-foreground">
                  Actions
                </p>
                {actionItems.map((item) => {
                  const idx = flatIndex++;
                  return (
                    <SpotlightRow
                      key={item.id}
                      item={item}
                      selected={idx === selectedIndex}
                      onSelect={item.onSelect}
                      onHover={() => setSelectedIndex(idx)}
                    />
                  );
                })}
              </div>
            )}

            {navItems.length > 0 && (
              <div className="mb-1">
                <p className="px-2 py-1 text-[10px] font-semibold uppercase tracking-wider text-muted-foreground">
                  Navigate
                </p>
                {navItems.map((item) => {
                  const idx = flatIndex++;
                  return (
                    <SpotlightRow
                      key={item.id}
                      item={item}
                      selected={idx === selectedIndex}
                      onSelect={item.onSelect}
                      onHover={() => setSelectedIndex(idx)}
                    />
                  );
                })}
              </div>
            )}
          </div>

          {/* Footer */}
          <div className="flex items-center justify-between border-t px-4 py-2 text-[10px] text-muted-foreground">
            <div className="flex items-center gap-3">
              <span>
                <kbd className="rounded bg-muted px-1 py-0.5 font-mono">↑↓</kbd> navigate
              </span>
              <span>
                <kbd className="rounded bg-muted px-1 py-0.5 font-mono">↵</kbd> select
              </span>
              <span>
                <kbd className="rounded bg-muted px-1 py-0.5 font-mono">esc</kbd> close
              </span>
            </div>
          </div>
        </div>
      </div>
    </>
  );
}

function SpotlightRow({
  item,
  selected,
  onSelect,
  onHover,
}: {
  item: SpotlightItem;
  selected: boolean;
  onSelect: () => void;
  onHover: () => void;
}) {
  const Icon = item.icon;

  return (
    <button
      type="button"
      onClick={onSelect}
      onMouseEnter={onHover}
      className={cn(
        "flex w-full items-center gap-3 rounded-lg px-2.5 py-2 text-left transition-colors",
        selected ? "bg-primary text-primary-foreground" : "hover:bg-muted/50",
      )}
    >
      {item.color ? (
        <span
          className="h-3 w-3 shrink-0 rounded-full"
          style={{ backgroundColor: item.color }}
        />
      ) : Icon ? (
        <Icon
          className={cn(
            "h-4 w-4 shrink-0",
            selected ? "text-primary-foreground" : "text-muted-foreground",
          )}
        />
      ) : null}
      <div className="flex-1 min-w-0">
        <div className="text-sm truncate">{item.label}</div>
        {item.description && (
          <div
            className={cn(
              "text-[11px] truncate",
              selected ? "text-primary-foreground/70" : "text-muted-foreground",
            )}
          >
            {item.description}
          </div>
        )}
      </div>
      {item.shortcut && (
        <kbd
          className={cn(
            "shrink-0 rounded px-1.5 py-0.5 text-[10px] font-mono",
            selected
              ? "bg-primary-foreground/20 text-primary-foreground"
              : "bg-muted text-muted-foreground",
          )}
        >
          {item.shortcut}
        </kbd>
      )}
    </button>
  );
}

/** Trigger button — shows ⌘K badge */
export function SpotlightTrigger({ onClick }: { onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="pointer-events-auto flex items-center gap-1.5 rounded-lg border bg-background/80 backdrop-blur-sm px-2.5 py-1.5 text-xs text-muted-foreground transition-colors hover:bg-muted/80"
    >
      <Search className="h-3.5 w-3.5" />
      <kbd className="rounded bg-muted px-1 py-0.5 text-[10px] font-mono">⌘K</kbd>
    </button>
  );
}
