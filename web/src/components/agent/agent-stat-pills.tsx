import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";
import { Separator } from "@/components/ui/separator";
import { Progress } from "@/components/ui/progress";
import { NODE_COLORS } from "@/components/graph/graph-constants";
import { nodeTypeLabel } from "@/components/shared/node-type-icon";
import { relativeLabel, cn } from "@/lib/utils";
import { ActivityHeatmap } from "./activity-heatmap";

function PillButton({ tooltip, className, children, ...props }: React.ButtonHTMLAttributes<HTMLButtonElement> & { tooltip: string }) {
  return (
    <TooltipProvider>
      <Tooltip>
        <TooltipTrigger asChild>
          <button className={className} {...props}>{children}</button>
        </TooltipTrigger>
        <TooltipContent side="bottom" sideOffset={4}>
          {tooltip}
        </TooltipContent>
      </Tooltip>
    </TooltipProvider>
  );
}

function pillColor(color: string) {
  switch (color) {
    case "green": return "border-emerald-500/30 text-emerald-600";
    case "amber": return "border-amber-500/30 text-amber-600";
    case "red": return "border-red-500/30 text-red-600";
    case "muted": return "border-border text-muted-foreground";
    default: return "border-border text-foreground";
  }
}

function formatTokens(t: number): string {
  if (t >= 1_000_000) return `${(t / 1_000_000).toFixed(1)}M`;
  if (t >= 1_000) return `${(t / 1_000).toFixed(0)}K`;
  return String(t);
}

// --- Status Pill ---

interface StatusPillProps {
  state: string;
  lastActiveAt?: string | null;
  heatmap?: number[][];
}

export function StatusPill({ state, lastActiveAt, heatmap }: StatusPillProps) {
  const isWorking = state === "working";
  const color = isWorking ? "amber" : "green";

  return (
    <Popover>
      <PopoverTrigger asChild>
        <PillButton tooltip="Agent status" className={cn("inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-xs transition-colors hover:bg-muted/50", pillColor(color))}>
          <span className={cn("h-1.5 w-1.5 rounded-full", isWorking ? "animate-pulse bg-amber-500" : "bg-emerald-500")} />
          <span className="font-medium">{isWorking ? "working..." : state}</span>
        </PillButton>
      </PopoverTrigger>
      <PopoverContent className="w-72 p-4 space-y-3" align="start">
        <p className="text-sm font-medium">Status: {state}</p>
        {lastActiveAt && (
          <p className="text-xs text-muted-foreground">Last active: {relativeLabel(lastActiveAt)}</p>
        )}
        {heatmap && heatmap.length === 7 && (
          <>
            <Separator />
            <p className="text-xs font-medium text-muted-foreground">Activity this week</p>
            <ActivityHeatmap data={heatmap} />
          </>
        )}
      </PopoverContent>
    </Popover>
  );
}

// --- Nodes Pill ---

interface NodesPillProps {
  created: number;
  accepted: number;
  rejected?: number;
  pending?: number;
  byNodeType?: Record<string, number>;
}

export function NodesPill({ created, accepted, rejected = 0, pending = 0, byNodeType }: NodesPillProps) {
  return (
    <Popover>
      <PopoverTrigger asChild>
        <PillButton tooltip="Accepted / created nodes" className={cn("inline-flex items-center gap-1 rounded-full border px-2.5 py-1 text-xs transition-colors hover:bg-muted/50", pillColor("default"))}>
          <span className="font-medium">{accepted}/{created}</span>
        </PillButton>
      </PopoverTrigger>
      <PopoverContent className="w-72 p-4 space-y-3" align="start">
        <p className="text-sm font-medium">Nodes this month</p>
        <div className="space-y-1.5 text-xs">
          <div className="flex justify-between"><span className="text-muted-foreground">Created</span><span className="font-medium">{created}</span></div>
          <div className="flex justify-between"><span className="text-muted-foreground">Accepted</span><span className="font-medium">{accepted}</span></div>
          {rejected > 0 && <div className="flex justify-between"><span className="text-muted-foreground">Rejected</span><span className="font-medium">{rejected}</span></div>}
          {pending > 0 && <div className="flex justify-between"><span className="text-muted-foreground">Pending</span><span className="font-medium">{pending}</span></div>}
        </div>
        {byNodeType && Object.keys(byNodeType).length > 0 && (
          <>
            <Separator />
            <p className="text-xs font-medium text-muted-foreground">By type</p>
            <div className="space-y-1 text-xs">
              {Object.entries(byNodeType)
                .sort(([, a], [, b]) => b - a)
                .map(([type, count]) => (
                  <div key={type} className="flex items-center gap-2">
                    <div className="h-1.5 w-1.5 rounded-full" style={{ backgroundColor: NODE_COLORS[type] ?? NODE_COLORS.default }} />
                    <span className="text-muted-foreground flex-1">{nodeTypeLabel(type)}</span>
                    <span className="font-medium">{count}</span>
                  </div>
                ))}
            </div>
          </>
        )}
      </PopoverContent>
    </Popover>
  );
}

