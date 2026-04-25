import type {
  AgentTask,
  ArchitectureNode,
  Flow,
  OnboardingStatus,
  StreamEntry,
  StreamTab,
  StreamTabCounts,
  StreamTabItem,
  WhyPayload,
  BoardEdge,
  BoardNode,
  BoardSession,
  BoardSessionEvent,
  Constraint,
  Decision,
  DesignNode,
  GraphData,
  GraphDataEdge,
  GraphFlag,
  Insight,
  KnowledgeEntry,
  Learning,
  Mention,
  ProductConversation,
  ProductTask,
  ProjectCounts,
  ProjectExport,
  Project,
  Requirement,
  Routine,
  RoutineRun,
  SimArchetype,
  SimEstimate,
  SimGraphNode,
  Simulation,
  Source,
  SourceReference,
  SourceReferenceSummary,
  Strategy,
  WatchTarget,
  AgentRule,
  Contradiction,
  SchemaProposal,
  SchemaProposalRequest,
} from "@/types";

const API_PREFIX = import.meta.env.VITE_API_BASE ?? "/api/v1";

type Envelope<T> = {
  data: T;
};

export class ApiError extends Error {
  status: number;
  body: Record<string, unknown> | null;

  constructor(status: number, message: string, body: Record<string, unknown> | null = null) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.body = body;
  }

  /** If the server returned an envelope `{error, data}`, pull `data` out. */
  data<T>(): T | null {
    if (!this.body) return null;
    const data = this.body["data"];
    return (data as T) ?? null;
  }
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${API_PREFIX}${path}`, {
    credentials: "include",
    headers: {
      Accept: "application/json",
      ...(init?.body instanceof FormData ? {} : { "Content-Type": "application/json" }),
      ...(init?.headers ?? {}),
    },
    ...init,
  });

  if (!response.ok) {
    let body: Record<string, unknown> | null = null;
    try {
      body = (await response.json()) as Record<string, unknown>;
    } catch {
      body = null;
    }
    const message =
      (body && typeof body["error"] === "string" ? (body["error"] as string) : null) ||
      (body && typeof body["message"] === "string" ? (body["message"] as string) : null) ||
      `Request failed (${response.status})`;
    throw new ApiError(response.status, message, body);
  }

  if (response.status === 204) {
    return undefined as T;
  }

  const payload = (await response.json()) as Envelope<T>;
  return payload.data;
}

export const api = {
  listProjects: () => request<Project[]>("/projects"),
  createProject: (payload: {
    name: string;
    slug?: string;
    description?: string;
    status?: string;
  }) =>
    request<Project>("/projects", {
      method: "POST",
      body: JSON.stringify({
        project: {
          name: payload.name,
          slug: payload.slug,
          description: payload.description,
          status: payload.status,
        },
      }),
    }),
  updateProject: (
    projectId: number,
    payload: {
      name: string;
      slug?: string;
      description?: string;
      status?: string;
    },
  ) =>
    request<Project>(`/projects/${projectId}`, {
      method: "PATCH",
      body: JSON.stringify({
        project: {
          name: payload.name,
          slug: payload.slug,
          description: payload.description,
          status: payload.status,
        },
      }),
    }),
  listSources: (projectId: number) => request<Source[]>(`/projects/${projectId}/sources`),
  getSource: (projectId: number, sourceId: number) =>
    request<Source>(`/projects/${projectId}/sources/${sourceId}`),
  createSource: async (
    projectId: number,
    payload: { title: string; sourceType: string; content?: string; file?: File | null },
  ) => {
    if (payload.file) {
      const form = new FormData();
      form.append("source[title]", payload.title);
      form.append("source[source_type]", payload.sourceType);
      form.append("source[upload]", payload.file);

      return request<Source>(`/projects/${projectId}/sources`, {
        method: "POST",
        body: form,
      });
    }

    return request<Source>(`/projects/${projectId}/sources`, {
      method: "POST",
      body: JSON.stringify({
        source: {
          title: payload.title,
          source_type: payload.sourceType,
          content: payload.content,
        },
      }),
    });
  },
  analyzeSource: (projectId: number, sourceId: number, boardSessionId?: number) =>
    request<{ conversation_id: number; source_id: number }>(
      `/projects/${projectId}/sources/${sourceId}/analyze`,
      {
        method: "POST",
        body: JSON.stringify({ board_session_id: boardSessionId ?? null }),
      },
    ),
  processAllPendingSources: (projectId: number) =>
    request<{ triggered: number; total_pending: number }>(
      `/projects/${projectId}/sources/process_pending`,
      { method: "POST" },
    ),

  // ---- Library API (Source-as-Data, Cycle 3) ----
  searchLibrary: (projectId: number, query: string, opts?: { limit?: number; includeArchived?: boolean }) => {
    const params = new URLSearchParams({ q: query });
    if (opts?.limit != null) params.set("limit", String(opts.limit));
    if (opts?.includeArchived) params.set("include_archived", "true");
    return request<Source[]>(`/projects/${projectId}/library/search?${params.toString()}`);
  },
  listLibraryRecent: (projectId: number, limit = 25) =>
    request<Source[]>(`/projects/${projectId}/library/recent?limit=${limit}`),
  listLibraryUnprocessed: (projectId: number) =>
    request<Source[]>(`/projects/${projectId}/library/unprocessed`),
  listLibraryByBucket: (
    projectId: number,
    bucket: "all" | "referenced" | "unreferenced" | "promoted" | "unprocessed" | "archived",
  ) => request<Source[]>(`/projects/${projectId}/library/bucket/${bucket}`),
  listLibraryCandidates: (projectId: number, threshold = 5) =>
    request<Source[]>(`/projects/${projectId}/library/candidates?threshold=${threshold}`),
  getLibrarySource: (projectId: number, sourceId: number) =>
    request<Source>(`/projects/${projectId}/library/sources/${sourceId}`),
  getLibrarySourceContent: (projectId: number, sourceId: number, maxChars?: number) => {
    const q = maxChars != null ? `?max_chars=${maxChars}` : "";
    return request<{ content: string }>(`/projects/${projectId}/library/sources/${sourceId}/content${q}`);
  },
  getLibraryReferencedBy: (projectId: number, sourceId: number) =>
    request<SourceReferenceSummary[]>(
      `/projects/${projectId}/library/sources/${sourceId}/referenced_by`,
    ),
  promoteSource: (projectId: number, sourceId: number) =>
    request<Source>(`/projects/${projectId}/library/sources/${sourceId}/promote`, {
      method: "POST",
      body: "{}",
    }),
  demoteSource: (projectId: number, sourceId: number) =>
    request<Source>(`/projects/${projectId}/library/sources/${sourceId}/demote`, {
      method: "POST",
      body: "{}",
    }),
  archiveSource: (projectId: number, sourceId: number) =>
    request<Source>(`/projects/${projectId}/library/sources/${sourceId}/archive`, {
      method: "POST",
      body: "{}",
    }),
  unarchiveSource: (projectId: number, sourceId: number) =>
    request<Source>(`/projects/${projectId}/library/sources/${sourceId}/unarchive`, {
      method: "POST",
      body: "{}",
    }),
  getNodeSourceReferences: (projectId: number, nodeType: string, nodeId: number) =>
    request<SourceReference[]>(`/projects/${projectId}/nodes/${nodeType}/${nodeId}/sources`),
  createSourceReference: (
    projectId: number,
    payload: {
      source_id: number;
      node_type: string;
      node_id: number;
      relationship?: "extracted_from" | "supports" | "cites" | "contradicts";
      excerpt?: string;
      confidence?: "high" | "medium" | "low";
      page_or_position?: string;
    },
  ) =>
    request<{ id: number }>(`/projects/${projectId}/source_references`, {
      method: "POST",
      body: JSON.stringify(payload),
    }),
  deleteSourceReference: (projectId: number, referenceId: number) =>
    request<void>(`/projects/${projectId}/source_references/${referenceId}`, { method: "DELETE" }),
  bulkCreateSources: async (projectId: number, files: File[]) => {
    const form = new FormData();
    files.forEach((f) => form.append("source[files][]", f));
    return request<{ sources: Source[]; errors: string[] }>(
      `/projects/${projectId}/sources/bulk`,
      { method: "POST", body: form },
    );
  },
  listInsights: (projectId: number) => request<Insight[]>(`/projects/${projectId}/insights`),
  createInsight: (
    projectId: number,
    payload: {
      title: string;
      body: string;
      status: string;
      evidenceChunkIds: number[];
    },
  ) =>
    request<Insight>(`/projects/${projectId}/insights`, {
      method: "POST",
      body: JSON.stringify({
        insight: {
          title: payload.title,
          body: payload.body,
          status: payload.status,
          evidence_chunk_ids: payload.evidenceChunkIds,
        },
      }),
    }),
  updateInsight: (
    projectId: number,
    insightId: number,
    payload: Partial<{
      title: string;
      body: string;
      status: string;
      evidenceChunkIds: number[];
    }>,
  ) => {
    const insight: Record<string, unknown> = {};
    if (payload.title !== undefined) insight.title = payload.title;
    if (payload.body !== undefined) insight.body = payload.body;
    if (payload.status !== undefined) insight.status = payload.status;
    if (payload.evidenceChunkIds !== undefined) insight.evidence_chunk_ids = payload.evidenceChunkIds;
    return request<Insight>(`/projects/${projectId}/insights/${insightId}`, {
      method: "PATCH",
      body: JSON.stringify({ insight }),
    });
  },
  listRequirements: (projectId: number) =>
    request<Requirement[]>(`/projects/${projectId}/requirements`),
  createRequirement: (
    projectId: number,
    payload: {
      title: string;
      body: string;
      status: string;
      insightIds: number[];
    },
  ) =>
    request<Requirement>(`/projects/${projectId}/requirements`, {
      method: "POST",
      body: JSON.stringify({
        requirement: {
          title: payload.title,
          body: payload.body,
          status: payload.status,
          insight_ids: payload.insightIds,
        },
      }),
    }),
  updateRequirement: (
    projectId: number,
    requirementId: number,
    payload: Partial<{
      title: string;
      body: string;
      status: string;
      insightIds: number[];
    }>,
  ) => {
    const requirement: Record<string, unknown> = {};
    if (payload.title !== undefined) requirement.title = payload.title;
    if (payload.body !== undefined) requirement.body = payload.body;
    if (payload.status !== undefined) requirement.status = payload.status;
    if (payload.insightIds !== undefined) requirement.insight_ids = payload.insightIds;
    return request<Requirement>(`/projects/${projectId}/requirements/${requirementId}`, {
      method: "PATCH",
      body: JSON.stringify({ requirement }),
    });
  },
  listConversations: (projectId: number) =>
    request<ProductConversation[]>(`/projects/${projectId}/conversations`),
  getConversation: (
    projectId: number,
    conversationId: number,
    opts?: { limit?: number; before?: number },
  ) => {
    const params = new URLSearchParams();
    if (opts?.limit) params.set("limit", String(opts.limit));
    if (opts?.before) params.set("before", String(opts.before));
    const qs = params.toString();
    return request<ProductConversation & { has_more?: boolean }>(
      `/projects/${projectId}/conversations/${conversationId}${qs ? `?${qs}` : ""}`,
    );
  },
  createConversation: (
    projectId: number,
    payload: { persona: string; title?: string; externalRef?: string; channel?: string },
  ) =>
    request<ProductConversation>(`/projects/${projectId}/conversations`, {
      method: "POST",
      body: JSON.stringify({
        conversation: {
          persona: payload.persona,
          title: payload.title,
          external_ref: payload.externalRef,
          channel: payload.channel,
        },
      }),
    }),
  sendConversationMessage: (projectId: number, conversationId: number, content: string) =>
    request<{ conversation: ProductConversation; response: { status: string; content?: string } }>(
      `/projects/${projectId}/conversations/${conversationId}/messages`,
      {
        method: "POST",
        body: JSON.stringify({
          message: {
            content,
          },
        }),
      },
    ),

  // --- Runtime control: branches, steering, model switching ---

  listBranches: (projectId: number, conversationId: number) =>
    request<{
      branches: Array<{
        id: number;
        branch_uuid: string;
        label: string;
        parent_branch_id: number | null;
        forked_from_sequence: number | null;
        turn_count: number;
        inserted_at: string;
        active: boolean;
      }>;
      active_branch_uuid: string | null;
    }>(`/projects/${projectId}/conversations/${conversationId}/branches`),

  createBranch: (
    projectId: number,
    conversationId: number,
    payload: { fromTurnId: number; label: string },
  ) =>
    request<{
      branch_uuid: string;
      label: string;
      active: boolean;
    }>(`/projects/${projectId}/conversations/${conversationId}/branches`, {
      method: "POST",
      body: JSON.stringify({
        from_turn_id: payload.fromTurnId,
        label: payload.label,
      }),
    }),

  activateBranch: (projectId: number, conversationId: number, branchUuid: string) =>
    request<{ active_branch_uuid: string }>(
      `/projects/${projectId}/conversations/${conversationId}/branches/${branchUuid}/activate`,
      { method: "POST", body: "{}" },
    ),

  sendSteeringMessage: (projectId: number, conversationId: number, content: string) =>
    request<{ queued: boolean }>(
      `/projects/${projectId}/conversations/${conversationId}/steer`,
      {
        method: "POST",
        body: JSON.stringify({ content }),
      },
    ),

  listModels: (projectId: number, conversationId: number) =>
    request<{ available: string[]; current_override: string | null }>(
      `/projects/${projectId}/conversations/${conversationId}/models`,
    ),

  switchModel: (
    projectId: number,
    conversationId: number,
    payload: { model: string; reason: string },
  ) =>
    request<{
      model: string;
      provider_id: number;
      provider_name: string;
      reason: string;
    }>(`/projects/${projectId}/conversations/${conversationId}/model`, {
      method: "POST",
      body: JSON.stringify(payload),
    }),
  getAgentFeed: (projectId: number, persona: string, limit = 20, offset = 0) =>
    request<{
      items: Array<{
        type: "node" | "artifact";
        node_type?: string;
        node_id?: number;
        artifact_id?: number;
        title: string;
        body?: string;
        status?: string;
        version?: number;
        change_summary?: string;
        upstream_count?: number;
        downstream_count?: number;
        flag_count?: number;
        origin?: string;
        origin_title?: string | null;
        created_at?: string;
        updated_at?: string;
      }>;
      stats: {
        nodes_created: number;
        nodes_accepted: number;
        acceptance_rate: number;
        spend_cents: number;
        tokens: number;
        activity_heatmap: number[][];
      };
      total_count: number;
    }>(`/projects/${projectId}/agents/${persona}/feed?limit=${limit}&offset=${offset}`),
  getAgentWork: (projectId: number, persona: string) =>
    request<{
      current: Array<{ type: string; title: string }>;
      completed: Array<{ type: string; title: string; node_id?: number; node_type?: string; status?: string; at?: string }>;
      queued: Array<{ type: string; title: string }>;
    }>(`/projects/${projectId}/agents/${persona}/work`),
  getAgentStatuses: (projectId: number) =>
    request<Array<{
      persona: string;
      state: string;
      summary?: string | null;
      active_count?: number;
      working_detail: string | null;
      ready_count: number;
      last_active_at: string | null;
    }>>(`/projects/${projectId}/agents/statuses`),
  listAgentTasks: (
    projectId: number,
    filters: { state?: string; agent_id?: string; search?: string; exclude_terminal?: boolean } = {},
  ) => {
    const params = new URLSearchParams();
    if (filters.state) params.set("state", filters.state);
    if (filters.agent_id) params.set("agent_id", filters.agent_id);
    if (filters.search) params.set("search", filters.search);
    if (filters.exclude_terminal) params.set("exclude_terminal", "true");
    const qs = params.toString();
    return request<AgentTask[]>(
      `/projects/${projectId}/agent_tasks${qs ? `?${qs}` : ""}`,
    );
  },
  transitionAgentTask: (projectId: number, id: number, to: string, reason?: string) =>
    request<AgentTask>(`/projects/${projectId}/agent_tasks/${id}/state`, {
      method: "PATCH",
      body: JSON.stringify({ to, reason }),
    }),
  redirectAgentTask: (projectId: number, id: number, refinement: string) =>
    request<AgentTask>(`/projects/${projectId}/agent_tasks/${id}/redirect`, {
      method: "POST",
      body: JSON.stringify({ refinement }),
    }),
  deferAgentTask: (projectId: number, id: number, hours: number) =>
    request<AgentTask>(`/projects/${projectId}/agent_tasks/${id}/defer`, {
      method: "POST",
      body: JSON.stringify({ hours }),
    }),
  listProposals: (projectId: number, filters: { agent_id?: string } = {}) => {
    const params = new URLSearchParams();
    if (filters.agent_id) params.set("agent_id", filters.agent_id);
    const qs = params.toString();
    return request<AgentTask[]>(
      `/projects/${projectId}/proposals${qs ? `?${qs}` : ""}`,
    );
  },
  recordProposalDecisions: (
    projectId: number,
    id: number,
    decisions: Array<{ item_index: number; decision: string; edits?: unknown }>,
  ) =>
    request<AgentTask>(`/projects/${projectId}/proposals/${id}/decisions`, {
      method: "POST",
      body: JSON.stringify({ decisions }),
    }),
  applyProposal: (projectId: number, id: number) =>
    request<AgentTask>(`/projects/${projectId}/proposals/${id}/apply`, {
      method: "POST",
      body: JSON.stringify({}),
    }),
  dismissProposal: (projectId: number, id: number, reason?: string) =>
    request<AgentTask>(`/projects/${projectId}/proposals/${id}/dismiss`, {
      method: "POST",
      body: JSON.stringify({ reason }),
    }),
  listStreamEntries: (
    projectId: number,
    filters: { tab?: string; unread?: boolean } = {},
  ) => {
    const params = new URLSearchParams();
    if (filters.tab) params.set("tab", filters.tab);
    if (filters.unread) params.set("unread", "true");
    const qs = params.toString();
    return request<StreamEntry[]>(
      `/projects/${projectId}/stream_entries${qs ? `?${qs}` : ""}`,
    );
  },
  getStreamEntryCounts: (projectId: number) =>
    request<{ activity: number; needs_you: number; blockers: number; total: number }>(
      `/projects/${projectId}/stream_entries/counts`,
    ),
  markStreamEntriesRead: (projectId: number, ids: number[]) =>
    request<{ marked: number }>(`/projects/${projectId}/stream_entries/read`, {
      method: "POST",
      body: JSON.stringify({ ids }),
    }),
  dismissStreamEntry: (projectId: number, id: number) =>
    request<{ actioned: number }>(`/projects/${projectId}/stream_entries/${id}/dismiss`, {
      method: "POST",
      body: JSON.stringify({}),
    }),
  getStreamItemLineage: (projectId: number, item: StreamTabItem) => {
    const params = new URLSearchParams();
    if (item.stream_entry_id) params.set("stream_entry_id", String(item.stream_entry_id));
    if (item.source_task_id) params.set("source_task_id", String(item.source_task_id));
    if (item.context_type) params.set("context_type", item.context_type);
    if (item.context_id) params.set("context_id", String(item.context_id));
    if (item.kind) params.set("kind", item.kind);
    const qs = params.toString();
    return request<{
      chain: Array<{ id: number; type: string; title: string; relation?: string | null }>;
      why: string | null;
      why_structured: {
        root: string | null;
        path: string | null;
        summary: string | null;
      } | null;
      node_type: string | null;
      node_id: number | null;
      chain_b?: Array<{ id: number; type: string; title: string; relation?: string | null }> | null;
    }>(`/projects/${projectId}/stream/lineage${qs ? `?${qs}` : ""}`);
  },
  listFlows: (projectId: number) =>
    request<Flow[]>(`/projects/${projectId}/flows`),
  getAnalytics: (projectId: number) =>
    request<{
      period: string;
      productivity: {
        nodes_created: number;
        nodes_accepted: number;
        acceptance_rate: number;
        cost_per_accepted_node_cents: number;
        by_node_type: Record<string, number>;
      };
      spend: {
        total_tokens: number;
        total_cost_cents: number;
        projected_cost_cents: number;
        budget_limit_cents: number;
        budget_used_percent: number;
      };
      spend_by_agent: Array<{ persona: string; tokens: number; cost_cents: number }>;
      this_week: { cost_cents: number; vs_last_week_percent: number };
      today: { cost_cents: number };
    }>(`/projects/${projectId}/analytics`),
  getSpendSummary: (projectId: number) =>
    request<{
      month_tokens: number;
      month_cost_cents: number;
      week_tokens: number;
      week_cost_cents: number;
      today_tokens: number;
      today_cost_cents: number;
      yesterday_tokens: number;
      yesterday_cost_cents: number;
      budget_cents: number | null;
      budget_percent: number | null;
    }>(`/projects/${projectId}/spend/summary`),
  getSpendAnalytics: (projectId: number, period = "30d", from?: string, to?: string) => {
    const params = new URLSearchParams({ period });
    if (from) params.set("from", from);
    if (to) params.set("to", to);
    return request<{
      summary: { month_tokens: number; month_cost_cents: number; budget_cents: number | null; budget_percent: number | null };
      spend_by_agent: Array<{ persona: string; tokens: number; cost_cents: number; by_model: Array<{ model: string; tokens_in: number; tokens_out: number; cost_cents: number }> }>;
      spend_by_model: Array<{ model: string; tokens_in: number; tokens_out: number; cost_cents: number }>;
      daily_spend: Array<{ date: string; tokens: number; cost_cents: number }>;
    }>(`/projects/${projectId}/spend/analytics?${params.toString()}`);
  },
  getSpendLog: (projectId: number, limit = 25, offset = 0) =>
    request<{
      entries: Array<{
        id: number;
        agent: string;
        model: string;
        tokens_in: number;
        tokens_out: number;
        cost_cents: number;
        inserted_at: string;
      }>;
      total: number;
      limit: number;
      offset: number;
    }>(`/projects/${projectId}/spend/log?limit=${limit}&offset=${offset}`),
  exportProject: (projectId: number) =>
    request<ProjectExport>(`/projects/${projectId}/exports`, {
      method: "POST",
    }),
  getStream: (projectId: number, role?: string) =>
    request<{
      right_now: StreamItem[];
      recently: StreamItem[];
      emerging: StreamItem[];
    }>(`/projects/${projectId}/stream${role ? `?role=${role}` : ""}`),
  getMyWork: (projectId: number) =>
    request<MyWorkData>(`/projects/${projectId}/my-work`),
  getTrail: (
    projectId: number,
    nodeType: string,
    nodeId: number,
    direction?: string,
    depth?: number,
  ) =>
    request<{
      center: TrailNode;
      upstream: TrailChainNode[];
      downstream: TrailChainNode[];
      flags: TrailFlag[];
    }>(
      `/projects/${projectId}/graph/trail?node_type=${nodeType}&node_id=${nodeId}${direction ? `&direction=${direction}` : ""}${depth ? `&depth=${depth}` : ""}`,
    ),
  getWhy: (projectId: number, nodeType: string, nodeId: number, force = false) =>
    request<WhyPayload>(
      `/projects/${projectId}/graph/why?node_type=${nodeType}&node_id=${nodeId}${force ? "&force=true" : ""}`,
    ),
  getStreamTabCounts: (projectId: number) =>
    request<StreamTabCounts>(`/projects/${projectId}/stream/tabs/counts`),
  getStreamTab: (
    projectId: number,
    tab: StreamTab,
    filters: { agent_id?: string; context_type?: string; search?: string } = {},
  ) => {
    const params = new URLSearchParams();
    if (filters.agent_id) params.set("agent_id", filters.agent_id);
    if (filters.context_type) params.set("context_type", filters.context_type);
    if (filters.search) params.set("search", filters.search);
    const qs = params.toString();
    return request<StreamTabItem[]>(
      `/projects/${projectId}/stream/tabs/${tab}${qs ? `?${qs}` : ""}`,
    );
  },
  getOnboarding: (projectId: number) =>
    request<OnboardingStatus>(`/projects/${projectId}/onboarding`),
  startOnboarding: (projectId: number) =>
    request<OnboardingStatus>(`/projects/${projectId}/onboarding/start`, {
      method: "POST",
      body: JSON.stringify({}),
    }),
  skipOnboarding: (projectId: number) =>
    request<OnboardingStatus>(`/projects/${projectId}/onboarding/skip`, {
      method: "POST",
      body: JSON.stringify({}),
    }),
  resetOnboarding: (projectId: number) =>
    request<OnboardingStatus>(`/projects/${projectId}/onboarding/reset`, {
      method: "POST",
      body: JSON.stringify({}),
    }),
  // Decisions
  listDecisions: (projectId: number) =>
    request<Decision[]>(`/projects/${projectId}/decisions`),
  createDecision: (projectId: number, payload: { title: string; body: string; status?: string; alternatives_considered?: Array<{ title: string; description: string; rejected_reason: string }> }) =>
    request<Decision>(`/projects/${projectId}/decisions`, { method: "POST", body: JSON.stringify({ decision: payload }) }),
  updateDecision: (projectId: number, id: number, payload: Partial<Decision>) =>
    request<Decision>(`/projects/${projectId}/decisions/${id}`, { method: "PATCH", body: JSON.stringify({ decision: payload }) }),
  deleteDecision: (projectId: number, id: number) =>
    request<void>(`/projects/${projectId}/decisions/${id}`, { method: "DELETE" }),
  // Strategies
  listStrategies: (projectId: number) =>
    request<Strategy[]>(`/projects/${projectId}/strategies`),
  createStrategy: (projectId: number, payload: { title: string; body: string; status?: string }) =>
    request<Strategy>(`/projects/${projectId}/strategies`, { method: "POST", body: JSON.stringify({ strategy: payload }) }),
  // Architecture nodes
  listArchitectureNodes: (projectId: number) =>
    request<ArchitectureNode[]>(`/projects/${projectId}/architecture_nodes`),
  createArchitectureNode: (projectId: number, payload: { title: string; body: string; node_type: string }) =>
    request<ArchitectureNode>(`/projects/${projectId}/architecture_nodes`, { method: "POST", body: JSON.stringify({ architecture_node: payload }) }),
  // Design nodes
  listDesignNodes: (projectId: number) =>
    request<DesignNode[]>(`/projects/${projectId}/design_nodes`),
  createDesignNode: (projectId: number, payload: { title: string; body: string; node_type: string }) =>
    request<DesignNode>(`/projects/${projectId}/design_nodes`, { method: "POST", body: JSON.stringify({ design_node: payload }) }),
  // Tasks
  listTasks: (projectId: number) =>
    request<ProductTask[]>(`/projects/${projectId}/tasks`),
  createTask: (projectId: number, payload: { title: string; body: string; priority?: string }) =>
    request<ProductTask>(`/projects/${projectId}/tasks`, { method: "POST", body: JSON.stringify({ task: payload }) }),
  updateTask: (projectId: number, id: number, payload: Partial<ProductTask>) =>
    request<ProductTask>(`/projects/${projectId}/tasks/${id}`, { method: "PATCH", body: JSON.stringify({ task: payload }) }),
  // Learnings
  listLearnings: (projectId: number) =>
    request<Learning[]>(`/projects/${projectId}/learnings`),
  createLearning: (projectId: number, payload: { title: string; body: string; learning_type: string }) =>
    request<Learning>(`/projects/${projectId}/learnings`, { method: "POST", body: JSON.stringify({ learning: payload }) }),
  // Constraints
  listConstraints: (projectId: number) =>
    request<Constraint[]>(`/projects/${projectId}/constraints`),
  createConstraint: (projectId: number, payload: { title: string; body: string; scope: string; enforcement: string }) =>
    request<Constraint>(`/projects/${projectId}/constraints`, { method: "POST", body: JSON.stringify({ constraint: payload }) }),
  updateConstraint: (projectId: number, id: number, payload: Partial<{ title: string; body: string; scope: string; enforcement: string; status: string }>) =>
    request<Constraint>(`/projects/${projectId}/constraints/${id}`, { method: "PATCH", body: JSON.stringify({ constraint: payload }) }),
  deleteConstraint: (projectId: number, id: number) =>
    request<void>(`/projects/${projectId}/constraints/${id}`, { method: "DELETE" }),

  // Watch Targets
  listWatchTargets: (projectId: number) =>
    request<WatchTarget[]>(`/projects/${projectId}/watch_targets`),
  createWatchTarget: (projectId: number, payload: { target_type: string; value: string; check_interval_hours?: number }) =>
    request<WatchTarget>(`/projects/${projectId}/watch_targets`, { method: "POST", body: JSON.stringify({ watch_target: payload }) }),
  deleteWatchTarget: (projectId: number, id: number) =>
    request<void>(`/projects/${projectId}/watch_targets/${id}`, { method: "DELETE" }),

  // Agent rules (Coherence / Continuous Research tuning)
  listAgentRules: (projectId: number, agentId: "coherence" | "continuous_research") =>
    request<AgentRule[]>(`/projects/${projectId}/agent_rules?agent_id=${agentId}`),
  createAgentRule: (
    projectId: number,
    payload: {
      agent_id: "coherence" | "continuous_research";
      rule_type: "mute_category" | "ignore_pattern" | "prioritize_category";
      value: string;
    },
  ) =>
    request<AgentRule>(`/projects/${projectId}/agent_rules`, {
      method: "POST",
      body: JSON.stringify(payload),
    }),
  deleteAgentRule: (projectId: number, id: number) =>
    request<void>(`/projects/${projectId}/agent_rules/${id}`, { method: "DELETE" }),

  // Routines
  listRoutines: (projectId: number) =>
    request<Routine[]>(`/projects/${projectId}/routines`),
  createRoutine: (projectId: number, payload: {
    title: string; description?: string; prompt_template: string; assigned_persona: string;
    schedule_type: string; cron_expression?: string; event_trigger?: string; output_target?: string;
  }) =>
    request<Routine>(`/projects/${projectId}/routines`, { method: "POST", body: JSON.stringify({ routine: payload }) }),
  updateRoutine: (projectId: number, id: number, payload: Record<string, unknown>) =>
    request<Routine>(`/projects/${projectId}/routines/${id}`, { method: "PATCH", body: JSON.stringify({ routine: payload }) }),
  deleteRoutine: (projectId: number, id: number) =>
    request<void>(`/projects/${projectId}/routines/${id}`, { method: "DELETE" }),
  runRoutine: (projectId: number, id: number) =>
    request<RoutineRun>(`/projects/${projectId}/routines/${id}/run`, { method: "POST" }),
  listRoutineRuns: (projectId: number, id: number) =>
    request<RoutineRun[]>(`/projects/${projectId}/routines/${id}/runs`),

  // Knowledge Entries
  listKnowledgeEntries: (projectId: number) =>
    request<KnowledgeEntry[]>(`/projects/${projectId}/knowledge`),
  createKnowledgeEntry: (projectId: number, payload: {
    title: string; content: string; entry_type: string; assigned_personas?: string[];
    source_type?: string; source_url?: string;
  }) =>
    request<KnowledgeEntry>(`/projects/${projectId}/knowledge`, { method: "POST", body: JSON.stringify({ knowledge_entry: payload }) }),
  updateKnowledgeEntry: (projectId: number, id: number, payload: Record<string, unknown>) =>
    request<KnowledgeEntry>(`/projects/${projectId}/knowledge/${id}`, { method: "PATCH", body: JSON.stringify({ knowledge_entry: payload }) }),
  deleteKnowledgeEntry: (projectId: number, id: number) =>
    request<void>(`/projects/${projectId}/knowledge/${id}`, { method: "DELETE" }),
  // Graph flags
  listGraphFlags: (projectId: number) =>
    request<GraphFlag[]>(`/projects/${projectId}/graph/flags`),
  resolveGraphFlag: (projectId: number, flagId: number) =>
    request<GraphFlag>(`/projects/${projectId}/graph/flags/${flagId}/resolve`, { method: "POST", body: JSON.stringify({ resolved_by: "operator" }) }),
  // Graph nodes (for visualization — legacy)
  getGraphNodes: (projectId: number) =>
    request<{ nodes: Array<{ id: string; db_id: number; node_type: string; title: string; status: string; body_excerpt: string }>; edges: Array<{ id: string; source: string; target: string; kind: string; weight: number }> }>(`/projects/${projectId}/graph/nodes`),
  // Graph data (enriched — nodes, edges, flags, density)
  getGraphData: (projectId: number) =>
    request<GraphData>(`/projects/${projectId}/graph/data`),
  // Graph edges (CRUD)
  createGraphEdge: (projectId: number, payload: {
    from_node_type: string;
    from_node_id: number;
    to_node_type: string;
    to_node_id: number;
    kind: string;
    metadata?: Record<string, unknown>;
  }) =>
    request<GraphDataEdge>(`/projects/${projectId}/graph/edges`, {
      method: "POST",
      body: JSON.stringify(payload),
    }),
  deleteGraphEdge: (projectId: number, edgeId: number) =>
    request<void>(`/projects/${projectId}/graph/edges/${edgeId}`, { method: "DELETE" }),
  getGraphEdge: (projectId: number, edgeId: number) =>
    request<GraphDataEdge & { metadata: Record<string, unknown>; inserted_at: string }>(`/projects/${projectId}/graph/edges/${edgeId}`),
  // Graph health
  getGraphHealth: (projectId: number) =>
    request<Record<string, unknown>>(`/projects/${projectId}/graph/health`),
  // Project counts
  getProjectCounts: (projectId: number) =>
    request<ProjectCounts>(`/projects/${projectId}/counts`),

  // Board sessions
  listBoardSessions: (projectId: number, status?: string) =>
    request<BoardSession[]>(`/projects/${projectId}/board_sessions${status ? `?status=${status}` : ""}`),
  createBoardSession: (projectId: number, payload: { title: string; description?: string }) =>
    request<BoardSession>(`/projects/${projectId}/board_sessions`, {
      method: "POST",
      body: JSON.stringify({ board_session: payload }),
    }),
  getBoardSession: (projectId: number, sessionId: number) =>
    request<BoardSession>(`/projects/${projectId}/board_sessions/${sessionId}`),
  updateBoardSession: (projectId: number, sessionId: number, payload: Partial<BoardSession>) =>
    request<BoardSession>(`/projects/${projectId}/board_sessions/${sessionId}`, {
      method: "PATCH",
      body: JSON.stringify({ board_session: payload }),
    }),
  deleteBoardSession: (projectId: number, sessionId: number) =>
    request<void>(`/projects/${projectId}/board_sessions/${sessionId}`, { method: "DELETE" }),

  // Board nodes
  listBoardNodes: (projectId: number, sessionId: number) =>
    request<BoardNode[]>(`/projects/${projectId}/board_sessions/${sessionId}/nodes`),
  createBoardNode: (projectId: number, sessionId: number, payload: {
    node_type: string; title: string; body: string; created_by?: string;
    metadata?: Record<string, unknown>;
  }) =>
    request<BoardNode>(`/projects/${projectId}/board_sessions/${sessionId}/nodes`, {
      method: "POST",
      body: JSON.stringify({ board_node: payload }),
    }),
  updateBoardNode: (projectId: number, sessionId: number, nodeId: number, payload: Partial<BoardNode>) =>
    request<BoardNode>(`/projects/${projectId}/board_sessions/${sessionId}/nodes/${nodeId}`, {
      method: "PATCH",
      body: JSON.stringify({ board_node: payload }),
    }),
  deleteBoardNode: (projectId: number, sessionId: number, nodeId: number) =>
    request<void>(`/projects/${projectId}/board_sessions/${sessionId}/nodes/${nodeId}`, { method: "DELETE" }),
  listBoardSessionEvents: (projectId: number, sessionId: number) =>
    request<BoardSessionEvent[]>(`/projects/${projectId}/board_sessions/${sessionId}/events`),
  promoteBoardNode: (projectId: number, sessionId: number, nodeId: number) =>
    request<{ board_node: BoardNode; promoted_node_type: string; promoted_node_id: number }>(
      `/projects/${projectId}/board_sessions/${sessionId}/nodes/${nodeId}/promote`,
      { method: "POST" },
    ),
  promoteBoardNodesBatch: (projectId: number, sessionId: number, nodeIds: number[]) =>
    request<{ promoted_count: number; nodes: BoardNode[] }>(
      `/projects/${projectId}/board_sessions/${sessionId}/nodes/promote_batch`,
      { method: "POST", body: JSON.stringify({ node_ids: nodeIds }) },
    ),
  toggleBoardNodeReaction: (projectId: number, sessionId: number, nodeId: number, reaction: string, userId: string) =>
    request<BoardNode>(
      `/projects/${projectId}/board_sessions/${sessionId}/nodes/${nodeId}/react`,
      { method: "POST", body: JSON.stringify({ reaction, user_id: userId }) },
    ),

  // Board edges
  createBoardEdge: (projectId: number, sessionId: number, payload: {
    from_board_node_id: number; to_board_node_id: number; kind: string;
  }) =>
    request<BoardEdge>(`/projects/${projectId}/board_sessions/${sessionId}/edges`, {
      method: "POST",
      body: JSON.stringify({ board_edge: payload }),
    }),
  deleteBoardEdge: (projectId: number, sessionId: number, edgeId: number) =>
    request<void>(`/projects/${projectId}/board_sessions/${sessionId}/edges/${edgeId}`, { method: "DELETE" }),

  // Artifacts
  listArtifacts: (projectId: number, opts?: { status?: string; artifact_type?: string; search?: string }) => {
    const params = new URLSearchParams();
    if (opts?.status) params.set("status", opts.status);
    if (opts?.artifact_type) params.set("artifact_type", opts.artifact_type);
    if (opts?.search) params.set("search", opts.search);
    const qs = params.toString();
    return request<Artifact[]>(`/projects/${projectId}/artifacts${qs ? `?${qs}` : ""}`);
  },
  getArtifact: (projectId: number, artifactId: number) =>
    request<Artifact>(`/projects/${projectId}/artifacts/${artifactId}`),
  createArtifact: (projectId: number, payload: {
    title: string; artifact_type: string; body: string; owner_persona: string;
  }) =>
    request<Artifact>(`/projects/${projectId}/artifacts`, {
      method: "POST",
      body: JSON.stringify({ artifact: payload }),
    }),
  updateArtifact: (projectId: number, artifactId: number, payload: {
    body: string; last_updated_by: string; change_summary?: string;
  }) =>
    request<Artifact>(`/projects/${projectId}/artifacts/${artifactId}`, {
      method: "PATCH",
      body: JSON.stringify({ artifact: payload }),
    }),
  listArtifactVersions: (projectId: number, artifactId: number) =>
    request<ArtifactVersion[]>(`/projects/${projectId}/artifacts/${artifactId}/versions`),

  // Simulations
  listSimulations: (projectId: number) =>
    request<Simulation[]>(`/projects/${projectId}/simulations`),
  createSimulation: (projectId: number, payload: {
    title?: string;
    scenario?: string;
    archetypes?: SimArchetype[];
    selected_node_ids?: Array<{ node_type: string; node_id: number }>;
    population_size?: number;
    max_ticks?: number;
    comparison_mode?: boolean;
    scenario_b?: string;
  }) =>
    request<Simulation>(`/projects/${projectId}/simulations`, {
      method: "POST",
      body: JSON.stringify({ simulation: payload }),
    }),
  getSimulation: (projectId: number, simulationId: number) =>
    request<Simulation>(`/projects/${projectId}/simulations/${simulationId}`),
  getSimulationArchetypes: (projectId: number) =>
    request<SimArchetype[]>(`/projects/${projectId}/simulations/archetypes`),
  getSimulationGraphNodes: (projectId: number) =>
    request<SimGraphNode[]>(`/projects/${projectId}/simulations/graph_nodes`),
  getSimulationEstimate: (projectId: number, params: { population_size: number; max_ticks: number; comparison_mode: boolean }) => {
    const qs = new URLSearchParams({
      population_size: String(params.population_size),
      max_ticks: String(params.max_ticks),
      comparison_mode: String(params.comparison_mode),
    }).toString();
    return request<SimEstimate>(`/projects/${projectId}/simulations/estimate?${qs}`);
  },
  importSimulationResults: (projectId: number, simulationId: number) =>
    request<Simulation>(`/projects/${projectId}/simulations/${simulationId}/import`, {
      method: "POST",
    }),

  getContradictionBadges: (projectId: number) =>
    request<ContradictionBadge[]>(`/projects/${projectId}/contradictions/badges`),
  listContradictions: (
    projectId: number,
    opts: { status?: string; min_severity?: string; limit?: number } = {},
  ) => {
    const qs = new URLSearchParams();
    if (opts.status) qs.set("status", opts.status);
    if (opts.min_severity) qs.set("min_severity", opts.min_severity);
    if (opts.limit) qs.set("limit", String(opts.limit));
    const suffix = qs.toString() ? `?${qs.toString()}` : "";
    return request<Contradiction[]>(`/projects/${projectId}/contradictions${suffix}`);
  },
  dismissContradiction: (projectId: number, id: number, reason?: string) =>
    request<Contradiction>(`/projects/${projectId}/contradictions/${id}/dismiss`, {
      method: "POST",
      body: JSON.stringify(reason ? { reason } : {}),
    }),
  resolveContradiction: (projectId: number, id: number, reason?: string) =>
    request<Contradiction>(`/projects/${projectId}/contradictions/${id}/resolve`, {
      method: "POST",
      body: JSON.stringify(reason ? { reason } : {}),
    }),
  updateMentionIntent: (
    projectId: number,
    mentionId: number,
    intent: "request_task" | "share_context" | "request_input" | "notify",
  ) =>
    request<Mention>(`/projects/${projectId}/mentions/${mentionId}/intent`, {
      method: "PATCH",
      body: JSON.stringify({ intent }),
    }),

  // Cycle 2 simple user auth
  devLogin: (payload: { email: string; display_name?: string }) =>
    request<CurrentUser>("/user_auth/dev_login", {
      method: "POST",
      body: JSON.stringify(payload),
    }),
  currentUser: () => request<CurrentUser>("/user_auth/me"),
  logoutUser: () =>
    request<{ signed_out: boolean }>("/user_auth/logout", { method: "POST" }),
  seedIdentity: (
    nodes: { node_type: string; title: string; body?: string }[],
  ) =>
    request<{ seeded: number }>("/user_auth/identity_bootstrap", {
      method: "POST",
      body: JSON.stringify({ nodes }),
    }),
  listSchemaProposals: (
    projectId: number,
    opts: { status?: string } = {},
  ) => {
    const query = opts.status ? `?status=${encodeURIComponent(opts.status)}` : "";
    return request<SchemaProposal[]>(`/projects/${projectId}/schema/proposals${query}`);
  },
  createSchemaProposal: (
    projectId: number,
    proposal: SchemaProposalRequest,
  ) =>
    request<SchemaProposal>(`/projects/${projectId}/schema/proposals`, {
      method: "POST",
      body: JSON.stringify({ proposal }),
    }),
  decideSchemaProposal: (
    projectId: number,
    proposalId: number,
    action: "approve" | "reject",
    opts: { by_operator?: boolean } = {},
  ) =>
    request<SchemaProposal>(`/projects/${projectId}/schema/proposals/${proposalId}`, {
      method: "PATCH",
      body: JSON.stringify({ action, by_operator: opts.by_operator ?? true }),
    }),
};

export type ContradictionBadge = {
  node_type: string;
  node_id: number;
  total: number;
  high: number;
  medium: number;
  low: number;
};

export type CurrentUser = {
  id: string;
  email: string;
  display_name: string | null;
  avatar_url: string | null;
  workspaces: { id: string; name: string; slug: string }[];
};

export type StreamItem = {
  id: string;
  category: string;
  title: string;
  summary: string;
  narrative?: string;
  node_type: string;
  node_id: number;
  urgency: "action" | "info" | "emerging";
  timestamp: string;
  connections: Record<string, number>;
  metadata: Record<string, unknown>;
  type?: "group";
  items?: StreamItem[];
};

export type MyWorkItem = {
  type: string;
  title: string;
  node_type?: string;
  node_id?: number;
  session_id?: number;
  session_title?: string;
  node_count?: number;
  agent?: string;
  flag_type?: string;
  priority?: string;
  status?: string;
  assignee?: string;
  actions?: string[];
  created_at?: string;
  updated_at?: string;
  at?: string;
};

export type MyWorkData = {
  needs_input: MyWorkItem[];
  active_work: MyWorkItem[];
  recent_output: MyWorkItem[];
};

export type TrailNode = {
  node_type: string;
  node_id: number;
  title: string;
  body?: string;
  status: string;
  inserted_at?: string;
  updated_at?: string;
  metadata?: Record<string, unknown>;
  alternatives_considered?: Array<{ title: string; description?: string; rejected_reason?: string }>;
  decided_by?: string;
  decided_at?: string;
  upstream_counts?: Record<string, number>;
  downstream_counts?: Record<string, number>;
  constraints?: Array<{ id: number; title: string; body: string }>;
};

export type TrailChainNode = {
  node_type: string;
  node_id: number;
  edge_kind: string;
  title: string;
  status: string;
  summary?: string;
  updated_at?: string;
  upstream_count?: number;
  downstream_count?: number;
};

export type TrailFlag = {
  id: number;
  flag_type: string;
  reason: string;
  status: string;
  source_agent: string;
};

export type Artifact = {
  id: number;
  project_id: number;
  title: string;
  artifact_type: string;
  body: string;
  owner_persona: string;
  status: string;
  version: number;
  last_updated_by?: string;
  metadata: Record<string, unknown>;
  inserted_at: string;
  updated_at: string;
};

export type ArtifactVersion = {
  id: number;
  artifact_id: number;
  version: number;
  body: string;
  change_summary?: string;
  updated_by: string;
  metadata: Record<string, unknown>;
  inserted_at: string;
};
