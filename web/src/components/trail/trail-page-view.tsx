import { motion } from "motion/react";
import type { TrailNode, TrailChainNode, TrailFlag } from "@/lib/api";
import { TrailBreadcrumb } from "./trail-breadcrumb";
import { TrailSectionDivider } from "./trail-section-divider";
import { TrailChainCard } from "./trail-chain-card";
import { TrailCenterDetail } from "./trail-center-detail";
import { TrailConnectionLine } from "./trail-connection-line";
import { Button } from "@/components/ui/button";
import { ArrowLeft, MessageSquare } from "lucide-react";

interface TrailPageViewProps {
  center: TrailNode;
  upstream: TrailChainNode[];
  downstream: TrailChainNode[];
  flags: TrailFlag[];
  projectId: number;
  backLabel: string;
  onBack: () => void;
  onNavigate: (nodeType: string, nodeId: number) => void;
  onNavigateGraph: () => void;
  onChat: () => void;
  onRefresh: () => void;
}

export function TrailPageView({
  center,
  upstream,
  downstream,
  flags,
  projectId,
  backLabel,
  onBack,
  onNavigate,
  onNavigateGraph,
  onChat,
  onRefresh,
}: TrailPageViewProps) {
  return (
    <div className="mx-auto max-w-2xl px-4 py-6">
      {/* Top bar: back link + breadcrumb */}
      <div className="flex items-center justify-between mb-2">
        <button
          onClick={onBack}
          className="flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground transition-colors"
        >
          <ArrowLeft className="h-3.5 w-3.5" />
          {backLabel}
        </button>
        <TrailBreadcrumb
          upstream={upstream}
          centerType={center.node_type}
          downstream={downstream}
          onNavigate={onNavigate}
        />
      </div>

      {/* Upstream section */}
      <TrailSectionDivider label="Where this came from" />

      {upstream.length === 0 ? (
        <motion.p
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          className="py-4 text-sm text-muted-foreground text-center"
        >
          This is a root node — it has no upstream sources.
        </motion.p>
      ) : (
        <div>
          {upstream.map((node, i) => (
            <div key={`${node.node_type}-${node.node_id}-${i}`}>
              {i > 0 && <TrailConnectionLine edgeKind={node.edge_kind} />}
              <TrailChainCard
                node={node}
                index={i}
                onClick={onNavigate}
              />
            </div>
          ))}
          {/* Connection line from last upstream to center */}
          {upstream.length > 0 && (
            <TrailConnectionLine edgeKind={upstream[upstream.length - 1].edge_kind} />
          )}
        </div>
      )}

      {/* Center node */}
      <TrailSectionDivider />

      <TrailCenterDetail
        node={center}
        flags={flags}
        projectId={projectId}
        onNavigate={onNavigate}
        onNavigateGraph={onNavigateGraph}
        onChat={onChat}
        onRefresh={onRefresh}
      />

      {/* Downstream section */}
      <TrailSectionDivider label="What depends on this" />

      {downstream.length === 0 ? (
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          className="py-4 text-center space-y-2"
        >
          <p className="text-sm text-muted-foreground">
            Nothing depends on this node yet.
          </p>
          <Button
            variant="ghost"
            size="sm"
            className="text-xs text-muted-foreground"
            onClick={onChat}
          >
            <MessageSquare className="mr-1 h-3 w-3" />
            Chat with an agent to explore what should come next
          </Button>
        </motion.div>
      ) : (
        <div>
          {downstream.map((node, i) => (
            <div key={`${node.node_type}-${node.node_id}-${i}`}>
              {i > 0 && <TrailConnectionLine edgeKind={node.edge_kind} />}
              <TrailChainCard
                node={node}
                index={i}
                onClick={onNavigate}
              />
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
