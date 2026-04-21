import { useNavigate, useParams } from "react-router-dom";
import {
  Activity,
  AlertTriangle,
  CheckCircle2,
  Clock,
  GitFork,
  Sparkles,
  TriangleAlert,
  XCircle,
} from "lucide-react";
import type { LucideIcon } from "lucide-react";

import { Button } from "@/components/ui/button";
import { cn, relativeLabel } from "@/lib/utils";
import { AGENTS_BY_ID, agentLabel } from "@/components/command-center/agents";
import { dispatchChatDockAgentSwitch } from "@/components/chat/chat-dock";
import type { StreamTabItem } from "@/types";

const KIND_ICON: Record<StreamTabItem["kind"], { icon: LucideIcon; tone: string }> = {
  stream_entry: { icon: Activity, tone: "text-muted-foreground" },
  proposing: { icon: Sparkles, tone: "text-emerald-500" },
  waiting_for_input: { icon: TriangleAlert, tone: "text-amber-500" },
  blocked: { icon: AlertTriangle, tone: "text-rose-500" },
  failed: { icon: XCircle, tone: "text-rose-500" },
  stalled_flow: { icon: GitFork, tone: "text-amber-500" },
  contradiction: { icon: AlertTriangle, tone: "text-rose-500" },
  burst: { icon: Activity, tone: "text-muted-foreground" },
};

const PRIMARY_LABEL: Partial<Record<StreamTabItem["kind"], string>> = {
  proposing: "Review",
  waiting_for_input: "Reply",
  blocked: "Resolve",
  failed: "View error",
  stalled_flow: "Inspect",
  contradiction: "Review",
};

export function StreamEntryRow({ item, onResolved }: { item: StreamTabItem; onResolved?: () => void }) {
  const navigate = useNavigate();
  const { projectId } = useParams<{ projectId: string }>();
  const meta = KIND_ICON[item.kind];
  const Icon = meta.icon;

  const agent = item.actor_agent_id ? AGENTS_BY_ID[item.actor_agent_id] : null;
  const AgentIcon = agent?.icon;

  const primaryLabel = PRIMARY_LABEL[item.kind];

  function handlePrimary() {
    if (!projectId) return;
    // Anything with a live task routes to Command Center, filtered to
    // its agent so the user can act immediately.
    if (item.source_task_id && item.actor_agent_id) {
      navigate(`/projects/${projectId}/command-center?agent=${item.actor_agent_id}`);
      return;
    }
    if (item.stream_entry_id) {
      navigate(`/projects/${projectId}/command-center`);
      return;
    }
    if (item.flow_id) {
      navigate(`/projects/${projectId}/command-center`);
    }
  }

  function handleTalk() {
    if (!item.actor_agent_id) return;
    dispatchChatDockAgentSwitch(item.actor_agent_id);
  }

  return (
    <div className="flex flex-col gap-1.5 rounded-lg border bg-card p-3 transition-colors hover:border-primary/40">
      <div className="flex items-start gap-2">
        <Icon className={cn("mt-0.5 h-4 w-4 shrink-0", meta.tone)} />
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2 text-[10px] uppercase tracking-widest text-muted-foreground">
            {AgentIcon ? <AgentIcon className="h-3 w-3" /> : null}
            <span>{item.actor_agent_id ? agentLabel(item.actor_agent_id) : item.kind.replace(/_/g, " ")}</span>
            <span aria-hidden>·</span>
            <Clock className="h-3 w-3" />
            <span>{relativeLabel(item.inserted_at)}</span>
            {item.state && item.state !== "active" ? (
              <>
                <span aria-hidden>·</span>
                <span>{item.state.replace(/_/g, " ")}</span>
              </>
            ) : null}
          </div>
          <p className="mt-0.5 text-sm font-medium leading-snug">{item.title}</p>
          {item.summary ? (
            <p className="mt-0.5 line-clamp-2 text-xs text-muted-foreground">{item.summary}</p>
          ) : null}
        </div>
      </div>

      {primaryLabel || item.actor_agent_id ? (
        <div className="flex justify-end gap-1">
          {item.actor_agent_id ? (
            <Button variant="ghost" size="sm" className="h-7 text-[11px]" onClick={handleTalk}>
              Talk to {agent?.label ?? item.actor_agent_id}
            </Button>
          ) : null}
          {primaryLabel ? (
            <Button size="sm" className="h-7 text-[11px]" onClick={handlePrimary}>
              <CheckCircle2 className="mr-1 h-3 w-3" />
              {primaryLabel}
            </Button>
          ) : null}
        </div>
      ) : null}
      {onResolved ? null : null}
    </div>
  );
}