// --- Acceptance Pill ---

interface AcceptancePillProps {
  rate: number;
}

export function AcceptancePill({ rate }: AcceptancePillProps) {
  const pct = Math.round(rate * 100);
  const color = rate === 0 ? "muted" : pct >= 75 ? "green" : pct >= 50 ? "amber" : "red";

  return (
    <Popover>
      <PopoverTrigger asChild>
        <PillButton tooltip="Acceptance rate" className={cn("inline-flex items-center gap-1 rounded-full border px-2.5 py-1 text-xs transition-colors hover:bg-muted/50", pillColor(color))}>
          <span className="font-medium">{pct}%</span>
        </PillButton>
      </PopoverTrigger>
      <PopoverContent className="w-64 p-4 space-y-3" align="start">
        <p className="text-sm font-medium">Acceptance rate</p>
        <p className="text-2xl font-semibold tracking-tight">{pct}%</p>
        <Progress value={pct} className="h-1.5" />
      </PopoverContent>
    </Popover>
  );
}

// --- Spend Pill ---

interface SpendPillProps {
  cents: number;
}

export function SpendPill({ cents }: SpendPillProps) {
  const color = cents > 2500 ? "red" : cents > 1000 ? "amber" : "default";

  return (
    <Popover>
      <PopoverTrigger asChild>
        <PillButton tooltip="Spend this month" className={cn("inline-flex items-center gap-1 rounded-full border px-2.5 py-1 text-xs transition-colors hover:bg-muted/50", pillColor(color))}>
          <span className="font-medium">${(cents / 100).toFixed(2)}</span>
        </PillButton>
      </PopoverTrigger>
      <PopoverContent className="w-64 p-4 space-y-3" align="start">
        <p className="text-sm font-medium">Spend this month</p>
        <p className="text-2xl font-semibold tracking-tight">${(cents / 100).toFixed(2)}</p>
        {cents > 0 && (
          <div className="flex justify-between text-xs">
            <span className="text-muted-foreground">Daily average</span>
            <span className="font-medium">${(cents / 30 / 100).toFixed(2)}</span>
          </div>
        )}
      </PopoverContent>
    </Popover>
  );
}

// --- Tokens Pill ---

interface TokensPillProps {
  tokens: number;
  tokensIn?: number;
  tokensOut?: number;
  callCount?: number;
}

export function TokensPill({ tokens, tokensIn = 0, tokensOut = 0, callCount = 0 }: TokensPillProps) {
  return (
    <Popover>
      <PopoverTrigger asChild>
        <PillButton tooltip="Tokens used this month" className={cn("inline-flex items-center gap-1 rounded-full border px-2.5 py-1 text-xs transition-colors hover:bg-muted/50", pillColor("muted"))}>
          <span className="font-medium">{formatTokens(tokens)}</span>
        </PillButton>
      </PopoverTrigger>
      <PopoverContent className="w-64 p-4 space-y-3" align="start">
        <p className="text-sm font-medium">Tokens this month</p>
        <p className="text-2xl font-semibold tracking-tight">{formatTokens(tokens)}</p>
        {(tokensIn > 0 || tokensOut > 0) && (
          <div className="space-y-1.5 text-xs">
            <div className="flex justify-between">
              <span className="text-muted-foreground">Input</span>
              <span className="font-medium">{formatTokens(tokensIn)} ({tokens > 0 ? Math.round((tokensIn / tokens) * 100) : 0}%)</span>
            </div>
            <div className="flex justify-between">
              <span className="text-muted-foreground">Output</span>
              <span className="font-medium">{formatTokens(tokensOut)} ({tokens > 0 ? Math.round((tokensOut / tokens) * 100) : 0}%)</span>
            </div>
          </div>
        )}
        {callCount > 0 && (
          <>
            <Separator />
            <div className="flex justify-between text-xs">
              <span className="text-muted-foreground">Total calls</span>
              <span className="font-medium">{callCount}</span>
            </div>
            <div className="flex justify-between text-xs">
              <span className="text-muted-foreground">Avg per call</span>
              <span className="font-medium">{formatTokens(Math.round(tokens / callCount))}</span>
            </div>
          </>
        )}
      </PopoverContent>
    </Popover>
  );
}
