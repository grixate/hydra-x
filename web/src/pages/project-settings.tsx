import { useCallback, useEffect, useState } from "react";
import { useParams, useNavigate } from "react-router-dom";
import { api } from "@/lib/api";
import type { Constraint, Routine, KnowledgeEntry } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Plus, Trash2, Play, FolderUp, User } from "lucide-react";
import { cn } from "@/lib/utils";
import { IdentityBootstrapDialog } from "@/components/onboarding/identity-bootstrap-dialog";
import { showToast } from "@/components/ui/toast-notification";

export function SettingsPage() {
  const { projectId } = useParams<{ projectId: string }>();
  const pid = Number(projectId);

  return (
    <div className="space-y-8 p-6">
      <h1 className="text-xl font-semibold">Settings</h1>
      <IdentitySection />
      <RoutinesSection projectId={pid} />
      <KnowledgeSection projectId={pid} />
      <BulkImportSection projectId={pid} />
      <ConstraintsSection projectId={pid} />
    </div>
  );
}

function IdentitySection() {
  const [open, setOpen] = useState(false);

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Your identity & cross-project principles</CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        <p className="text-sm text-muted-foreground">
          Seed your "You" scope with principles, identity facts, and values. Every project you
          start inherits them, so agents stay consistent with how you actually think.
        </p>
        <Button size="sm" variant="outline" onClick={() => setOpen(true)}>
          <User className="mr-1 h-3.5 w-3.5" />
          Update identity
        </Button>
        <IdentityBootstrapDialog
          open={open}
          onClose={() => setOpen(false)}
          onSeeded={(count) => {
            if (count > 0) showToast(`Saved ${count} to your "You" scope.`);
          }}
        />
      </CardContent>
    </Card>
  );
}

// Usage section moved to standalone /usage page
// Watch Targets section moved to /watch page

/* ───────────── Routines ───────────── */

