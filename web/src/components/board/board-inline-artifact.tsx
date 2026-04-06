import { useState, useEffect } from "react";
import { Card, CardContent } from "@/components/ui/card";
import { ChevronDown, ChevronRight, FileText } from "lucide-react";
import { api, type Artifact } from "@/lib/api";

type BoardInlineArtifactProps = {
  projectId: number;
  artifactId: number;
};

const ARTIFACT_CACHE_TTL_MS = 5 * 60 * 1000;
const artifactCache = new Map<string, { data: Artifact; fetchedAt: number }>();

function getCachedArtifact(key: string): Artifact | null {
  const entry = artifactCache.get(key);
  if (!entry) return null;
  if (Date.now() - entry.fetchedAt > ARTIFACT_CACHE_TTL_MS) {
    artifactCache.delete(key);
    return null;
  }
  return entry.data;
}

export function BoardInlineArtifact({ projectId, artifactId }: BoardInlineArtifactProps) {
  const [artifact, setArtifact] = useState<Artifact | null>(null);
  const [error, setError] = useState(false);
  const [expanded, setExpanded] = useState(false);

  const cacheKey = `${projectId}-${artifactId}`;

  useEffect(() => {
    const cached = getCachedArtifact(cacheKey);
    if (cached) {
      setArtifact(cached);
      return;
    }

    let cancelled = false;

    api
      .getArtifact(projectId, artifactId)
      .then((result) => {
        if (cancelled) return;
        artifactCache.set(cacheKey, { data: result, fetchedAt: Date.now() });
        setArtifact(result);
      })
      .catch(() => {
        if (!cancelled) setError(true);
      });

    return () => {
      cancelled = true;
    };
  }, [projectId, artifactId, cacheKey]);

  if (error) {
    return (
      <Card className="my-2 border-dashed opacity-60">
        <CardContent className="px-4 py-3 text-xs text-muted-foreground">
          Artifact not found: #{artifactId}
        </CardContent>
      </Card>
    );
  }

  if (!artifact) {
    return (
      <Card className="my-2 animate-pulse">
        <CardContent className="px-4 py-3">
          <div className="h-4 w-48 rounded bg-muted" />
          <div className="mt-2 h-3 w-72 rounded bg-muted" />
        </CardContent>
      </Card>
    );
  }

  // Preview: first 300 chars
  const preview = artifact.body.length > 300
    ? artifact.body.slice(0, 300) + "..."
    : artifact.body;

  return (
    <Card className="my-2 border-l-4 border-l-indigo-400">
      <CardContent className="px-4 py-3 space-y-2">
        {/* Header — clickable to expand/collapse */}
        <button
          className="flex w-full items-center gap-2 text-left"
          onClick={() => setExpanded(!expanded)}
        >
          {expanded ? (
            <ChevronDown className="h-3.5 w-3.5 text-muted-foreground shrink-0" />
          ) : (
            <ChevronRight className="h-3.5 w-3.5 text-muted-foreground shrink-0" />
          )}
          <FileText className="h-3.5 w-3.5 text-indigo-500 shrink-0" />
          <span className="text-sm font-semibold">{artifact.title}</span>
          <span className="text-[10px] text-muted-foreground ml-auto shrink-0">
            v{artifact.version}
          </span>
        </button>

        {/* Meta line */}
        <div className="text-[10px] text-muted-foreground pl-7">
          {artifact.artifact_type.replace(/_/g, " ")} &middot; Updated by {artifact.last_updated_by ?? "system"}
        </div>

        {/* Content — collapsed = preview, expanded = full */}
        <div className="pl-7">
          <pre className="whitespace-pre-wrap text-xs leading-relaxed text-muted-foreground font-sans">
            {expanded ? artifact.body : preview}
          </pre>

          {/* Actions */}
          <div className="mt-2 flex gap-2">
            <a
              href={`/projects/${projectId}/artifacts/${artifactId}`}
              target="_blank"
              rel="noopener noreferrer"
              className="text-[10px] text-primary hover:underline"
            >
              View full artifact
            </a>
          </div>
        </div>
      </CardContent>
    </Card>
  );
}
