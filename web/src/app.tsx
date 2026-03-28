import { startTransition, useDeferredValue, useEffect, useEffectEvent, useMemo, useState } from "react";
import { AlertCircle, Command, Ellipsis, FileUp, MessageSquarePlus, Search, Settings2, X } from "lucide-react";

import { ChatPanel } from "@/components/chat/chat-panel";
import { ConversationDialog } from "@/components/chat/conversation-dialog";
import { InsightDialog } from "@/components/insights/insight-dialog";
import { InsightDetail } from "@/components/insights/insight-detail";
import { InsightList } from "@/components/insights/insight-list";
import { ProjectOverview } from "@/components/overview/project-overview";
import { RequirementDialog } from "@/components/requirements/requirement-dialog";
import { RequirementDetail } from "@/components/requirements/requirement-detail";
import { RequirementList } from "@/components/requirements/requirement-list";
import { CommandCenter } from "@/components/shared/command-center";
import { ExportDialog } from "@/components/shared/export-dialog";
import { ProjectDialog } from "@/components/shared/project-dialog";
import { ProjectSidebar } from "@/components/shared/project-sidebar";
import { ProcessingProgress } from "@/components/sources/processing-progress";
import { SourceDetail } from "@/components/sources/source-detail";
import { SourceList } from "@/components/sources/source-list";
import { SourceIntakeDialog } from "@/components/sources/source-intake-dialog";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Input } from "@/components/ui/input";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Separator } from "@/components/ui/separator";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { api } from "@/lib/api";
import { getSocket } from "@/lib/socket";
import { formatDate } from "@/lib/utils";
import type {
  Insight,
  ProductConversation,
  ProjectExport,
  ProductMessage,
  Project,
  ProjectCounts,
  Requirement,
  Source,
  SourceProgress,
} from "@/types";

type Section = "overview" | "sources" | "chat" | "insights" | "requirements";

