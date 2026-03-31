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
  architect_agent?: AgentSummary | null;
  designer_agent?: AgentSummary | null;
  memory_agent?: AgentSummary | null;
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
  decisions: number;
  strategies: number;
  design_nodes: number;
  architecture_nodes: number;
  tasks: number;
  learnings: number;
  flags: number;
};

export type SourceProgress = {
  status: string;
  stage?: string;
  chunk_count?: number;
  error?: string;
};

export type Decision = {
  id: number;
  project_id: number;
  title: string;
  body: string;
  status: string;
  decided_by?: string | null;
  decided_at?: string | null;
  alternatives_considered: Array<{
    title: string;
    description: string;
    rejected_reason: string;
  }>;
  metadata: Record<string, unknown>;
  inserted_at?: string;
  updated_at?: string;
};

export type Strategy = {
  id: number;
  project_id: number;
  title: string;
  body: string;
  status: string;
  metadata: Record<string, unknown>;
  inserted_at?: string;
  updated_at?: string;
};

export type ArchitectureNode = {
  id: number;
  project_id: number;
  title: string;
  body: string;
  node_type: string;
  status: string;
  metadata: Record<string, unknown>;
  inserted_at?: string;
  updated_at?: string;
};

export type DesignNode = {
  id: number;
  project_id: number;
  title: string;
  body: string;
  node_type: string;
  status: string;
  metadata: Record<string, unknown>;
  inserted_at?: string;
  updated_at?: string;
};

export type ProductTask = {
  id: number;
  project_id: number;
  title: string;
  body: string;
  status: string;
  assignee?: string | null;
  priority: string;
  effort_estimate?: string | null;
  metadata: Record<string, unknown>;
  inserted_at?: string;
  updated_at?: string;
};

export type Learning = {
  id: number;
  project_id: number;
  title: string;
  body: string;
  learning_type: string;
  status: string;
  metadata: Record<string, unknown>;
  inserted_at?: string;
  updated_at?: string;
};

export type GraphFlag = {
  id: number;
  project_id: number;
  node_type: string;
  node_id: number;
  flag_type: string;
  reason?: string | null;
  source_agent?: string | null;
  status: string;
  resolved_by?: string | null;
  resolved_at?: string | null;
  inserted_at?: string;
  updated_at?: string;
};

export type WatchTarget = {
  id: number;
  project_id: number;
  target_type: string;
  value: string;
  check_interval_hours: number;
  last_checked_at?: string | null;
  status: string;
  metadata: Record<string, unknown>;
  inserted_at?: string;
  updated_at?: string;
};

export type Constraint = {
  id: number;
  project_id: number;
  title: string;
  body: string;
  scope: string;
  enforcement: string;
  status: string;
  metadata: Record<string, unknown>;
  inserted_at?: string;
  updated_at?: string;
};

export type Routine = {
  id: number;
  project_id: number;
  title: string;
  description?: string | null;
  prompt_template: string;
  assigned_persona: string;
  schedule_type: string;
  cron_expression?: string | null;
  event_trigger?: string | null;
  timezone: string;
  output_target: string;
  status: string;
  last_run_at?: string | null;
  last_run_status?: string | null;
  last_run_tokens?: number | null;
  metadata: Record<string, unknown>;
  inserted_at?: string;
  updated_at?: string;
};

export type RoutineRun = {
  id: number;
  routine_id: number;
  started_at: string;
  completed_at?: string | null;
  status: string;
  prompt_resolved?: string | null;
  output?: string | null;
  token_count?: number | null;
  cost_cents?: number | null;
  metadata: Record<string, unknown>;
  inserted_at?: string;
};

export type KnowledgeEntry = {
  id: number;
  project_id: number;
  title: string;
  content: string;
  entry_type: string;
  assigned_personas: string[];
  source_type: string;
  source_url?: string | null;
  status: string;
  metadata: Record<string, unknown>;
  inserted_at?: string;
  updated_at?: string;
};

export type TaskFeedback = {
  id: number;
  task_id: number;
  rating: "good" | "needs_improvement" | "poor";
  comment?: string | null;
  feedback_tags: string[];
  created_by: string;
  metadata: Record<string, unknown>;
  inserted_at?: string;
};

export type GraphDataNode = {
  id: string;
  node_type: string;
  node_id: number;
  title: string;
  status: string;
  body: string;
  connection_count: number;
  upstream_count: number;
  downstream_count: number;
  flag_count: number;
  inserted_at?: string;
  updated_at?: string;
};

export type GraphDataEdge = {
  id: number;
  source: string;
  target: string;
  kind: string;
  weight: number;
};

export type GraphDataFlag = {
  id: number;
  node_id: string;
  flag_type: string;
  reason: string;
  status: string;
  source_agent: string;
};

export type GraphData = {
  nodes: GraphDataNode[];
  edges: GraphDataEdge[];
  flags: GraphDataFlag[];
  density: Record<string, { count: number; outgoing: number; avg_outgoing: number }>;
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
