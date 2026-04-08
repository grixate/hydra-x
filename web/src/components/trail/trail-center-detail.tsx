import { useState, useEffect } from "react";
import { motion } from "motion/react";
import type { TrailNode, TrailFlag } from "@/lib/api";
import { api } from "@/lib/api";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { NodeTypeIcon, nodeTypeLabel } from "@/components/shared/node-type-icon";
import { NODE_COLORS } from "@/components/graph/graph-constants";
import { relativeLabel } from "@/lib/utils";
import {
  Pencil,
  MessageSquare,
  Network,
  Lock,
  AlertTriangle,
  Check,
  X,
} from "lucide-react";

interface TrailCenterDetailProps {
  node: TrailNode;
  flags: TrailFlag[];
  projectId: number;
  onNavigate: (nodeType: string, nodeId: number) => void;
  onNavigateGraph: () => void;
  onChat: () => void;
  onRefresh: () => void;
}

const statusOptions: Record<string, string[]> = {
  insight: ["draft", "accepted", "rejected"],
  decision: ["draft", "active", "superseded", "archived"],
  requirement: ["draft", "accepted", "archived"],
  strategy: ["draft", "active", "archived"],
  design_node: ["draft", "active", "archived"],
  architecture_node: ["draft", "active", "archived"],
  task: ["backlog", "ready", "in_progress", "review", "done"],
  learning: ["draft", "active", "archived"],
  constraint: ["active", "archived"],
};

// Map node types to their api update function names
function getUpdateFn(nodeType: string) {
  const map: Record<string, string> = {
    insight: "updateInsight",
    decision: "updateDecision",
    requirement: "updateRequirement",
    task: "updateTask",
    constraint: "updateConstraint",
  };
  return map[nodeType];
}

