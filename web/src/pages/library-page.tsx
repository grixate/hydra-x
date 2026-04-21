import { useEffect, useState } from "react";
import { useParams, useNavigate } from "react-router-dom";
import type { Artifact } from "@/lib/api";
import { api } from "@/lib/api";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { BookOpen, FileText, Paperclip } from "lucide-react";
import { relativeLabel } from "@/lib/utils";
import { motion } from "motion/react";

// Categorize artifact by its type
type LibrarySection = "artifact" | "document" | "reference";

const AGENT_ARTIFACT_TYPES = new Set([
  "competitive_analysis",
  "strategy_memo",
  "project_summary",
  "decision_log",
  "design_language",
]);

const REFERENCE_TYPES = new Set(["reference"]);

function sectionOf(a: Artifact): LibrarySection {
  if (REFERENCE_TYPES.has(a.artifact_type)) return "reference";
  if (AGENT_ARTIFACT_TYPES.has(a.artifact_type) || a.owner_persona) return "artifact";
  return "document";
}

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

function typeLabel(type: string) {
  return TYPE_LABELS[type] ?? type.replace(/_/g, " ");
}

export function LibraryPage() {
  const { projectId } = useParams<{ projectId: string }>();
  const navigate = useNavigate();
  const pid = Number(projectId);

  const [items, setItems] = useState<Artifact[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState("");

  useEffect(() => {
    if (!pid || isNaN(pid)) return;
    setLoading(true);
    api
      .listArtifacts(pid, { status: "active" })
      .then(setItems)
      .catch(() => {})
      .finally(() => setLoading(false));
  }, [pid]);

  const filtered = search.trim()
    ? items.filter((a) => a.title.toLowerCase().includes(search.toLowerCase()))
    : items;

  const agentArtifacts = filtered.filter((a) => sectionOf(a) === "artifact");
  const documents = filtered.filter((a) => sectionOf(a) === "document");
  const references = filtered.filter((a) => sectionOf(a) === "reference");

  if (loading) {
    return (
      <div className="mx-auto max-w-2xl space-y-4 px-4 py-6">
        <Skeleton className="h-8 w-48" />
        <Skeleton className="h-16 w-full" />
        <Skeleton className="h-16 w-full" />
        <Skeleton className="h-16 w-full" />
      </div>
    );
  }

  const isEmpty = items.length === 0;

  return (
    <div className="mx-auto max-w-2xl px-4 py-6">
      <div className="mb-6 flex items-center justify-between">
        <h1 className="text-xl font-semibold">Library</h1>
      </div>

      {/* Search */}
      {!isEmpty && (
        <div className="mb-6">
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search library..."
            className="w-full rounded-lg border bg-background px-3 py-2 text-sm placeholder:text-muted-foreground/60 focus:outline-none focus:ring-1 focus:ring-ring"
          />
        </div>
      )}

      {/* Empty state */}
      {isEmpty && (
        <motion.div
          initial={{ opacity: 0, scale: 0.97 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ duration: 0.4, delay: 0.1 }}
          className="flex flex-col items-center justify-center py-24 text-center"
        >
          <div className="mb-4 flex h-12 w-12 items-center justify-center rounded-full bg-muted">
            <BookOpen className="h-5 w-5 text-muted-foreground" />
          </div>
          <p className="text-base font-medium text-foreground">Your library is empty</p>
          <p className="mt-2 max-w-sm text-sm text-muted-foreground">
            The library holds all documents and artifacts your agents produce — specs,
            competitive analyses, strategy memos, and reports. Items will appear here
            as your agents work.
          </p>
        </motion.div>
      )}

      {/* Agent Artifacts */}
      {agentArtifacts.length > 0 && (
        <LibrarySection
          title="Agent artifacts"
          icon={<BookOpen className="h-3.5 w-3.5" />}
          items={agentArtifacts}
          onNavigate={(id) => navigate(`/projects/${projectId}/library/${id}`)}
        />
      )}

      {/* Documents */}
      {documents.length > 0 && (
        <LibrarySection
          title="Documents"
          icon={<FileText className="h-3.5 w-3.5" />}
          items={documents}
          onNavigate={(id) => navigate(`/projects/${projectId}/library/${id}`)}
        />
      )}

      {/* Reference files */}
      {references.length > 0 && (
        <LibrarySection
          title="Reference files"
          icon={<Paperclip className="h-3.5 w-3.5" />}
          items={references}
          onNavigate={(id) => navigate(`/projects/${projectId}/library/${id}`)}
        />
      )}

      {/* No results from search */}
      {!isEmpty && filtered.length === 0 && search.trim() && (
        <p className="py-12 text-center text-sm text-muted-foreground">
          No items matching "{search}"
        </p>
      )}
    </div>
  );
}

function LibrarySection({
  title,
  icon,
  items,
  onNavigate,
}: {
  title: string;
  icon: React.ReactNode;
  items: Artifact[];
  onNavigate: (id: number) => void;
}) {
  return (
    <section className="mb-8">
      <div className="mb-3 flex items-center gap-2 text-xs font-semibold uppercase tracking-widest text-muted-foreground">
        {icon}
        {title}
      </div>
      <div className="space-y-1">
        {items.map((item, i) => (
          <motion.button
            key={item.id}
            initial={{ opacity: 0, y: 6 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.2, delay: i * 0.03 }}
            onClick={() => onNavigate(item.id)}
            className="flex w-full items-center gap-3 rounded-lg px-3 py-3 text-left transition-colors hover:bg-muted/50"
          >
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2">
                <span className="text-sm font-medium truncate">{item.title}</span>
                {item.version > 1 && (
                  <Badge variant="secondary" className="text-[9px] shrink-0">
                    v{item.version}
                  </Badge>
                )}
              </div>
              <div className="mt-0.5 flex items-center gap-2 text-xs text-muted-foreground">
                {item.owner_persona && (
                  <span className="capitalize">by {item.owner_persona.replace("_", " ")}</span>
                )}
                {item.owner_persona && <span>&middot;</span>}
                <span>{typeLabel(item.artifact_type)}</span>
              </div>
            </div>
            <span className="shrink-0 text-xs text-muted-foreground">
              {relativeLabel(item.updated_at)}
            </span>
          </motion.button>
        ))}
      </div>
    </section>
  );
}
