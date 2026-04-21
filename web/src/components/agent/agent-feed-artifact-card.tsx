import { useNavigate } from "react-router-dom";
import { motion } from "motion/react";
import { Badge } from "@/components/ui/badge";
import { relativeLabel } from "@/lib/utils";

interface FeedArtifactCardProps {
  projectId: number;
  artifactId: number;
  title: string;
  version: number;
  changeSummary?: string | null;
  updatedAt?: string;
  index?: number;
}

export function FeedArtifactCard({
  projectId,
  artifactId,
  title,
  version,
  changeSummary,
  updatedAt,
  index = 0,
}: FeedArtifactCardProps) {
  const navigate = useNavigate();
  return (
    <motion.div
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.3, delay: index * 0.05 }}
      className="rounded-xl border border-l-3 border-l-muted-foreground/30 bg-card p-4 space-y-2"
    >
      <div className="flex items-center gap-2">
        <span className="text-sm">📋</span>
        <span className="text-xs text-muted-foreground">Artifact</span>
        <Badge variant="secondary" className="text-[9px] px-1.5 py-0 h-4">
          v{version}
        </Badge>
      </div>

      <p className="text-sm font-medium">{title}</p>

      {updatedAt && (
        <p className="text-xs text-muted-foreground">
          Updated {relativeLabel(updatedAt)}
        </p>
      )}

      {changeSummary && (
        <p className="text-sm text-muted-foreground leading-relaxed line-clamp-3">
          {changeSummary}
        </p>
      )}

      <div className="flex justify-end">
        <button
          onClick={() => navigate(`/projects/${projectId}/library/${artifactId}`)}
          className="text-xs text-muted-foreground hover:text-foreground transition-colors"
        >
          Read full ↗
        </button>
      </div>
    </motion.div>
  );
}
