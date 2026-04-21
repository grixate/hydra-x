import { useEffect, useRef, useState } from "react";
import {
  AlertTriangle,
  ArrowDown,
  Compass,
  Link2,
  Loader2,
  Pin,
  RotateCw,
  Target,
  TriangleAlert,
} from "lucide-react";

import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { api } from "@/lib/api";
import { cn } from "@/lib/utils";
import type {
  WhyContradictionRef,
  WhyLineageCard,
  WhyPayload,
} from "@/types";

export function WhyPanel({
  open,
  projectId,
  nodeType,
  nodeId,
  onClose,
  onNavigateToNode,
}: {
  open: boolean;
  projectId: number;
  nodeType: string | null;
  nodeId: number | null;
  onClose: () => void;
  onNavigateToNode?: (nodeType: string, nodeId: number) => void;
}) {
  const [payload, setPayload] = useState<WhyPayload | null>(null);
  const [loading, setLoading] = useState(false);
  const [retrying, setRetrying] = useState(false);
  const [pinned, setPinned] = useState(false);
  const [shared, setShared] = useState(false);
  const shareTimeoutRef = useRef<number | null>(null);

  useEffect(() => {
    if (!open || !nodeType || nodeId == null) return;
    let cancelled = false;

    setLoading(true);
    setPayload(null);

    api
      .getWhy(projectId, nodeType, nodeId)
      .then((data) => {
        if (!cancelled) setPayload(data);
      })
      .catch(() => {
        if (!cancelled) {
          setPayload({
            lineage: [],
            prose: null,
            vision_present: false,
            orphan: true,
            cached: false,
            error: "Couldn't load lineage.",
            contradictions: [],
          });
        }
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [open, projectId, nodeType, nodeId]);

  async function handleRetryProse() {
    if (!nodeType || nodeId == null) return;
    setRetrying(true);
    try {
      const data = await api.getWhy(projectId, nodeType, nodeId, true);
      setPayload(data);
    } finally {
      setRetrying(false);
    }
  }

  async function handleShare() {
    if (!nodeType || nodeId == null) return;
    const url = `${window.location.origin}/projects/${projectId}/graph?node=${nodeType}-${nodeId}&panel=why`;
    try {
      await navigator.clipboard.writeText(url);
      setShared(true);
      if (shareTimeoutRef.current) window.clearTimeout(shareTimeoutRef.current);
      shareTimeoutRef.current = window.setTimeout(() => setShared(false), 2000);
    } catch {
      // clipboard unavailable (e.g. non-https) — fall back to a prompt
      window.prompt("Copy this link", url);
    }
  }

  const target = payload?.lineage.find((c) => c.is_target);
  const targetTitle = target?.title ?? "this node";
  const contradictions = payload?.contradictions ?? [];

  return (
    <Sheet open={open} onOpenChange={(value) => (!value && !pinned ? onClose() : undefined)}>
      <SheetContent className="w-full overflow-y-auto sm:max-w-[480px]">
        <SheetHeader>
          <SheetTitle className="flex items-start gap-2">
            <Compass className="mt-0.5 h-4 w-4 shrink-0 text-primary" />
            <span className="flex-1">Why does "{targetTitle}" exist?</span>
            <button
              type="button"
              onClick={() => setPinned((value) => !value)}
              className={cn(
                "ml-auto flex h-6 w-6 items-center justify-center rounded-md border transition-colors",
                pinned ? "border-primary bg-primary/10 text-primary" : "text-muted-foreground hover:bg-muted",
              )}
              title={pinned ? "Unpin" : "Pin this view"}
              aria-label={pinned ? "Unpin" : "Pin"}
            >
              <Pin className="h-3 w-3" />
            </button>
          </SheetTitle>
          {payload?.cached ? (
            <SheetDescription className="text-[10px] uppercase tracking-widest">
              Cached explanation
            </SheetDescription>
          ) : null}
        </SheetHeader>

        {loading && !payload ? (
          <div className="space-y-3 px-4 py-4">
            <Skeleton className="h-16 w-full" />
            <Skeleton className="h-16 w-full" />
            <Skeleton className="h-16 w-full" />
          </div>
        ) : payload ? (
          <div className="flex flex-col gap-4 px-4 py-4">
            {contradictions.length > 0 ? (
              <ContradictionCallout refs={contradictions} />
            ) : null}

            <LineageChain
              lineage={payload.lineage}
              orphan={payload.orphan}
              visionPresent={payload.vision_present}
              onNavigate={onNavigateToNode}
            />

            <ProseSection
              prose={payload.prose}
              error={payload.error}
              orphan={payload.orphan}
              visionPresent={payload.vision_present}
              retrying={retrying}
              onRetry={handleRetryProse}
            />

            <div className="flex items-center justify-end gap-2 border-t pt-3">
              <Button size="sm" variant="outline" onClick={handleShare}>
                <Link2 className="mr-1 h-3 w-3" />
                {shared ? "Link copied" : "Share"}
              </Button>
            </div>
          </div>
        ) : null}
      </SheetContent>
    </Sheet>
  );
}

function ContradictionCallout({ refs }: { refs: WhyContradictionRef[] }) {
  const severities = refs.reduce(
    (acc, c) => {
      acc[c.severity] = (acc[c.severity] ?? 0) + 1;
      return acc;
    },
    { low: 0, medium: 0, high: 0 } as Record<string, number>,
  );
  const tone = severities.high > 0 ? "text-rose-500" : "text-amber-500";
  const border = severities.high > 0 ? "border-rose-500/40 bg-rose-500/5" : "border-amber-500/40 bg-amber-500/5";

  return (
    <div className={cn("flex items-start gap-2 rounded-lg border p-3", border)}>
      <AlertTriangle className={cn("mt-0.5 h-4 w-4 shrink-0", tone)} />
      <div className="flex-1">
        <p className="text-xs font-medium">
          This node is part of {refs.length} open contradiction{refs.length === 1 ? "" : "s"}.
        </p>
        {refs[0]?.explanation ? (
          <p className="mt-1 line-clamp-3 text-[11px] text-muted-foreground">{refs[0].explanation}</p>
        ) : null}
        <p className="mt-1 text-[10px] uppercase tracking-widest text-muted-foreground/80">
          Open the Command Center blockers tab to resolve.
        </p>
      </div>
    </div>
  );
}

function LineageChain({
  lineage,
  orphan,
  visionPresent,
  onNavigate,
}: {
  lineage: WhyLineageCard[];
  orphan: boolean;
  visionPresent: boolean;
  onNavigate?: (nodeType: string, nodeId: number) => void;
}) {
  return (
    <div className="flex flex-col">
      {!visionPresent ? <MissingVisionCard /> : null}

      {lineage.map((card, idx) => (
        <div key={`${card.node_type}-${card.node_id ?? "synth"}-${idx}`} className="flex flex-col items-stretch">
          {idx > 0 || !visionPresent ? <ChainConnector /> : null}
          <LineageCard card={card} onNavigate={onNavigate} />
        </div>
      ))}

      {orphan ? (
        <div className="mt-3 rounded-md border border-dashed bg-muted/30 p-3 text-center text-xs text-muted-foreground">
          No connection to Vision yet.
        </div>
      ) : null}
    </div>
  );
}

function ChainConnector() {
  return (
    <div className="my-1 flex justify-center">
      <ArrowDown className="h-3 w-3 text-muted-foreground/60" />
    </div>
  );
}

function LineageCard({
  card,
  onNavigate,
}: {
  card: WhyLineageCard;
  onNavigate?: (nodeType: string, nodeId: number) => void;
}) {
  const label = card.is_vision ? "Vision" : card.node_type.replace(/_/g, " ");
  const clickable = !card.is_vision && card.node_id !== null && !!onNavigate;

  const content = (
    <div
      className={cn(
        "rounded-lg border p-3 transition-colors",
        card.is_vision && "border-primary/40 bg-primary/5",
        card.is_target && "border-primary bg-primary/10 shadow-sm",
        !card.is_vision && !card.is_target && "bg-card",
        card.stale && !card.is_target && "border-amber-500/40",
        clickable && "hover:border-primary/40 cursor-pointer",
      )}
    >
      <div className="flex items-center gap-1.5">
        {card.is_vision ? (
          <Compass className="h-3 w-3 text-primary" />
        ) : card.is_target ? (
          <Target className="h-3 w-3 text-primary" />
        ) : null}
        <span className="text-[10px] uppercase tracking-widest text-muted-foreground">{label}</span>
        {card.stale && !card.is_target ? (
          <span
            className="inline-flex items-center gap-0.5 rounded-full bg-amber-500/10 px-1.5 py-0.5 text-[9px] font-semibold uppercase text-amber-600"
            title="This ancestor was edited after the target node — its lineage may no longer match."
          >
            <TriangleAlert className="h-2.5 w-2.5" />
            Stale
          </span>
        ) : null}
        {card.is_target ? (
          <span className="text-[10px] text-primary">(this node)</span>
        ) : null}
      </div>

      <p className="mt-1 text-sm font-medium leading-snug">{card.title}</p>

      {card.body ? (
        <p className="mt-1 line-clamp-3 text-xs text-muted-foreground">{card.body}</p>
      ) : null}

      {card.edge_kind && !card.is_target ? (
        <p className="mt-1.5 text-[10px] uppercase tracking-widest text-muted-foreground/60">
          via {card.edge_kind.replace(/_/g, " ")}
        </p>
      ) : null}
    </div>
  );

  if (!clickable) return content;
  return (
    <button
      type="button"
      onClick={() => card.node_id !== null && onNavigate?.(card.node_type, card.node_id)}
      className="w-full text-left"
    >
      {content}
    </button>
  );
}

function MissingVisionCard() {
  return (
    <div className="flex flex-col items-stretch">
      <div className="rounded-lg border border-dashed bg-muted/30 p-3 text-center">
        <p className="text-[10px] uppercase tracking-widest text-muted-foreground">Vision</p>
        <p className="mt-1 text-sm font-medium text-muted-foreground">Not yet set for this project</p>
        <p className="mt-1 text-[11px] text-muted-foreground/80">
          Set a project description to anchor the lineage chain.
        </p>
      </div>
    </div>
  );
}

function ProseSection({
  prose,
  error,
  orphan,
  visionPresent,
  retrying,
  onRetry,
}: {
  prose: string | null;
  error: string | null;
  orphan: boolean;
  visionPresent: boolean;
  retrying: boolean;
  onRetry: () => void;
}) {
  if (error) {
    return (
      <div className="rounded-lg border bg-muted/20 p-3 text-xs text-muted-foreground">
        <p>Couldn't generate the explanation right now.</p>
        <p className="mt-1 text-[11px] text-muted-foreground/80">{error}</p>
        <Button size="sm" variant="outline" className="mt-2 h-7 text-[11px]" onClick={onRetry} disabled={retrying}>
          {retrying ? <Loader2 className="mr-1 h-3 w-3 animate-spin" /> : <RotateCw className="mr-1 h-3 w-3" />}
          Retry
        </Button>
      </div>
    );
  }

  if (!prose) {
    return (
      <div className="rounded-lg border bg-muted/20 p-3 text-xs text-muted-foreground">
        {orphan
          ? "This node isn't connected to the Vision yet. Add parent relationships to explain why it exists."
          : !visionPresent
            ? "This project has no Vision yet, so the chain back to your purpose can't be drawn."
            : "Generating explanation…"}
      </div>
    );
  }

  return (
    <div className="rounded-lg border bg-card p-3">
      <p className="text-sm leading-relaxed text-foreground whitespace-pre-wrap">{prose}</p>
    </div>
  );
}
