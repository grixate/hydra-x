import type {
  TrailChainNode,
  TrailFlag,
  TrailNode,
} from "@/lib/api";
import { TrailChain } from "./trail-chain";
import { TrailDetail } from "./trail-detail";
import { TrailFlags } from "./trail-flags";
import { Card, CardContent } from "@/components/ui/card";

interface TrailViewProps {
  center: TrailNode | null;
  upstream: TrailChainNode[];
  downstream: TrailChainNode[];
  flags: TrailFlag[];
  onNodeClick?: (nodeType: string, nodeId: number) => void;
}

export function TrailView({
  center,
  upstream,
  downstream,
  flags,
  onNodeClick,
}: TrailViewProps) {
  if (!center) {
    return (
      <Card>
        <CardContent className="py-8 text-center text-sm text-ink-soft">
          Select a node to view its trail.
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-4">
      <TrailChain
        nodes={upstream}
        direction="upstream"
        onNodeClick={onNodeClick}
      />

      <TrailDetail node={center} />

      <TrailFlags flags={flags} />

      <TrailChain
        nodes={downstream}
        direction="downstream"
        onNodeClick={onNodeClick}
      />
    </div>
  );
}