export function App() {
  const [projects, setProjects] = useState<Project[]>([]);
  const [selectedProjectId, setSelectedProjectId] = useState<number | null>(null);
  const [activeSection, setActiveSection] = useState<Section>("overview");
  const [sources, setSources] = useState<Source[]>([]);
  const [insights, setInsights] = useState<Insight[]>([]);
  const [requirements, setRequirements] = useState<Requirement[]>([]);
  const [conversations, setConversations] = useState<ProductConversation[]>([]);
  const [activeConversation, setActiveConversation] = useState<ProductConversation | null>(null);
  const [selectedSourceId, setSelectedSourceId] = useState<number | null>(null);
  const [selectedInsightId, setSelectedInsightId] = useState<number | null>(null);
  const [selectedRequirementId, setSelectedRequirementId] = useState<number | null>(null);
  const [streamPreview, setStreamPreview] = useState("");
  const [progressBySource, setProgressBySource] = useState<Record<number, SourceProgress>>({});
  const [persona, setPersona] = useState<"researcher" | "strategist">("researcher");
  const [commandOpen, setCommandOpen] = useState(false);
  const [projectDialogOpen, setProjectDialogOpen] = useState(false);
  const [conversationDialogOpen, setConversationDialogOpen] = useState(false);
  const [sourceDialogOpen, setSourceDialogOpen] = useState(false);
  const [editingProject, setEditingProject] = useState<Project | null>(null);
  const [exportDialogOpen, setExportDialogOpen] = useState(false);
  const [exportResult, setExportResult] = useState<ProjectExport | null>(null);
  const [exporting, setExporting] = useState(false);
  const [insightDialogOpen, setInsightDialogOpen] = useState(false);
  const [requirementDialogOpen, setRequirementDialogOpen] = useState(false);
  const [editingInsight, setEditingInsight] = useState<Insight | null>(null);
  const [editingRequirement, setEditingRequirement] = useState<Requirement | null>(null);
  const [sourceStatusFilter, setSourceStatusFilter] = useState("all");
  const [sourceTypeFilter, setSourceTypeFilter] = useState("all");
  const [insightStatusFilter, setInsightStatusFilter] = useState("all");
  const [requirementGroundingFilter, setRequirementGroundingFilter] = useState("all");
  const [requirementStatusFilter, setRequirementStatusFilter] = useState("all");
  const [search, setSearch] = useState("");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const deferredSearch = useDeferredValue(search.trim().toLowerCase());

  useEffect(() => {
    function handleKeyDown(event: KeyboardEvent) {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
        event.preventDefault();
        setCommandOpen((current) => !current);
      }

      if (event.shiftKey && event.key.toLowerCase() === "p") {
        event.preventDefault();
        setEditingProject(null);
        setProjectDialogOpen(true);
      }

      if (event.shiftKey && event.key.toLowerCase() === "c") {
        event.preventDefault();
        setConversationDialogOpen(true);
      }
    }

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, []);

  useEffect(() => {
    let cancelled = false;

    async function loadProjects() {
      setLoading(true);

      try {
        const projectList = await api.listProjects();

        if (cancelled) {
          return;
        }

        startTransition(() => {
          setProjects(projectList);
          setSelectedProjectId((current) => current ?? projectList[0]?.id ?? null);
          setError(null);
        });
      } catch (err) {
        if (!cancelled) {
          setError(err instanceof Error ? err.message : "Failed to load projects");
        }
      } finally {
        if (!cancelled) {
          setLoading(false);
        }
      }
    }

    loadProjects();

    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    if (!selectedProjectId) {
      return;
    }

    let cancelled = false;
    const projectId = selectedProjectId;

    async function loadProjectData() {
      setLoading(true);

      try {
        const [sourceListRaw, insightList, requirementList, conversationList] = await Promise.all([
          api.listSources(projectId),
          api.listInsights(projectId),
          api.listRequirements(projectId),
          api.listConversations(projectId),
        ]);
        const sourceList = await hydrateSourceDetails(projectId, sourceListRaw);

        if (cancelled) {
          return;
        }

        startTransition(() => {
          setSources(sourceList);
          setInsights(insightList);
          setRequirements(requirementList);
          setConversations(conversationList);
          setSelectedSourceId(sourceList[0]?.id ?? null);
          setSelectedInsightId(insightList[0]?.id ?? null);
          setSelectedRequirementId(requirementList[0]?.id ?? null);
          setActiveConversation(null);
          setStreamPreview("");
          setProgressBySource({});
          setExportResult(null);
          setSourceStatusFilter("all");
          setSourceTypeFilter("all");
          setInsightStatusFilter("all");
          setRequirementGroundingFilter("all");
          setRequirementStatusFilter("all");
          setError(null);
        });
      } catch (err) {
        if (!cancelled) {
          setError(err instanceof Error ? err.message : "Failed to load project data");
        }
      } finally {
        if (!cancelled) {
          setLoading(false);
        }
      }
    }

    loadProjectData();

    return () => {
      cancelled = true;
    };
  }, [selectedProjectId]);

  const handleProjectEvent = useEffectEvent((event: string, payload: Record<string, unknown>) => {
    if (event.startsWith("source.")) {
      const source = payload.source as Source | undefined;
      if (source) {
        setSources((current) => upsertById(current, source));
      }

      if (source?.id && payload.status) {
        setProgressBySource((current) => ({
          ...current,
          [source.id]: {
            status: String(payload.status),
            stage: payload.stage ? String(payload.stage) : undefined,
            chunk_count:
              typeof payload.chunk_count === "number" ? payload.chunk_count : undefined,
            error: payload.error ? String(payload.error) : undefined,
          },
        }));
      }
    }

    if (event.startsWith("insight.")) {
      const insight = payload.insight as Insight | undefined;
      if (insight) {
        setInsights((current) => upsertById(current, insight));
      }
    }

    if (event.startsWith("requirement.")) {
      const requirement = payload.requirement as Requirement | undefined;
      if (requirement) {
        setRequirements((current) => upsertById(current, requirement));
      }
    }

    if (event.startsWith("conversation.")) {
      const conversation = payload.conversation as ProductConversation | undefined;
      if (conversation) {
        setConversations((current) => upsertById(current, conversation));
      }
    }

    if (event === "message.created") {
      const conversation = payload.conversation as ProductConversation | undefined;
      const message = payload.message as ProductMessage | undefined;

      if (conversation) {
        setConversations((current) => upsertById(current, conversation));
      }

      if (message && conversation && activeConversation?.id === conversation.id) {
        setActiveConversation((current) =>
          current
            ? {
                ...current,
                ...conversation,
                messages: [...(current.messages ?? []), message],
              }
            : current,
        );
      }
    }
  });

  useEffect(() => {
    if (!selectedProjectId) {
      return;
    }

    const channel = getSocket().channel(`project:${selectedProjectId}`);

    channel.join();

    const events = [
      "source.created",
      "source.updated",
      "source.progress",
      "source.completed",
      "source.failed",
      "insight.created",
      "insight.updated",
      "requirement.created",
      "requirement.updated",
      "conversation.created",
      "conversation.updated",
      "message.created",
    ];

    events.forEach((event) => {
      channel.on(event, (payload: Record<string, unknown>) => handleProjectEvent(event, payload));
    });

    return () => {
      channel.leave();
    };
  }, [handleProjectEvent, selectedProjectId]);

  useEffect(() => {
    if (!selectedProjectId || !selectedSourceId) {
      return;
    }

    const channel = getSocket().channel(`source:${selectedSourceId}`);

    channel.join().receive("ok", (reply: { source: Source }) => {
      setSources((current) => upsertById(current, reply.source));
    });

    ["progress", "completed", "failed"].forEach((event) => {
      channel.on(
        event,
        (payload: {
          source: Source;
          status: string;
          stage?: string;
          chunk_count?: number;
          error?: string;
        }) => {
          setSources((current) => upsertById(current, payload.source));
          setProgressBySource((current) => ({
            ...current,
            [payload.source.id]: {
              status: payload.status,
              stage: payload.stage,
              chunk_count: payload.chunk_count,
              error: payload.error,
            },
          }));
        },
      );
    });

    return () => {
      channel.leave();
    };
  }, [selectedProjectId, selectedSourceId]);

  useEffect(() => {
    if (!selectedProjectId) {
      return;
    }

    const selected = conversations.find((conversation) => conversation.id === activeConversation?.id);

    if (!selected && conversations[0]) {
      void selectConversation(conversations[0].id);
    }
  }, [activeConversation?.id, conversations, selectedProjectId]);

  const handleConversationEvent = useEffectEvent(
    (event: string, payload: { conversation?: ProductConversation; delta?: string }) => {
      if (event === "stream_chunk" && payload.delta) {
        setStreamPreview((current) => current + payload.delta);
        return;
      }

      if ((event === "stream_done" || event === "conversation_updated") && payload.conversation) {
        setStreamPreview("");
        setActiveConversation(payload.conversation);
        setConversations((current) => upsertById(current, payload.conversation!));
      }
    },
  );

  useEffect(() => {
    if (!activeConversation) {
      return;
    }

    const channel = getSocket().channel(`product_conversation:${activeConversation.id}`);

    channel.join().receive("ok", (reply: { conversation: ProductConversation }) => {
      setActiveConversation(reply.conversation);
      setConversations((current) => upsertById(current, reply.conversation));
    });

    channel.on("stream_chunk", (payload: { delta?: string; conversation?: ProductConversation }) =>
      handleConversationEvent("stream_chunk", payload),
    );
    channel.on("stream_done", (payload: { conversation?: ProductConversation }) =>
      handleConversationEvent("stream_done", payload),
    );
    channel.on(
      "conversation_updated",
      (payload: { conversation?: ProductConversation; delta?: string }) =>
        handleConversationEvent("conversation_updated", payload),
    );

    return () => {
      channel.leave();
    };
  }, [activeConversation?.id, handleConversationEvent]);

  const filteredSources = useMemo(
    () =>
      filterBySearch(
        sources.filter((source) => {
          const statusMatch =
            sourceStatusFilter === "all" || source.processing_status === sourceStatusFilter;
          const typeMatch = sourceTypeFilter === "all" || source.source_type === sourceTypeFilter;

          return statusMatch && typeMatch;
        }),
        deferredSearch,
        (source) => `${source.title} ${source.content}`,
      ),
    [deferredSearch, sourceStatusFilter, sourceTypeFilter, sources],
  );
  const filteredInsights = useMemo(
    () =>
      filterBySearch(
        insights.filter((insight) => {
          return insightStatusFilter === "all" || insight.status === insightStatusFilter;
        }),
        deferredSearch,
        (insight) => `${insight.title} ${insight.body}`,
      ),
    [deferredSearch, insightStatusFilter, insights],
  );
  const filteredRequirements = useMemo(
    () =>
      filterBySearch(
        requirements.filter((requirement) => {
          const groundingMatch =
            requirementGroundingFilter === "all" ||
            (requirementGroundingFilter === "grounded" ? requirement.grounded : !requirement.grounded);
          const statusMatch =
            requirementStatusFilter === "all" || requirement.status === requirementStatusFilter;

          return groundingMatch && statusMatch;
        }),
        deferredSearch,
        (requirement) => `${requirement.title} ${requirement.body}`,
      ),
    [deferredSearch, requirementGroundingFilter, requirementStatusFilter, requirements],
  );
  const filteredConversations = useMemo(
    () =>
      filterBySearch(
        conversations,
        deferredSearch,
        (conversation) =>
          `${conversation.title ?? ""} ${conversation.latest_message?.content ?? ""}`,
      ),
    [conversations, deferredSearch],
  );

  const selectedSource = filteredSources.find((source) => source.id === selectedSourceId) ?? null;
  const selectedInsight =
    filteredInsights.find((insight) => insight.id === selectedInsightId) ?? null;
  const selectedRequirement =
    filteredRequirements.find((requirement) => requirement.id === selectedRequirementId) ?? null;
  const selectedInsightForDetail =
    insights.find((insight) => insight.id === selectedInsightId) ?? selectedInsight ?? null;
  const selectedRequirementForDetail =
    requirements.find((requirement) => requirement.id === selectedRequirementId) ??
    selectedRequirement ??
    null;
  const sourceTypes = useMemo(
    () => Array.from(new Set(sources.map((source) => source.source_type))).sort(),
    [sources],
  );
  const selectedSourceForDetail =
    sources.find((source) => source.id === selectedSourceId) ?? selectedSource ?? null;
  const relatedInsightsForSource = useMemo(() => {
    if (!selectedSourceForDetail) {
      return [];
    }

    return insights.filter((insight) =>
      insight.evidence.some((evidence) => evidence.source_chunk?.source_id === selectedSourceForDetail.id),
    );
  }, [insights, selectedSourceForDetail]);
  const relatedRequirementsForSource = useMemo(() => {
    if (!selectedSourceForDetail) {
      return [];
    }

    const relatedInsightIds = new Set(relatedInsightsForSource.map((insight) => insight.id));
    return requirements.filter((requirement) =>
      requirement.insights.some((insight) => relatedInsightIds.has(insight.id)),
    );
  }, [relatedInsightsForSource, requirements, selectedSourceForDetail]);
  const activeProject = projects.find((project) => project.id === selectedProjectId) ?? null;
  const counts: ProjectCounts = useMemo(
    () => ({
      sources: sources.length,
      insights: insights.length,
      requirements: requirements.length,
      conversations: conversations.length,
      decisions: 0,
      strategies: 0,
      design_nodes: 0,
      architecture_nodes: 0,
      tasks: 0,
      learnings: 0,
      flags: 0,
    }),
    [conversations.length, insights.length, requirements.length, sources.length],
  );

  async function saveProject(payload: {
    name: string;
    slug?: string;
    description?: string;
    status: string;
  }) {
    const next = editingProject
      ? await api.updateProject(editingProject.id, payload)
      : await api.createProject(payload);

    setProjects((current) => upsertById(current, next));
    setSelectedProjectId(next.id);
    setEditingProject(null);
    setActiveSection("overview");
  }

  function focusSource(sourceId: number) {
    setSelectedSourceId(sourceId);
    setActiveSection("sources");
  }

  function focusInsight(insightId: number) {
    setSelectedInsightId(insightId);
    setActiveSection("insights");
  }

  function focusRequirement(requirementId: number) {
    setSelectedRequirementId(requirementId);
    setActiveSection("requirements");
  }

  async function selectConversation(conversationId: number) {
    if (!selectedProjectId) {
      return;
    }

    const conversation = await api.getConversation(selectedProjectId, conversationId);
    setActiveConversation(conversation);
    setConversations((current) => upsertById(current, conversation));
  }

  async function createConversation(payload: {
    persona: ProductConversation["persona"];
    title: string;
    externalRef?: string;
  }) {
    if (!selectedProjectId) {
      return;
    }

    const conversation = await api.createConversation(selectedProjectId, {
      persona: payload.persona,
      title: payload.title,
      externalRef: payload.externalRef,
    });

    setConversations((current) => upsertById(current, conversation));
    await selectConversation(conversation.id);
    setPersona((payload.persona === "strategist" ? "strategist" : "researcher"));
    setActiveSection("chat");
  }

  async function sendConversationMessage(content: string) {
    if (!activeConversation || !selectedProjectId) {
      return;
    }

    setStreamPreview("");
    const reply = await api.sendConversationMessage(selectedProjectId, activeConversation.id, content);

    setActiveConversation(reply.conversation);
    setConversations((current) => upsertById(current, reply.conversation));
  }

  async function createSource(payload: {
    title: string;
    sourceType: string;
    content?: string;
    file?: File | null;
  }) {
    if (!selectedProjectId) {
      return;
    }

    const source = await api.createSource(selectedProjectId, payload);
    setSources((current) => upsertById(current, source));
    setSelectedSourceId(source.id);
  }

  async function saveInsight(payload: {
    title: string;
    body: string;
    status: string;
    evidenceChunkIds: number[];
  }) {
    if (!selectedProjectId) {
      return;
    }

    const next = editingInsight
      ? await api.updateInsight(selectedProjectId, editingInsight.id, payload)
      : await api.createInsight(selectedProjectId, payload);

    setInsights((current) => upsertById(current, next));
    setSelectedInsightId(next.id);
    setEditingInsight(null);
  }

  async function saveRequirement(payload: {
    title: string;
    body: string;
    status: string;
    insightIds: number[];
  }) {
    if (!selectedProjectId) {
      return;
    }

    const next = editingRequirement
      ? await api.updateRequirement(selectedProjectId, editingRequirement.id, payload)
      : await api.createRequirement(selectedProjectId, payload);

    setRequirements((current) => upsertById(current, next));
    setSelectedRequirementId(next.id);
    setEditingRequirement(null);
  }

  async function exportProject() {
    if (!selectedProjectId) {
      return;
    }

    setExporting(true);

    try {
      const result = await api.exportProject(selectedProjectId);
      setExportResult(result);
      setExportDialogOpen(true);
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to export project");
    } finally {
      setExporting(false);
    }
  }

  const hasSourceFilters = sourceStatusFilter !== "all" || sourceTypeFilter !== "all";
  const hasInsightFilters = insightStatusFilter !== "all";
  const hasRequirementFilters =
    requirementGroundingFilter !== "all" || requirementStatusFilter !== "all";

  return (
    <main className="app-shell min-h-screen p-4 md:p-6 xl:p-8">
      <div className="grid min-h-[calc(100vh-2rem)] gap-6 xl:grid-cols-[320px_minmax(0,1fr)]">
        <ProjectSidebar
          projects={projects}
          selectedProjectId={selectedProjectId}
          onSelectProject={setSelectedProjectId}
          activeSection={activeSection}
          onSelectSection={setActiveSection}
          counts={counts}
          onCreateProject={() => {
            setEditingProject(null);
            setProjectDialogOpen(true);
          }}
          onOpenCommand={() => setCommandOpen(true)}
        />

        <section className="flex flex-col gap-6">
          <Card className="overflow-hidden">
            <CardContent className="px-6 py-5">
            <div className="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
              <div>
                <p className="text-[10px] font-bold uppercase tracking-[0.3em] text-[var(--ink-soft)]">
                  Product layer workspace
                </p>
                <h1 className="mt-2 font-display text-5xl text-[var(--ink)]">
                  {activeProject?.name ?? "Hydra Product"}
                </h1>
                <p className="mt-3 max-w-2xl text-sm leading-7 text-[var(--ink-soft)]">
                  A research notebook front-end for grounded chat, evidence-backed insights, and traceable requirements.
                </p>
              </div>

              <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
                <label className="relative block min-w-[18rem]">
                  <Search className="pointer-events-none absolute left-4 top-1/2 h-4 w-4 -translate-y-1/2 text-[var(--ink-soft)]" />
                  <Input
                    className="pl-10"
                    value={search}
                    onChange={(event) => setSearch(event.target.value)}
                    placeholder="Filter the active panel"
                  />
                </label>
                <div className="flex items-center gap-2">
                  <Button variant="outline" size="sm" onClick={() => setCommandOpen(true)}>
                    <Command className="h-4 w-4" />
                    Command
                  </Button>
                  <DropdownMenu>
                    <DropdownMenuTrigger asChild>
                      <Button variant="secondary" size="sm">
                        <Ellipsis className="h-4 w-4" />
                        Actions
                      </Button>
                    </DropdownMenuTrigger>
                    <DropdownMenuContent align="end">
                      <DropdownMenuItem
                        onClick={() => {
                          setEditingProject(null);
                          setProjectDialogOpen(true);
                        }}
                      >
                        <Settings2 className="h-4 w-4" />
                        New project
                      </DropdownMenuItem>
                      <DropdownMenuItem
                        disabled={!activeProject}
                        onClick={() => {
                          if (!activeProject) {
                            return;
                          }

                          setEditingProject(activeProject);
                          setProjectDialogOpen(true);
                        }}
                      >
                        <Settings2 className="h-4 w-4" />
                        Edit project
                      </DropdownMenuItem>
                      <DropdownMenuSeparator />
                      <DropdownMenuItem onClick={() => setConversationDialogOpen(true)}>
                        <MessageSquarePlus className="h-4 w-4" />
                        New conversation
                      </DropdownMenuItem>
                      <DropdownMenuItem onClick={() => setSourceDialogOpen(true)}>
                        <FileUp className="h-4 w-4" />
                        Ingest source
                      </DropdownMenuItem>
                      <DropdownMenuSeparator />
                      <DropdownMenuItem onClick={() => setExportDialogOpen(true)}>
                        <Settings2 className="h-4 w-4" />
                        Export snapshot
                      </DropdownMenuItem>
                    </DropdownMenuContent>
                  </DropdownMenu>
                  <Badge variant="accent">{counts.sources} sources</Badge>
                  <Badge variant="neutral">{counts.conversations} chats</Badge>
                </div>
              </div>
            </div>
            </CardContent>
          </Card>

          {loading ? (
            <Card className="p-8">
              <div className="grid gap-6 xl:grid-cols-[360px_minmax(0,1fr)]">
                <div className="space-y-4">
                  <Skeleton className="h-12 w-40" />
                  <Skeleton className="h-[18rem] w-full" />
                </div>
                <div className="space-y-4">
                  <Skeleton className="h-12 w-56" />
                  <Skeleton className="h-[28rem] w-full" />
                </div>
              </div>
            </Card>
          ) : error ? (
            <Card className="p-8">
              <p className="inline-flex items-center gap-3 font-semibold text-rose-900">
                <AlertCircle className="h-5 w-5" />
                {error}
              </p>
            </Card>
          ) : (
            <Tabs
              value={activeSection}
              onValueChange={(value) => setActiveSection(value as Section)}
              className="space-y-0"
            >
              <TabsList>
                <TabsTrigger value="overview">Overview</TabsTrigger>
                <TabsTrigger value="sources">Sources</TabsTrigger>
                <TabsTrigger value="chat">Chat</TabsTrigger>
                <TabsTrigger value="insights">Insights</TabsTrigger>
                <TabsTrigger value="requirements">Requirements</TabsTrigger>
              </TabsList>

              <TabsContent value="overview">
                <ProjectOverview
                  project={activeProject}
                  sources={sources}
                  insights={insights}
                  requirements={requirements}
                  conversations={conversations}
                  onSelectSection={setActiveSection}
                  onOpenExport={() => {
                    setExportDialogOpen(true);
                  }}
                />
              </TabsContent>

              <TabsContent value="sources">
                <div className="grid gap-6 2xl:grid-cols-[minmax(0,1.1fr)_minmax(24rem,0.9fr)]">
                  <div className="space-y-6">
                    <Card className="overflow-hidden">
                      <CardHeader className="border-b border-[var(--line)] bg-[linear-gradient(135deg,rgba(245,207,124,0.2),rgba(158,98,61,0.04))]">
                        <p className="text-[10px] font-bold uppercase tracking-[0.3em] text-[var(--ink-soft)]">
                          Ingestion desk
                        </p>
                        <CardTitle>Bring evidence into the corpus</CardTitle>
                        <CardDescription>
                          Use the source intake flow to paste raw notes or upload files into the retrieval graph.
                        </CardDescription>
                      </CardHeader>
                      <CardContent className="flex flex-col gap-4 pt-6 sm:flex-row sm:items-center sm:justify-between">
                        <div>
                          <p className="text-sm font-medium text-[var(--ink)]">
                            {counts.sources} tracked sources across the active product workspace.
                          </p>
                          <p className="mt-2 text-sm text-[var(--ink-soft)]">
                            New material is chunked, embedded, and made available to chat, insights, and requirements.
                          </p>
                        </div>
                        <Button onClick={() => setSourceDialogOpen(true)}>
                          <FileUp className="h-4 w-4" />
                          Ingest source
                        </Button>
                      </CardContent>
                    </Card>
                    <SourceList
                      sources={filteredSources}
                      selectedSourceId={selectedSourceId}
                      onSelectSource={setSelectedSourceId}
                    />
                  </div>
                  <div className="space-y-6">
                    <Card>
                      <CardContent className="flex flex-col gap-4 p-4 lg:flex-row lg:items-center lg:justify-between">
                        <div className="grid gap-3 sm:grid-cols-2">
                          <Select value={sourceStatusFilter} onValueChange={setSourceStatusFilter}>
                            <SelectTrigger className="w-full sm:w-[12rem]">
                              <SelectValue placeholder="Filter by status" />
                            </SelectTrigger>
                            <SelectContent>
                              <SelectItem value="all">All statuses</SelectItem>
                              <SelectItem value="pending">Pending</SelectItem>
                              <SelectItem value="processing">Processing</SelectItem>
                              <SelectItem value="completed">Completed</SelectItem>
                              <SelectItem value="failed">Failed</SelectItem>
                            </SelectContent>
                          </Select>
                          <Select value={sourceTypeFilter} onValueChange={setSourceTypeFilter}>
                            <SelectTrigger className="w-full sm:w-[12rem]">
                              <SelectValue placeholder="Filter by type" />
                            </SelectTrigger>
                            <SelectContent>
                              <SelectItem value="all">All types</SelectItem>
                              {sourceTypes.map((type) => (
                                <SelectItem key={type} value={type}>
                                  {type}
                                </SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                        </div>
                        {hasSourceFilters ? (
                          <Button
                            variant="outline"
                            size="sm"
                            onClick={() => {
                              setSourceStatusFilter("all");
                              setSourceTypeFilter("all");
                            }}
                          >
                            <X className="h-4 w-4" />
                            Clear filters
                          </Button>
                        ) : null}
                      </CardContent>
                    </Card>
                    <ProcessingProgress progress={selectedSourceId ? progressBySource[selectedSourceId] : null} />
                    <SourceDetail
                      source={selectedSourceForDetail}
                      relatedInsights={relatedInsightsForSource}
                      relatedRequirements={relatedRequirementsForSource}
                      onSelectInsight={focusInsight}
                      onSelectRequirement={focusRequirement}
                    />
                  </div>
                </div>
              </TabsContent>

              <TabsContent value="chat">
                <ChatPanel
                  conversations={filteredConversations}
                  selectedConversationId={activeConversation?.id ?? null}
                  onSelectConversation={(conversationId) => void selectConversation(conversationId)}
                  onOpenConversationDialog={() => setConversationDialogOpen(true)}
                  activeConversation={activeConversation}
                  onSendMessage={sendConversationMessage}
                  streamPreview={streamPreview}
                  persona={persona}
                  onChangePersona={setPersona}
                />
              </TabsContent>

              <TabsContent value="insights">
                <div className="mb-4 flex flex-col gap-4 xl:flex-row xl:items-center xl:justify-between">
                  <div className="flex flex-wrap items-center gap-3">
                    <Select value={insightStatusFilter} onValueChange={setInsightStatusFilter}>
                      <SelectTrigger className="w-[12rem]">
                        <SelectValue placeholder="Filter by insight status" />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="all">All statuses</SelectItem>
                        <SelectItem value="draft">Draft</SelectItem>
                        <SelectItem value="accepted">Accepted</SelectItem>
                        <SelectItem value="rejected">Rejected</SelectItem>
                      </SelectContent>
                    </Select>
                    {hasInsightFilters ? (
                      <Button variant="outline" size="sm" onClick={() => setInsightStatusFilter("all")}>
                        <X className="h-4 w-4" />
                        Clear filters
                      </Button>
                    ) : null}
                  </div>
                  <Button
                    onClick={() => {
                      setEditingInsight(null);
                      setInsightDialogOpen(true);
                    }}
                  >
                    New insight
                  </Button>
                </div>
                <div className="grid gap-6 xl:grid-cols-[360px_minmax(0,1fr)]">
                  <InsightList
                    insights={filteredInsights}
                    selectedInsightId={selectedInsightId}
                    onSelectInsight={setSelectedInsightId}
                  />
                  <InsightDetail
                    insight={selectedInsightForDetail}
                    onEdit={
                      selectedInsightForDetail
                        ? () => {
                            setEditingInsight(selectedInsightForDetail);
                            setInsightDialogOpen(true);
                          }
                        : undefined
                    }
                    onSelectSource={focusSource}
                    onSelectRequirement={focusRequirement}
                  />
                </div>
              </TabsContent>

              <TabsContent value="requirements">
                <div className="mb-4 flex flex-col gap-4 xl:flex-row xl:items-center xl:justify-between">
                  <div className="flex flex-wrap items-center gap-3">
                    <Select value={requirementGroundingFilter} onValueChange={setRequirementGroundingFilter}>
                      <SelectTrigger className="w-[12rem]">
                        <SelectValue placeholder="Filter by grounding" />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="all">All grounding</SelectItem>
                        <SelectItem value="grounded">Grounded</SelectItem>
                        <SelectItem value="review">Needs review</SelectItem>
                      </SelectContent>
                    </Select>
                    <Select value={requirementStatusFilter} onValueChange={setRequirementStatusFilter}>
                      <SelectTrigger className="w-[12rem]">
                        <SelectValue placeholder="Filter by status" />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="all">All statuses</SelectItem>
                        <SelectItem value="draft">Draft</SelectItem>
                        <SelectItem value="accepted">Accepted</SelectItem>
                        <SelectItem value="rejected">Rejected</SelectItem>
                      </SelectContent>
                    </Select>
                    {hasRequirementFilters ? (
                      <Button
                        variant="outline"
                        size="sm"
                        onClick={() => {
                          setRequirementGroundingFilter("all");
                          setRequirementStatusFilter("all");
                        }}
                      >
                        <X className="h-4 w-4" />
                        Clear filters
                      </Button>
                    ) : null}
                  </div>
                  <Button
                    onClick={() => {
                      setEditingRequirement(null);
                      setRequirementDialogOpen(true);
                    }}
                  >
                    New requirement
                  </Button>
                </div>
                <div className="grid gap-6 xl:grid-cols-[360px_minmax(0,1fr)]">
                  <RequirementList
                    requirements={filteredRequirements}
                    selectedRequirementId={selectedRequirementId}
                    onSelectRequirement={setSelectedRequirementId}
                  />
                  <RequirementDetail
                    requirement={selectedRequirementForDetail}
                    onEdit={
                      selectedRequirementForDetail
                        ? () => {
                            setEditingRequirement(selectedRequirementForDetail);
                            setRequirementDialogOpen(true);
                          }
                        : undefined
                    }
                    onSelectInsight={focusInsight}
                    onSelectSource={focusSource}
                  />
                </div>
              </TabsContent>
            </Tabs>
          )}
        </section>
      </div>

      <CommandCenter
        open={commandOpen}
        projects={projects}
        conversations={conversations}
        onOpenChange={setCommandOpen}
        onSelectProject={setSelectedProjectId}
        onSelectSection={setActiveSection}
        onSelectConversation={(conversationId) => void selectConversation(conversationId)}
        onCreateProject={() => {
          setEditingProject(null);
          setProjectDialogOpen(true);
        }}
        onCreateConversation={() => setConversationDialogOpen(true)}
      />

      <ProjectDialog
        open={projectDialogOpen}
        mode={editingProject ? "edit" : "create"}
        project={editingProject}
        onClose={() => {
          setProjectDialogOpen(false);
          setEditingProject(null);
        }}
        onSubmit={saveProject}
      />

      <ConversationDialog
        open={conversationDialogOpen}
        projectName={activeProject?.name}
        conversationCount={conversations.length}
        onClose={() => setConversationDialogOpen(false)}
        onSubmit={createConversation}
      />

      <SourceIntakeDialog
        open={sourceDialogOpen}
        onClose={() => setSourceDialogOpen(false)}
        onSubmit={createSource}
      />

      <InsightDialog
        open={insightDialogOpen}
        mode={editingInsight ? "edit" : "create"}
        insight={editingInsight}
        sources={sources}
        onClose={() => {
          setInsightDialogOpen(false);
          setEditingInsight(null);
        }}
        onSubmit={saveInsight}
      />

      <RequirementDialog
        open={requirementDialogOpen}
        mode={editingRequirement ? "edit" : "create"}
        requirement={editingRequirement}
        insights={insights}
        onClose={() => {
          setRequirementDialogOpen(false);
          setEditingRequirement(null);
        }}
        onSubmit={saveRequirement}
      />

      <ExportDialog
        open={exportDialogOpen}
        project={activeProject}
        exportResult={exportResult}
        exporting={exporting}
        onClose={() => setExportDialogOpen(false)}
        onExport={exportProject}
      />
    </main>
  );
}

function filterBySearch<T>(items: T[], search: string, getText: (item: T) => string) {
  if (!search) {
    return items;
  }

  return items.filter((item) => getText(item).toLowerCase().includes(search));
}

function upsertById<T extends { id: number }>(items: T[], next: T) {
  const existingIndex = items.findIndex((item) => item.id === next.id);

  if (existingIndex === -1) {
    return [next, ...items];
  }

  const copy = items.slice();
  copy[existingIndex] = mergePreservingLoadedFields(copy[existingIndex], next);
  return copy;
}

async function hydrateSourceDetails(projectId: number, sources: Source[]) {
  return Promise.all(sources.map((source) => api.getSource(projectId, source.id)));
}

function mergePreservingLoadedFields<T extends Record<string, unknown>>(current: T, next: T): T {
  const merged: Record<string, unknown> = { ...current };

  Object.entries(next).forEach(([key, value]) => {
    if (value === null || value === undefined) {
      return;
    }

    merged[key] = value;
  });

  return merged as T;
}
