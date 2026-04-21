import { useEffect, useState } from "react";
import { useParams, useNavigate } from "react-router-dom";
import { api } from "@/lib/api";
import type { Artifact, ArtifactVersion } from "@/lib/api";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { ArrowLeft, Download, Clock } from "lucide-react";
import { cn } from "@/lib/utils";
import { relativeLabel } from "@/lib/utils";
import Markdown from "react-markdown";

const TYPE_LABELS: Record<string, string> = {
  competitive_analysis: "Competitive Analysis",
  strategy_memo: "Strategy Memo",
  project_summary: "Project Summary",
  decision_log: "Decision Log",
  design_language: "Design Language",
  spec: "Spec",
  campaign: "Campaign",
  report: "Report",
  brief: "Brief",
  reference: "Reference",
  custom: "Document",
};

export function LibraryDetailPage() {
  const { projectId, artifactId } = useParams<{ projectId: string; artifactId: string }>();
  const navigate = useNavigate();
  const pid = Number(projectId);
  const aid = Number(artifactId);

  const [artifact, setArtifact] = useState<Artifact | null>(null);
  const [versions, setVersions] = useState<ArtifactVersion[]>([]);
  const [loading, setLoading] = useState(true);
  const [showVersions, setShowVersions] = useState(false);
  const [error, setError] = useState(false);

  useEffect(() => {
    if (!pid || !aid || isNaN(pid) || isNaN(aid)) {
      setError(true);
      setLoading(false);
      return;
    }
    Promise.all([
      api.getArtifact(pid, aid),
      api.listArtifactVersions(pid, aid).catch(() => []),
    ])
      .then(([a, v]) => {
        setArtifact(a);
        setVersions(v);
      })
      .catch(() => setError(true))
      .finally(() => setLoading(false));
  }, [pid, aid]);

  const handleExport = () => {
    if (!artifact) return;
    const blob = new Blob([artifact.body ?? ""], { type: "text/markdown" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `${artifact.title.replace(/[^a-zA-Z0-9-_ ]/g, "")}.md`;
    a.click();
    URL.revokeObjectURL(url);
  };

  const goBack = () => navigate(`/projects/${projectId}/library`);

  if (loading) {
    return (
      <div className="mx-auto max-w-3xl px-4 py-6">
        <Skeleton className="h-8 w-64 mb-4" />
        <Skeleton className="h-96 w-full" />
      </div>
    );
  }

  if (error || !artifact) {
    return (
      <div className="flex h-full flex-col items-center justify-center gap-3 text-sm text-muted-foreground">
        <p>Item not found</p>
        <Button variant="outline" size="sm" onClick={goBack}>
          <ArrowLeft className="mr-1.5 h-3 w-3" />
          Back to Library
        </Button>
      </div>
    );
  }

  const typeLabel = TYPE_LABELS[artifact.artifact_type] ?? artifact.artifact_type;

  return (
    <div className="h-full overflow-auto">
      {/* Header */}
      <div className="sticky top-0 z-10 border-b bg-background/95 backdrop-blur-sm">
        <div className="mx-auto flex max-w-3xl items-center justify-between px-4 py-3">
          <div className="flex items-center gap-3 min-w-0">
            <button
              onClick={goBack}
              className="text-muted-foreground hover:text-foreground transition-colors shrink-0"
            >
              <ArrowLeft className="h-4 w-4" />
            </button>
            <div className="min-w-0">
              <h1 className="text-sm font-semibold truncate">{artifact.title}</h1>
              <div className="flex items-center gap-2 text-xs text-muted-foreground">
                <span>{typeLabel}</span>
                <span>&middot;</span>
                <span>v{artifact.version}</span>
                {artifact.owner_persona && (
                  <>
                    <span>&middot;</span>
                    <span className="capitalize">by {artifact.owner_persona.replace("_", " ")}</span>
                  </>
                )}
              </div>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <Button
              variant={showVersions ? "secondary" : "outline"}
              size="sm"
              onClick={() => setShowVersions((v) => !v)}
            >
              <Clock className="mr-1.5 h-3 w-3" />
              History
              {versions.length > 0 && (
                <Badge variant="secondary" className="ml-1.5 text-[9px] px-1 py-0 h-4">
                  {versions.length}
                </Badge>
              )}
            </Button>
            <Button variant="outline" size="sm" onClick={handleExport}>
              <Download className="mr-1.5 h-3 w-3" />
              Export
            </Button>
          </div>
        </div>
      </div>

      <div className="mx-auto max-w-3xl px-4 py-8">
        {/* Version history panel */}
        {showVersions && (
          <div className="mb-8 rounded-lg border bg-muted/20 p-4">
            <p className="mb-3 text-xs font-semibold uppercase tracking-widest text-muted-foreground">
              Version history
            </p>
            {versions.length === 0 ? (
              <p className="text-sm text-muted-foreground py-2">
                No version history yet. Changes will appear here after the first update.
              </p>
            ) : (
              <div className="space-y-1">
                {versions.map((v) => (
                  <div
                    key={v.id}
                    className={cn(
                      "flex items-start justify-between rounded-md px-3 py-2 text-sm",
                      v.version === artifact.version && "bg-muted/50",
                    )}
                  >
                    <div className="min-w-0 flex-1">
                      <span className="font-medium">v{v.version}</span>
                      {v.change_summary && (
                        <span className="ml-2 text-muted-foreground">{v.change_summary}</span>
                      )}
                    </div>
                    <div className="shrink-0 ml-3 text-xs text-muted-foreground text-right">
                      {v.updated_by && (
                        <span className="capitalize">{v.updated_by.replace("_", " ")} &middot; </span>
                      )}
                      {relativeLabel(v.inserted_at)}
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        )}

        {/* Markdown body */}
        {artifact.body ? (
          <article className="prose prose-sm prose-neutral dark:prose-invert max-w-none">
            <Markdown>{artifact.body}</Markdown>
          </article>
        ) : (
          <p className="py-12 text-center text-sm text-muted-foreground">
            This item has no content yet.
          </p>
        )}

        {/* Metadata footer */}
        <div className="mt-12 border-t pt-6 text-xs text-muted-foreground space-y-1">
          <p>Updated {relativeLabel(artifact.updated_at)}</p>
          <p>
            Created{" "}
            {new Date(artifact.inserted_at).toLocaleDateString("en-US", {
              year: "numeric",
              month: "long",
              day: "numeric",
            })}
          </p>
          {artifact.last_updated_by && (
            <p className="capitalize">
              Last updated by {artifact.last_updated_by.replace("_", " ")}
            </p>
          )}
        </div>
      </div>
    </div>
  );
}
