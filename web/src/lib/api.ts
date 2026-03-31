import type {
  ArchitectureNode,
  BoardEdge,
  BoardNode,
  BoardSession,
  Decision,
  DesignNode,
  Constraint,
  GraphData,
  GraphDataEdge,
  GraphFlag,
  Insight,
  Learning,
  ProductConversation,
  ProductTask,
  ProjectCounts,
  ProjectExport,
  Project,
  Requirement,
  Source,
  Strategy,
} from "@/types";

const API_PREFIX = import.meta.env.VITE_API_BASE ?? "/api/v1";

type Envelope<T> = {
  data: T;
};

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
    throw new Error(`Request failed (${response.status})`);
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
    payload: {
      title: string;
      body: string;
      status: string;
      evidenceChunkIds: number[];
    },
  ) =>
    request<Insight>(`/projects/${projectId}/insights/${insightId}`, {
      method: "PATCH",
      body: JSON.stringify({
        insight: {
          title: payload.title,
          body: payload.body,
          status: payload.status,
          evidence_chunk_ids: payload.evidenceChunkIds,
        },
      }),
    }),
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
    payload: {
      title: string;
      body: string;
      status: string;
      insightIds: number[];
    },
  ) =>
    request<Requirement>(`/projects/${projectId}/requirements/${requirementId}`, {
      method: "PATCH",
      body: JSON.stringify({
        requirement: {
          title: payload.title,
          body: payload.body,
          status: payload.status,
          insight_ids: payload.insightIds,
        },
      }),
    }),
  listConversations: (projectId: number) =>
    request<ProductConversation[]>(`/projects/${projectId}/conversations`),
  getConversation: (projectId: number, conversationId: number) =>
    request<ProductConversation>(`/projects/${projectId}/conversations/${conversationId}`),
  createConversation: (
    projectId: number,
    payload: { persona: string; title?: string; externalRef?: string },
  ) =>
    request<ProductConversation>(`/projects/${projectId}/conversations`, {
      method: "POST",
      body: JSON.stringify({
        conversation: {
          persona: payload.persona,
          title: payload.title,
          external_ref: payload.externalRef,
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
  createConstraint: (projectId: number, payload: { title: string; body: string; scope: string; enforcement: string }) =>
    request<Constraint>(`/projects/${projectId}/constraints`, { method: "POST", body: JSON.stringify({ constraint: payload }) }),
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
};

export type StreamItem = {
  id: string;
  category: string;
  title: string;
  summary: string;
  node_type: string;
  node_id: number;
  urgency: "action" | "info" | "emerging";
  timestamp: string;
  connections: Record<string, number>;
  metadata: Record<string, unknown>;
};

export type TrailNode = {
  node_type: string;
  node_id: number;
  title: string;
  body?: string;
  status: string;
  updated_at?: string;
};

export type TrailChainNode = {
  node_type: string;
  node_id: number;
  edge_kind: string;
  title: string;
  status: string;
  summary?: string;
};

export type TrailFlag = {
  id: number;
  flag_type: string;
  reason: string;
  status: string;
  source_agent: string;
};