function RoutinesSection({ projectId }: { projectId: number }) {
  const [routines, setRoutines] = useState<Routine[]>([]);
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [form, setForm] = useState({
    title: "",
    prompt_template: "",
    assigned_persona: "researcher",
    schedule_type: "daily",
  });
  const [adding, setAdding] = useState(false);

  useEffect(() => {
    if (isNaN(projectId)) return;
    api
      .listRoutines(projectId)
      .then(setRoutines)
      .catch(() => {})
      .finally(() => setLoading(false));
  }, [projectId]);

  const handleCreate = useCallback(async () => {
    if (!form.title.trim() || !form.prompt_template.trim() || adding) return;
    setAdding(true);
    try {
      const r = await api.createRoutine(projectId, {
        title: form.title,
        prompt_template: form.prompt_template,
        assigned_persona: form.assigned_persona,
        schedule_type: form.schedule_type,
      });
      setRoutines((prev) => [...prev, r]);
      setForm({ title: "", prompt_template: "", assigned_persona: "researcher", schedule_type: "daily" });
      setShowForm(false);
    } catch {}
    setAdding(false);
  }, [projectId, form, adding]);

  const handleRun = useCallback(
    async (id: number) => {
      try {
        await api.runRoutine(projectId, id);
        // Refresh to get updated last_run_at
        const updated = await api.listRoutines(projectId);
        setRoutines(updated);
      } catch {}
    },
    [projectId],
  );

  const handleDelete = useCallback(
    async (id: number) => {
      try {
        await api.deleteRoutine(projectId, id);
        setRoutines((prev) => prev.filter((r) => r.id !== id));
      } catch {}
    },
    [projectId],
  );

  if (loading) return <SettingSkeleton title="Routines" />;

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between">
        <CardTitle className="text-sm">Routines</CardTitle>
        <Button
          variant="outline"
          size="sm"
          onClick={() => setShowForm(!showForm)}
        >
          <Plus className="mr-1.5 h-3 w-3" />
          New
        </Button>
      </CardHeader>
      <CardContent className="space-y-3">
        {showForm && (
          <div className="space-y-2 rounded-lg border p-3">
            <Input
              placeholder="Routine title"
              value={form.title}
              onChange={(e) => setForm((f) => ({ ...f, title: e.target.value }))}
            />
            <textarea
              placeholder="Prompt template (use {{variable}} for placeholders)"
              value={form.prompt_template}
              onChange={(e) =>
                setForm((f) => ({ ...f, prompt_template: e.target.value }))
              }
              rows={3}
              className="w-full resize-none rounded-lg border bg-background px-3 py-2 text-sm placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-ring"
            />
            <div className="flex gap-2">
              <Select
                value={form.assigned_persona}
                onValueChange={(v) =>
                  setForm((f) => ({ ...f, assigned_persona: v }))
                }
              >
                <SelectTrigger className="w-36">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="researcher">Researcher</SelectItem>
                  <SelectItem value="strategist">Strategist</SelectItem>
                  <SelectItem value="architect">Architect</SelectItem>
                  <SelectItem value="designer">Designer</SelectItem>
                  <SelectItem value="memory_agent">Memory</SelectItem>
                </SelectContent>
              </Select>
              <Select
                value={form.schedule_type}
                onValueChange={(v) =>
                  setForm((f) => ({ ...f, schedule_type: v }))
                }
              >
                <SelectTrigger className="w-36">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="interval">Interval</SelectItem>
                  <SelectItem value="daily">Daily</SelectItem>
                  <SelectItem value="weekly">Weekly</SelectItem>
                  <SelectItem value="cron">Cron</SelectItem>
                  <SelectItem value="event">Event</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="flex justify-end gap-2">
              <Button
                variant="ghost"
                size="sm"
                onClick={() => setShowForm(false)}
              >
                Cancel
              </Button>
              <Button
                size="sm"
                onClick={handleCreate}
                disabled={!form.title.trim() || !form.prompt_template.trim() || adding}
              >
                Create
              </Button>
            </div>
          </div>
        )}

        {routines.length === 0 && !showForm && (
          <p className="text-sm text-muted-foreground">
            No routines configured. Add recurring agent tasks.
          </p>
        )}

        {routines.map((r) => (
          <div
            key={r.id}
            className="flex items-center justify-between rounded-lg border px-3 py-2"
          >
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2">
                <span className="text-sm font-medium">{r.title}</span>
                <Badge variant="secondary" className="text-[9px]">
                  {r.assigned_persona}
                </Badge>
                <Badge variant="outline" className="text-[9px]">
                  {r.schedule_type}
                </Badge>
                <Badge
                  className={cn(
                    "text-[9px]",
                    r.status === "active"
                      ? "bg-green-100 text-green-800"
                      : "bg-muted text-muted-foreground",
                  )}
                >
                  {r.status}
                </Badge>
              </div>
              {r.last_run_at && (
                <p className="mt-0.5 text-[10px] text-muted-foreground">
                  Last run:{" "}
                  {new Date(r.last_run_at).toLocaleString([], {
                    dateStyle: "short",
                    timeStyle: "short",
                  })}
                  {r.last_run_status && ` (${r.last_run_status})`}
                </p>
              )}
            </div>
            <div className="flex items-center gap-1">
              <Button
                variant="ghost"
                size="icon"
                className="h-7 w-7"
                onClick={() => handleRun(r.id)}
                title="Run now"
              >
                <Play className="h-3.5 w-3.5" />
              </Button>
              <Button
                variant="ghost"
                size="icon"
                className="h-7 w-7 text-muted-foreground hover:text-destructive"
                onClick={() => handleDelete(r.id)}
              >
                <Trash2 className="h-3.5 w-3.5" />
              </Button>
            </div>
          </div>
        ))}
      </CardContent>
    </Card>
  );
}

/* ───────────── Knowledge Library ───────────── */

