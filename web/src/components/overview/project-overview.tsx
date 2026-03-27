import { ArrowRight, Download, MessagesSquare } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Separator } from "@/components/ui/separator";
import type { Insight, ProductConversation, Project, Requirement, Source } from "@/types";
import { formatDate, relativeLabel } from "@/lib/utils";

type Section = "overview" | "sources" | "chat" | "insights" | "requirements";

export function ProjectOverview({
  project,
  sources,
  insights,
  requirements,
  conversations,
  onSelectSection,
  onOpenExport,
}: {
  project: Project | null;
  sources: Source[];
  insights: Insight[];
  requirements: Requirement[];
  conversations: ProductConversation[];
  onSelectSection: (section: Section) => void;
  onOpenExport: () => void;
}) {
  const completedSources = sources.filter((source) => source.processing_status === "completed").length;
  const acceptedInsights = insights.filter((insight) => insight.status === "accepted").length;
  const groundedRequirements = requirements.filter((requirement) => requirement.grounded).length;
  const acceptedRequirements = requirements.filter((requirement) => requirement.status === "accepted").length;

  const recentSources = [...sources]
    .sort(sortByUpdatedAt)
    .slice(0, 3);
  const recentInsights = [...insights]
    .sort(sortByUpdatedAt)
    .slice(0, 3);
  const recentConversations = [...conversations]
    .sort(sortByUpdatedAt)
    .slice(0, 3);

  return (
    <div className="space-y-6">
      <div className="grid gap-6 xl:grid-cols-[minmax(0,1.2fr)_minmax(23rem,0.8fr)]">
        <Card className="overflow-hidden bg-[linear-gradient(135deg,rgba(33,27,22,0.96),rgba(79,57,39,0.92))] text-[var(--paper)]">
          <CardContent className="p-8">
            <p className="text-[10px] font-bold uppercase tracking-[0.35em] text-white/60">
              Project command surface
            </p>
            <h2 className="mt-4 max-w-2xl font-display text-5xl leading-tight">
              {project?.name ?? "Hydra Product"}
            </h2>
            <p className="mt-4 max-w-2xl text-sm leading-7 text-white/72">
              Operate the full evidence chain from ingest to grounded chat to accepted requirements, then export the full project ledger as a portable package.
            </p>

            <div className="mt-8 flex flex-wrap gap-3">
              <Button type="button" onClick={() => onSelectSection("chat")}>
                <MessagesSquare className="h-4 w-4" />
                Open grounded chat
              </Button>
              <Button type="button" variant="secondary" onClick={onOpenExport}>
                <Download className="h-4 w-4" />
                Export project
              </Button>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-4">
            <p className="text-[10px] font-bold uppercase tracking-[0.3em] text-[var(--ink-soft)]">
              Coverage snapshot
            </p>
            <CardTitle>Readiness pulse</CardTitle>
            <CardDescription>
              A fast read on whether the project has enough evidence, synthesis, and grounded requirements to ship a snapshot.
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <MetricRow
              label="Source processing"
              value={`${completedSources}/${sources.length || 0}`}
              detail="completed"
            />
            <MetricRow
              label="Accepted insights"
              value={`${acceptedInsights}/${insights.length || 0}`}
              detail="validated findings"
            />
            <MetricRow
              label="Grounded requirements"
              value={`${groundedRequirements}/${requirements.length || 0}`}
              detail="traceable requirements"
            />
            <MetricRow
              label="Accepted requirements"
              value={`${acceptedRequirements}/${requirements.length || 0}`}
              detail="ready for downstream delivery"
            />
          </CardContent>
        </Card>
      </div>

      <div className="grid gap-6 md:grid-cols-2 2xl:grid-cols-4">
        <StatCard
          title="Sources"
          value={sources.length}
          detail={`${completedSources} processed`}
          accent="warning"
        />
        <StatCard
          title="Insights"
          value={insights.length}
          detail={`${acceptedInsights} accepted`}
          accent="accent"
        />
        <StatCard
          title="Requirements"
          value={requirements.length}
          detail={`${groundedRequirements} grounded`}
          accent="success"
        />
        <StatCard
          title="Conversations"
          value={conversations.length}
          detail={conversations[0]?.updated_at ? `last touch ${relativeLabel(conversations[0].updated_at)}` : "no live threads yet"}
          accent="neutral"
        />
      </div>

      <div className="grid gap-6 xl:grid-cols-3">
        <Card>
          <CardHeader className="pb-4">
            <p className="text-[10px] font-bold uppercase tracking-[0.3em] text-[var(--ink-soft)]">
              Quick routes
            </p>
            <CardTitle>Move through the graph</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <ActionRow
              title="Inspect source grounding"
              detail="Review chunks and processing state before promoting evidence."
              onClick={() => onSelectSection("sources")}
            />
            <ActionRow
              title="Synthesize in chat"
              detail="Use the researcher or strategist on the live conversation rail."
              onClick={() => onSelectSection("chat")}
            />
            <ActionRow
              title="Refine the evidence model"
              detail="Create or edit insights and connect them to requirements."
              onClick={() => onSelectSection("insights")}
            />
            <ActionRow
              title="Validate final requirements"
              detail="Check grounded status before passing work downstream."
              onClick={() => onSelectSection("requirements")}
            />
          </CardContent>
        </Card>

        <ActivityCard
          eyebrow="Latest sources"
          title="Fresh evidence"
          empty="No sources yet. Start by ingesting raw material."
          items={recentSources.map((source) => ({
            id: source.id,
            label: source.title,
            meta: `${source.source_chunk_count} chunks`,
            badge: source.processing_status,
            updated_at: source.updated_at,
          }))}
        />

        <ActivityCard
          eyebrow="Recent analysis"
          title="Insight and chat motion"
          empty="No synthesis yet. Grounded chat and insight creation will appear here."
          items={[
            ...recentInsights.map((insight) => ({
              id: `insight-${insight.id}`,
              label: insight.title,
              meta: `${insight.evidence.length} evidence links`,
              badge: insight.status,
              updated_at: insight.updated_at,
            })),
            ...recentConversations.map((conversation) => ({
              id: `conversation-${conversation.id}`,
              label: conversation.title || "Untitled conversation",
              meta: `${conversation.message_count} turns`,
              badge: conversation.persona,
              updated_at: conversation.updated_at,
            })),
          ]
            .sort((left, right) => sortByUpdatedAt(left, right))
            .slice(0, 4)}
        />
      </div>
    </div>
  );
}

