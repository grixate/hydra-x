import { useNavigate, useParams } from "react-router-dom";
import { motion } from "motion/react";
import { Badge } from "@/components/ui/badge";
import { NODE_COLORS } from "@/components/graph/graph-constants";
import { nodeTypeLabel } from "@/components/shared/node-type-icon";
import { relativeLabel, cn } from "@/lib/utils";

interface FeedNodeCardProps {
  nodeType: string;
  nodeId: number;
  title: string;
  body?: string;
  status: string;
  upstreamCount: number;
  downstreamCount: number;
  flagCount: number;
  origin?: string;
  originTitle?: string | null;
  createdAt?: string;
  index?: number;
}

export function FeedNodeCard({
  nodeType,
  nodeId,
  title,
  body,
  status,
  upstreamCount,
  downstreamCount,
  flagCount,
  origin,
  originTitle,
  createdAt,
  index = 0,
}: FeedNodeCardProps) {
  const navigate = useNavigate();
  const { projectId } = useParams<{ projectId: string }>();
  const dotColor = NODE_COLORS[nodeType] ?? NODE_COLORS.default;
  const isDraft = status === "draft";
  const hasFlags = flagCount > 0;

  const borderColor = hasFlags ? "border-l-amber-500" : `border-l-[${dotColor}]`;

  return (
    <motion.div
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.3, delay: index * 0.05 }}
      className={cn(
        "rounded-xl border bg-card p-4 space-y-2 transition-colors hover:bg-accent/30",
        isDraft && "border-dashed",
      )}
      style={{ borderLeftWidth: 3, borderLeftColor: hasFlags ? undefined : dotColor }}
    >
      {/* Type header */}
      <div className="flex items-center gap-2">
        <div
          className="h-2 w-2 shrink-0 rounded-full"
          style={{ backgroundColor: dotColor }}
        />
        <span className="text-xs text-muted-foreground">
          {nodeTypeLabel(nodeType)}
        </span>
        <Badge
          variant={status === "active" || status === "accepted" ? "default" : "secondary"}
          className="text-[9px] px-1.5 py-0 h-4"
        >
          {status?.replace(/_/g, " ")}
        </Badge>
      </div>

      {/* Title */}
      <p
        className="text-sm font-medium leading-snug cursor-pointer hover:underline"
        onClick={() => navigate(`/projects/${projectId}/trail/${nodeType}/${nodeId}`, { state: { from: "agent" } })}
      >
        {title}
      </p>

      {/* Body */}
      {body && (
        <p className="text-sm text-muted-foreground leading-relaxed line-clamp-5">
          {body}
        </p>
      )}

      {/* Connection footer */}
      <div className="flex items-center gap-3 text-xs text-muted-foreground">
        {upstreamCount > 0 && <span>↑{upstreamCount}</span>}
        {downstreamCount > 0 && <span>↓{downstreamCount}</span>}
        {flagCount > 0 && <span>⚑{flagCount}</span>}
      </div>

      {/* Origin + trail */}
      <div className="flex items-center justify-between text-xs text-muted-foreground">
        <span>
          {originTitle ? `From: ${originTitle}` : origin === "autonomous" ? "Autonomous work" : "Project"}
          {createdAt && ` · ${relativeLabel(createdAt)}`}
        </span>
        <button
          className="text-xs text-muted-foreground hover:text-foreground transition-colors"
          onClick={() => navigate(`/projects/${projectId}/trail/${nodeType}/${nodeId}`, { state: { from: "agent" } })}
        >
          Trail ↗
        </button>
      </div>
    </motion.div>
  );
}