function KnowledgeSection({ projectId }: { projectId: number }) {
  const [entries, setEntries] = useState<KnowledgeEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [form, setForm] = useState({
    title: "",
    content: "",
    entry_type: "reference",
    source_url: "",
  });
  const [adding, setAdding] = useState(false);

  useEffect(() => {
    if (isNaN(projectId)) return;
    api
      .listKnowledgeEntries(projectId)
      .then(setEntries)
      .catch(() => {})
      .finally(() => setLoading(false));
  }, [projectId]);

  const handleCreate = useCallback(async () => {
    if (!form.title.trim() || !form.content.trim() || adding) return;
    setAdding(true);
    try {
      const ke = await api.createKnowledgeEntry(projectId, {
        title: form.title,
        content: form.content,
        entry_type: form.entry_type,
        source_url: form.source_url || undefined,
      });
      setEntries((prev) => [...prev, ke]);
      setForm({ title: "", content: "", entry_type: "reference", source_url: "" });
      setShowForm(false);
    } catch {}
    setAdding(false);
  }, [projectId, form, adding]);

  const handleDelete = useCallback(
    async (id: number) => {
      try {
        await api.deleteKnowledgeEntry(projectId, id);
        setEntries((prev) => prev.filter((e) => e.id !== id));
      } catch {}
    },
    [projectId],
  );

  if (loading) return <SettingSkeleton title="Knowledge Library" />;

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between">
        <CardTitle className="text-sm">Knowledge Library</CardTitle>
        <Button
          variant="outline"
          size="sm"
          onClick={() => setShowForm(!showForm)}
        >
          <Plus className="mr-1.5 h-3 w-3" />
          New
        </Button>
      </CardHeader>
      <CardContent className="space-y-3">
        {showForm && (
          <div className="space-y-2 rounded-lg border p-3">
            <Input
              placeholder="Title"
              value={form.title}
              onChange={(e) => setForm((f) => ({ ...f, title: e.target.value }))}
            />
            <textarea
              placeholder="Content (reference material, guidelines, etc.)"
              value={form.content}
              onChange={(e) =>
                setForm((f) => ({ ...f, content: e.target.value }))
              }
              rows={4}
              className="w-full resize-none rounded-lg border bg-background px-3 py-2 text-sm placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-ring"
            />
            <div className="flex gap-2">
              <Select
                value={form.entry_type}
                onValueChange={(v) =>
                  setForm((f) => ({ ...f, entry_type: v }))
                }
              >
                <SelectTrigger className="w-36">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="reference">Reference</SelectItem>
                  <SelectItem value="guideline">Guideline</SelectItem>
                  <SelectItem value="example">Example</SelectItem>
                  <SelectItem value="glossary">Glossary</SelectItem>
                </SelectContent>
              </Select>
              <Input
                placeholder="Source URL (optional)"
                value={form.source_url}
                onChange={(e) =>
                  setForm((f) => ({ ...f, source_url: e.target.value }))
                }
                className="flex-1"
              />
            </div>
            <div className="flex justify-end gap-2">
              <Button
                variant="ghost"
                size="sm"
                onClick={() => setShowForm(false)}
              >
                Cancel
              </Button>
              <Button
                size="sm"
                onClick={handleCreate}
                disabled={!form.title.trim() || !form.content.trim() || adding}
              >
                Create
              </Button>
            </div>
          </div>
        )}

        {entries.length === 0 && !showForm && (
          <p className="text-sm text-muted-foreground">
            No knowledge entries. Add reference material for your agents.
          </p>
        )}

        {entries.map((ke) => (
          <div
            key={ke.id}
            className="flex items-start justify-between rounded-lg border px-3 py-2"
          >
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2">
                <span className="text-sm font-medium">{ke.title}</span>
                <Badge variant="secondary" className="text-[9px]">
                  {ke.entry_type}
                </Badge>
              </div>
              <p className="mt-0.5 text-xs text-muted-foreground line-clamp-2">
                {ke.content}
              </p>
            </div>
            <Button
              variant="ghost"
              size="icon"
              className="h-7 w-7 shrink-0 text-muted-foreground hover:text-destructive"
              onClick={() => handleDelete(ke.id)}
            >
              <Trash2 className="h-3.5 w-3.5" />
            </Button>
          </div>
        ))}
      </CardContent>
    </Card>
  );
}

/* ───────────── Bulk Import ───────────── */

function BulkImportSection({ projectId }: { projectId: number }) {
  const navigate = useNavigate();

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-sm">Bulk import</CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        <p className="text-sm text-muted-foreground leading-relaxed">
          Import a large collection of documents to bootstrap your product graph.
          Best for onboarding existing research, meeting notes, design docs, and prior knowledge.
        </p>
        <p className="text-sm text-muted-foreground leading-relaxed">
          The Researcher agent will process files in batches, extract insights, and
          cross-reference with existing graph knowledge. This may take several minutes
          for large collections.
        </p>
        <Button
          variant="outline"
          size="sm"
          onClick={() => navigate(`/projects/${projectId}/import`)}
        >
          <FolderUp className="mr-2 h-4 w-4" />
          Import files
        </Button>
        <p className="text-xs text-muted-foreground">
          Supported: PDF, DOCX, MD, TXT, CSV — Recommended: up to 500 files per import
        </p>
      </CardContent>
    </Card>
  );
}

/* ───────────── Constraints ───────────── */