function MetricRow({
  label,
  value,
  detail,
}: {
  label: string;
  value: string;
  detail: string;
}) {
  return (
    <div className="rounded-[1.4rem] border border-[var(--line)] bg-[var(--paper-strong)] px-4 py-3">
      <div className="flex items-center justify-between gap-4">
        <div>
          <p className="text-sm font-semibold text-[var(--ink)]">{label}</p>
          <p className="text-xs text-[var(--ink-soft)]">{detail}</p>
        </div>
        <p className="font-display text-2xl text-[var(--ink)]">{value}</p>
      </div>
    </div>
  );
}

function StatCard({
  title,
  value,
  detail,
  accent,
}: {
  title: string;
  value: number;
  detail: string;
  accent: "accent" | "neutral" | "success" | "warning";
}) {
  return (
    <Card>
      <CardContent className="p-6">
        <div className="flex items-center justify-between gap-4">
          <div>
            <p className="text-[10px] font-bold uppercase tracking-[0.3em] text-[var(--ink-soft)]">
              {title}
            </p>
            <p className="mt-3 font-display text-4xl text-[var(--ink)]">{value}</p>
            <p className="mt-2 text-sm text-[var(--ink-soft)]">{detail}</p>
          </div>
          <Badge variant={accent}>{detail}</Badge>
        </div>
      </CardContent>
    </Card>
  );
}

function ActionRow({
  title,
  detail,
  onClick,
}: {
  title: string;
  detail: string;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="flex w-full items-center justify-between gap-4 rounded-[1.4rem] border border-[var(--line)] bg-white/70 px-4 py-4 text-left transition hover:border-[var(--accent-strong)] hover:bg-white"
    >
      <div>
        <p className="font-semibold text-[var(--ink)]">{title}</p>
        <p className="mt-1 text-sm text-[var(--ink-soft)]">{detail}</p>
      </div>
      <ArrowRight className="h-4 w-4 text-[var(--ink-soft)]" />
    </button>
  );
}

function ActivityCard({
  eyebrow,
  title,
  empty,
  items,
}: {
  eyebrow: string;
  title: string;
  empty: string;
  items: Array<{
    id: string | number;
    label: string;
    meta: string;
    badge: string;
    updated_at?: string;
  }>;
}) {
  return (
    <Card>
      <CardHeader className="pb-4">
        <p className="text-[10px] font-bold uppercase tracking-[0.3em] text-[var(--ink-soft)]">
          {eyebrow}
        </p>
        <CardTitle>{title}</CardTitle>
      </CardHeader>
      <CardContent>
        {items.length === 0 ? (
          <div className="rounded-[1.4rem] border border-dashed border-[var(--line)] bg-[var(--paper-strong)] p-5 text-sm text-[var(--ink-soft)]">
            {empty}
          </div>
        ) : (
          <div className="space-y-3">
            {items.map((item, index) => (
              <div key={item.id}>
                {index > 0 ? <Separator className="mb-3" /> : null}
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <p className="font-semibold text-[var(--ink)]">{item.label}</p>
                    <p className="mt-1 text-sm text-[var(--ink-soft)]">{item.meta}</p>
                    <p className="mt-2 text-xs text-[var(--ink-soft)]">
                      {item.updated_at ? formatDate(item.updated_at) : "Pending"}
                    </p>
                  </div>
                  <Badge variant="neutral">{item.badge}</Badge>
                </div>
              </div>
            ))}
          </div>
        )}
      </CardContent>
    </Card>
  );
}

function sortByUpdatedAt<T extends { updated_at?: string }>(left: T, right: T) {
  const leftTime = left.updated_at ? new Date(left.updated_at).getTime() : 0;
  const rightTime = right.updated_at ? new Date(right.updated_at).getTime() : 0;

  return rightTime - leftTime;
}
