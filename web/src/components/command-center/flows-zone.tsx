import { useState } from "react";
import { ChevronDown, ChevronUp } from "lucide-react";
import type { Flow } from "@/types";
import { FlowDiagram } from "./flow-diagram";

export function FlowsZone({
  flows,
  onAgentClick,
}: {
  flows: Flow[];
  onAgentClick: (agentId: string) => void;
}) {
  const [collapsed, setCollapsed] = useState(flows.length === 0);

  const hasFlows = flows.length > 0;

  return (
    <div className="flex flex-col gap-2 rounded-lg border bg-card p-3">
      <button
        type="button"
        onClick={() => setCollapsed((current) => !current)}
        className="flex items-center justify-between text-left"
      >
        <div className="flex items-center gap-2">
          <h2 className="text-sm font-semibold">Cross-agent flows</h2>
          {hasFlows ? (
            <span className="text-[10px] text-muted-foreground tabular-nums">{flows.length}</span>
          ) : null}
        </div>
        {collapsed ? (
          <ChevronDown className="h-4 w-4 text-muted-foreground" />
        ) : (
          <ChevronUp className="h-4 w-4 text-muted-foreground" />
        )}
      </button>

      {collapsed ? null : hasFlows ? (
        <div className="flex gap-2 overflow-x-auto pb-1">
          {flows.map((flow) => (
            <FlowDiagram key={flow.id} flow={flow} onAgentClick={onAgentClick} />
          ))}
        </div>
      ) : (
        <p className="text-xs text-muted-foreground">
          No cross-agent flows active. Agents coordinate here when their work connects via @-mentions.
        </p>
      )}
    </div>
  );
}