function ConstraintsSection({ projectId }: { projectId: number }) {
  const [constraints, setConstraints] = useState<Constraint[]>([]);
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [form, setForm] = useState({
    title: "",
    body: "",
    scope: "project",
    enforcement: "hard",
  });
  const [adding, setAdding] = useState(false);

  useEffect(() => {
    if (isNaN(projectId)) return;
    api
      .listConstraints(projectId)
      .then(setConstraints)
      .catch(() => {})
      .finally(() => setLoading(false));
  }, [projectId]);

  const handleCreate = useCallback(async () => {
    if (!form.title.trim() || !form.body.trim() || adding) return;
    setAdding(true);
    try {
      const c = await api.createConstraint(projectId, {
        title: form.title,
        body: form.body,
        scope: form.scope,
        enforcement: form.enforcement,
      });
      setConstraints((prev) => [...prev, c]);
      setForm({ title: "", body: "", scope: "project", enforcement: "hard" });
      setShowForm(false);
    } catch {}
    setAdding(false);
  }, [projectId, form, adding]);

  const handleDelete = useCallback(
    async (id: number) => {
      try {
        await api.deleteConstraint(projectId, id);
        setConstraints((prev) => prev.filter((c) => c.id !== id));
      } catch {}
    },
    [projectId],
  );

  if (loading) return <SettingSkeleton title="Constraints" />;

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between">
        <CardTitle className="text-sm">Constraints</CardTitle>
        <Button
          variant="outline"
          size="sm"
          onClick={() => setShowForm(!showForm)}
        >
          <Plus className="mr-1.5 h-3 w-3" />
          New
        </Button>
      </CardHeader>
      <CardContent className="space-y-3">
        {showForm && (
          <div className="space-y-2 rounded-lg border p-3">
            <Input
              placeholder="Constraint title"
              value={form.title}
              onChange={(e) => setForm((f) => ({ ...f, title: e.target.value }))}
            />
            <textarea
              placeholder="Describe the constraint..."
              value={form.body}
              onChange={(e) =>
                setForm((f) => ({ ...f, body: e.target.value }))
              }
              rows={3}
              className="w-full resize-none rounded-lg border bg-background px-3 py-2 text-sm placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-ring"
            />
            <div className="flex gap-2">
              <Select
                value={form.scope}
                onValueChange={(v) => setForm((f) => ({ ...f, scope: v }))}
              >
                <SelectTrigger className="w-36">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="project">Project</SelectItem>
                  <SelectItem value="design">Design</SelectItem>
                  <SelectItem value="architecture">Architecture</SelectItem>
                  <SelectItem value="legal">Legal</SelectItem>
                </SelectContent>
              </Select>
              <Select
                value={form.enforcement}
                onValueChange={(v) =>
                  setForm((f) => ({ ...f, enforcement: v }))
                }
              >
                <SelectTrigger className="w-36">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="hard">Hard (blocking)</SelectItem>
                  <SelectItem value="soft">Soft (advisory)</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="flex justify-end gap-2">
              <Button
                variant="ghost"
                size="sm"
                onClick={() => setShowForm(false)}
              >
                Cancel
              </Button>
              <Button
                size="sm"
                onClick={handleCreate}
                disabled={!form.title.trim() || !form.body.trim() || adding}
              >
                Create
              </Button>
            </div>
          </div>
        )}

        {constraints.length === 0 && !showForm && (
          <p className="text-sm text-muted-foreground">
            No constraints defined. Add non-negotiable project boundaries.
          </p>
        )}

        {constraints.map((c) => (
          <div
            key={c.id}
            className="flex items-start justify-between rounded-lg border px-3 py-2"
          >
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2">
                <span className="text-sm font-medium">{c.title}</span>
                <Badge variant="secondary" className="text-[9px]">
                  {c.scope}
                </Badge>
                <Badge
                  className={cn(
                    "text-[9px]",
                    c.enforcement === "hard"
                      ? "bg-red-100 text-red-800"
                      : "bg-yellow-100 text-yellow-800",
                  )}
                >
                  {c.enforcement}
                </Badge>
              </div>
              <p className="mt-0.5 text-xs text-muted-foreground line-clamp-2">
                {c.body}
              </p>
            </div>
            <Button
              variant="ghost"
              size="icon"
              className="h-7 w-7 shrink-0 text-muted-foreground hover:text-destructive"
              onClick={() => handleDelete(c.id)}
            >
              <Trash2 className="h-3.5 w-3.5" />
            </Button>
          </div>
        ))}
      </CardContent>
    </Card>
  );
}

/* ───────────── Shared ───────────── */

function SettingSkeleton({ title }: { title: string }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-sm">{title}</CardTitle>
      </CardHeader>
      <CardContent>
        <Skeleton className="h-8 w-full" />
      </CardContent>
    </Card>
  );
}
