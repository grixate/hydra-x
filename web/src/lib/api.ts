import type {
  Insight,
  ProductConversation,
  ProjectExport,
  Project,
  Requirement,
  Source,
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
};
