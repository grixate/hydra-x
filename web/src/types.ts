export type AgentSummary = {
  id: number;
  name: string;
  slug: string;
  role: string;
  workspace_root: string;
  status: string;
};

export type Project = {
  id: number;
  name: string;
  slug: string;
  description?: string | null;
  status: string;
  metadata: Record<string, unknown>;
  researcher_agent?: AgentSummary | null;
  strategist_agent?: AgentSummary | null;
  inserted_at?: string;
  updated_at?: string;
};

export type SourceChunk = {
  id: number;
  ordinal: number;
  content: string;
  token_count: number;
  metadata: Record<string, unknown>;
  inserted_at?: string;
  updated_at?: string;
};

export type Source = {
  id: number;
  project_id: number;
  title: string;
  source_type: string;
  external_ref?: string | null;
  processing_status: string;
  content: string;
  metadata: Record<string, unknown>;
  source_chunk_count: number;
  chunks?: SourceChunk[] | null;
  inserted_at?: string;
  updated_at?: string;
};

export type Citation = {
  id?: number;
  source_chunk_id?: number;
  quote?: string;
  label?: string;
  source_title?: string;
  content?: string;
  source_chunk?: {
    id: number;
    source_id: number;
    source_title?: string | null;
    content: string;
    ordinal: number;
  };
};

export type ProductMessage = {
  id: number;
  hydra_turn_id?: number | null;
  role: "user" | "assistant" | string;
  content: string;
  citations: Citation[];
  metadata: Record<string, unknown>;
  inserted_at?: string;
  updated_at?: string;
};

export type ProductConversation = {
  id: number;
  project_id: number;
  hydra_conversation_id: number;
  persona: "researcher" | "strategist" | string;
  title?: string | null;
  status: string;
  metadata: Record<string, unknown>;
  hydra_channel?: string | null;
  hydra_external_ref?: string | null;
  message_count: number;
  latest_message?: ProductMessage | null;
  channel_state?: {
    status?: string;
    provider?: string | null;
    tool_rounds?: number;
    resumable?: boolean;
  };
  messages?: ProductMessage[] | null;
  inserted_at?: string;
  updated_at?: string;
};

export type InsightEvidence = {
  id?: number;
  source_chunk_id: number;
  quote: string;
  metadata?: Record<string, unknown>;
  source_chunk?: {
    id: number;
    source_id: number;
    source_title?: string | null;
    content: string;
    ordinal: number;
  };
};

export type Insight = {
  id: number;
  project_id: number;
  title: string;
  body: string;
  status: string;
  metadata: Record<string, unknown>;
  evidence: InsightEvidence[];
  linked_requirements: Array<{
    requirement_id: number;
    metadata?: Record<string, unknown>;
  }>;
  inserted_at?: string;
  updated_at?: string;
};

export type Requirement = {
  id: number;
  project_id: number;
  title: string;
  body: string;
  status: string;
  grounded: boolean;
  metadata: Record<string, unknown>;
  insights: Insight[];
  inserted_at?: string;
  updated_at?: string;
};

export type ProjectCounts = {
  sources: number;
  insights: number;
  requirements: number;
  conversations: number;
};

export type SourceProgress = {
  status: string;
  stage?: string;
  chunk_count?: number;
  error?: string;
};

export type ProjectExport = {
  project_id: number;
  markdown_path: string;
  json_path: string;
  bundle_dir: string;
  counts: {
    sources: number;
    insights: number;
    requirements: number;
    conversations: number;
  };
};