export function TrailCenterDetail({
  node,
  flags,
  projectId,
  onNavigate,
  onNavigateGraph,
  onChat,
  onRefresh,
}: TrailCenterDetailProps) {
  const [editing, setEditing] = useState(false);
  const [editTitle, setEditTitle] = useState(node.title);
  const [editBody, setEditBody] = useState(node.body ?? "");
  const [saving, setSaving] = useState(false);

  // Reset edit state when node changes
  useEffect(() => {
    setEditing(false);
    setEditTitle(node.title);
    setEditBody(node.body ?? "");
  }, [node.node_type, node.node_id]);

  const dotColor = NODE_COLORS[node.node_type] ?? NODE_COLORS.default;
  const alternatives = node.alternatives_considered;
  const constraints = node.constraints;
  const openFlags = flags.filter((f) => f.status === "open");

  // Build metadata stats
  const upCounts = node.upstream_counts ?? {};
  const downCounts = node.downstream_counts ?? {};
  const upTotal = Object.values(upCounts).reduce((a, b) => a + b, 0);
  const downTotal = Object.values(downCounts).reduce((a, b) => a + b, 0);

  const upLabel = upTotal > 0
    ? `↑ ${Object.entries(upCounts).map(([t, c]) => `${c} ${t.replace(/_/g, " ")}${c > 1 ? "s" : ""}`).join(", ")}`
    : null;
  const downLabel = downTotal > 0
    ? `↓ ${Object.entries(downCounts).map(([t, c]) => `${c} ${t.replace(/_/g, " ")}${c > 1 ? "s" : ""}`).join(", ")}`
    : null;

  const handleSave = async () => {
    const fnName = getUpdateFn(node.node_type);
    if (!fnName) return;
    setSaving(true);
    try {
      const updateFn = (api as Record<string, Function>)[fnName];
      await updateFn(projectId, node.node_id, {
        title: editTitle,
        body: editBody,
      });
      setEditing(false);
      onRefresh();
    } finally {
      setSaving(false);
    }
  };

  const handleStatusChange = async (newStatus: string) => {
    const fnName = getUpdateFn(node.node_type);
    if (!fnName) return;
    const updateFn = (api as Record<string, Function>)[fnName];
    await updateFn(projectId, node.node_id, { status: newStatus });
    onRefresh();
  };

  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.4, ease: [0.25, 0.46, 0.45, 0.94] }}
      className="rounded-xl border-2 border-primary/20 bg-card p-6 space-y-4"
    >
      {/* Type + status header */}
      <div className="flex items-center gap-2">
        <div
          className="h-2.5 w-2.5 shrink-0 rounded-full"
          style={{ backgroundColor: dotColor }}
        />
        <NodeTypeIcon nodeType={node.node_type} className="h-4 w-4 text-muted-foreground" />
        <span className="text-sm text-muted-foreground">
          {nodeTypeLabel(node.node_type)}
        </span>
        <Badge
          variant={node.status === "active" || node.status === "accepted" ? "default" : "secondary"}
          className="text-[10px]"
        >
          {node.status?.replace(/_/g, " ")}
        </Badge>
      </div>

      {/* Title */}
      {editing ? (
        <input
          className="w-full text-lg font-semibold bg-transparent border-b border-primary/30 focus:outline-none focus:border-primary pb-1"
          value={editTitle}
          onChange={(e) => setEditTitle(e.target.value)}
        />
      ) : (
        <h1 className="text-lg font-semibold leading-snug">
          {node.title}
        </h1>
      )}

      {/* Body */}
      {editing ? (
        <textarea
          className="w-full min-h-[120px] text-sm leading-relaxed bg-transparent border rounded-lg p-3 focus:outline-none focus:border-primary resize-y"
          value={editBody}
          onChange={(e) => setEditBody(e.target.value)}
        />
      ) : (
        node.body && (
          <p className="text-sm leading-relaxed whitespace-pre-wrap">
            {node.body}
          </p>
        )
      )}

      {/* Alternatives (decisions only) */}
      {!editing && alternatives && alternatives.length > 0 && (
        <div className="space-y-1.5">
          <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
            Alternatives considered
          </p>
          <ul className="space-y-1">
            {alternatives.map((alt, i) => (
              <li key={i} className="text-sm text-muted-foreground">
                <span className="font-medium text-foreground">{alt.title}</span>
                {alt.rejected_reason && ` — ${alt.rejected_reason}`}
              </li>
            ))}
          </ul>
        </div>
      )}

      {/* Constraints */}
      {!editing && constraints && constraints.length > 0 && (
        <div className="space-y-1.5">
          <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
            Constraints
          </p>
          {constraints.map((c) => (
            <div
              key={c.id}
              className="flex items-center gap-2 text-sm cursor-pointer hover:text-foreground text-muted-foreground transition-colors"
              onClick={() => onNavigate("constraint", c.id)}
            >
              <Lock className="h-3 w-3 shrink-0" />
              <span>{c.title}</span>
            </div>
          ))}
        </div>
      )}

      {/* Flags */}
      {!editing && openFlags.length > 0 && (
        <div className="space-y-1.5 border-t pt-3">
          {openFlags.map((flag) => (
            <div
              key={flag.id}
              className="flex items-center gap-2 text-sm"
            >
              <AlertTriangle className="h-3.5 w-3.5 shrink-0 text-amber-500" />
              <span className="flex-1 text-muted-foreground">
                <span className="font-medium capitalize">{flag.flag_type.replace(/_/g, " ")}</span>
                : {flag.reason}
              </span>
              <Button variant="ghost" size="sm" className="text-xs h-6 px-2 shrink-0">
                Resolve
              </Button>
            </div>
          ))}
        </div>
      )}

      {/* Metadata bar */}
      {!editing && (
        <div className="border-t pt-3 space-y-1">
          <div className="flex flex-wrap gap-x-4 gap-y-1 text-xs text-muted-foreground">
            {upLabel && <span>{upLabel}</span>}
            {downLabel && <span>{downLabel}</span>}
            <span>⚑ {openFlags.length} flag{openFlags.length !== 1 ? "s" : ""}</span>
          </div>
          <div className="text-xs text-muted-foreground">
            {node.decided_by && `Decided by ${node.decided_by} · `}
            {node.inserted_at && `Created ${relativeLabel(node.inserted_at)}`}
            {node.updated_at && ` · Updated ${relativeLabel(node.updated_at)}`}
          </div>
        </div>
      )}

      {/* Action bar */}
      <div className="border-t pt-3 flex items-center gap-2 flex-wrap">
        {editing ? (
          <>
            <Button
              variant="default"
              size="sm"
              className="text-xs"
              onClick={handleSave}
              disabled={saving}
            >
              <Check className="mr-1 h-3 w-3" />
              {saving ? "Saving..." : "Save"}
            </Button>
            <Button
              variant="ghost"
              size="sm"
              className="text-xs"
              onClick={() => {
                setEditing(false);
                setEditTitle(node.title);
                setEditBody(node.body ?? "");
              }}
            >
              <X className="mr-1 h-3 w-3" />
              Cancel
            </Button>
          </>
        ) : (
          <>
            {getUpdateFn(node.node_type) && (
              <Button
                variant="outline"
                size="sm"
                className="text-xs"
                onClick={() => setEditing(true)}
              >
                <Pencil className="mr-1 h-3 w-3" />
                Edit
              </Button>
            )}

            {/* Status dropdown */}
            {statusOptions[node.node_type] && (
              <select
                className="h-7 rounded-md border bg-background px-2 text-xs"
                value={node.status}
                onChange={(e) => handleStatusChange(e.target.value)}
              >
                {statusOptions[node.node_type].map((s) => (
                  <option key={s} value={s}>
                    {s.replace(/_/g, " ")}
                  </option>
                ))}
              </select>
            )}

            <Button
              variant="outline"
              size="sm"
              className="text-xs"
              onClick={onChat}
            >
              <MessageSquare className="mr-1 h-3 w-3" />
              Chat about this
            </Button>

            <Button
              variant="ghost"
              size="sm"
              className="text-xs"
              onClick={onNavigateGraph}
            >
              <Network className="mr-1 h-3 w-3" />
              View on graph
            </Button>
          </>
        )}
      </div>
    </motion.div>
  );
}
