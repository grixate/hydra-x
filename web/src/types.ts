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
  onboarding_session_id?: number | null;
  onboarding_conversation_id?: number | null;
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
  // Source-as-Data (Cycle 3)
  promoted_to_graph?: boolean;
  promoted_at?: string | null;
  archived_at?: string | null;
  // Enriched when returned from /library endpoints:
  score?: number;
  top_chunk?: { id: number; ordinal: number; excerpt: string } | null;
  reference_count?: number;
  referenced_by?: SourceReferenceSummary[];
  inserted_at?: string;
  updated_at?: string;
};

export type SourceReferenceRelationship =
  | "extracted_from"
  | "supports"
  | "cites"
  | "contradicts";

export type SourceReference = {
  id: number;
  source_id: number;
  relationship: SourceReferenceRelationship;
  excerpt?: string | null;
  confidence?: "high" | "medium" | "low" | null;
  page_or_position?: string | null;
  created_by: "agent" | "user" | "system";
  created_at: string;
  source?: Source | null;
};

export type SourceReferenceSummary = {
  node_type: string;
  count: number;
  nodes: Array<{
    node_id: number;
    relationship: SourceReferenceRelationship;
    excerpt?: string | null;
    confidence?: "high" | "medium" | "low" | null;
    created_at: string;
  }>;
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

export type AgentRule = {
  id: number;
  project_id: number;
  agent_id: "coherence" | "continuous_research";
  rule_type: "mute_category" | "ignore_pattern" | "prioritize_category";
  value: string;
  inserted_at?: string;
  updated_at?: string;
};

export type Contradiction = {
  id: number;
  project_id: number;
  shared_scope_id?: number | null;
  mode: string;
  node_a: { type: string; id: number; scope?: string | null };
  node_b: { type: string; id: number; scope?: string | null };
  explanation: string | null;
  severity: "low" | "medium" | "high";
  severity_reason?: string | null;
  confidence?: number | null;
  context_diff?: Record<string, unknown> | null;
  suggested_resolutions?: unknown;
  status: string;
  status_reason?: string | null;
  resolved_at?: string | null;
  detected_at?: string | null;
  last_confirmed_at?: string | null;
  dismissed_count?: number | null;
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

// Board types
export type BoardNodePosition = { x: number; y: number };

export type BoardNodeReactions = {
  agree: string[];
  question: string[];
  flag: string[];
  star: string[];
};

export type BoardSession = {
  id: number;
  project_id: number;
  title: string;
  description?: string | null;
  status: string;
  created_by_user_id?: string | null;
  metadata: Record<string, unknown>;
  draft_node_count: number;
  promoted_node_count: number;
  total_node_count: number;
  node_types?: string[];
  active_agents?: string[];
  inserted_at?: string;
  updated_at?: string;
};

export type BoardSessionEvent = {
  id: number;
  event_type: string;
  actor_type: string;
  actor_name: string;
  target_type?: string;
  target_id?: number;
  target_title?: string;
  metadata?: Record<string, unknown>;
  inserted_at: string;
};

export type BoardNode = {
  id: number;
  board_session_id: number;
  project_id: number;
  node_type: string;
  title: string;
  body: string;
  status: string;
  promoted_node_type?: string | null;
  promoted_node_id?: number | null;
  created_by: string;
  metadata: {
    position?: BoardNodePosition;
    reactions?: BoardNodeReactions;
    source_id?: number;
    [key: string]: unknown;
  };
  inserted_at?: string;
  updated_at?: string;
};

export type BoardEdge = {
  id: number;
  board_session_id: number;
  from_board_node_id: number;
  to_board_node_id: number;
  kind: string;
  metadata: Record<string, unknown>;
  inserted_at?: string;
  updated_at?: string;
};

export type BoardPresenceUser = {
  user_id: string;
  name: string;
  color: string;
  cursor?: BoardNodePosition;
  joined_at: string;
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
  // Source-as-Data (Cycle 3): count of Library sources referenced by this node.
  source_reference_count?: number;
  // Present only for source / signal nodes.
  promoted_to_graph?: boolean | null;
  // Work-in-progress styling (Graph-Opt §10): draft / forming / proposed.
  wip?: boolean;
  wip_reason?: "board_draft" | "agent_proposed" | "agent_forming" | "user_draft" | null;
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
  meta?: {
    include_sources?: "promoted" | "all";
    total_source_references?: number;
  };
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

export type Simulation = {
  id: number;
  project_id: number;
  simulation_id: number | null;
  scenario_summary: string | null;
  archetype_summary: SimArchetype[] | null;
  status: string;
  results_imported: boolean;
  metadata: Record<string, unknown>;
  title?: string | null;
  population_size?: number;
  max_ticks?: number;
  comparison_mode?: boolean;
  inserted_at?: string;
  updated_at?: string;
};

export type SimArchetype = {
  source_insight_id?: number;
  title: string;
  description: string;
  traits: Record<string, string>;
};

export type SimGraphNode = {
  id: number;
  node_type: "decision" | "requirement" | "design_node";
  title: string;
  status: string;
  body: string;
};

export type SimEstimate = {
  estimated_cost_cents: number;
  estimated_duration_seconds: number;
  population_size: number;
  max_ticks: number;
  comparison_mode: boolean;
};

export type AgentTaskState =
  | "pending"
  | "running"
  | "paused"
  | "waiting_for_input"
  | "blocked"
  | "proposing"
  | "completed"
  | "rejected"
  | "cancelled"
  | "failed";

export type AgentTaskPriority = "low" | "normal" | "high" | "urgent";

export type AgentTask = {
  id: number;
  project_id: number;
  agent_id: string;
  title: string;
  description: string | null;
  state: AgentTaskState;
  state_reason: string | null;
  priority: AgentTaskPriority;
  progress_current: number | null;
  progress_total: number | null;
  progress_label: string | null;
  context_type: string | null;
  context_id: number | null;
  parent_task_id: number | null;
  assigned_by: "user" | "agent" | "system";
  assigned_by_user_id: number | null;
  assigned_by_agent_id: string | null;
  proposal_payload: Record<string, unknown> | null;
  result_payload: Record<string, unknown> | null;
  error_payload: Record<string, unknown> | null;
  started_at: string | null;
  completed_at: string | null;
  last_state_change_at: string;
  lock_version: number;
  inserted_at: string;
  updated_at: string;
};

export type StreamEntry = {
  id: number;
  project_id: number;
  tab: "activity" | "needs_you" | "blockers";
  source_task_id: number | null;
  source_agent_id: string | null;
  title: string;
  summary: string | null;
  context_type: string | null;
  context_id: number | null;
  read_at: string | null;
  actioned_at: string | null;
  inserted_at: string;
};

export type ProposalDecision = "accepted" | "rejected" | "deferred" | "edited";

export type ProposalItemDecision = {
  item_index: number;
  decision: ProposalDecision;
  edits?: Record<string, unknown> | null;
};

export type OnboardingState = "pending" | "in_progress" | "completed" | "skipped";

export type OnboardingStatus = {
  project_id: number;
  state: OnboardingState;
  vision_set: boolean;
  bets_count: number;
  hint: string | null;
  onboarded_at: string | null;
  onboarding_skipped_at: string | null;
};

export type StreamTab = "activity" | "needs_you" | "blockers";

export type StreamTabItem = {
  id: string;
  tab: StreamTab;
  kind:
    | "stream_entry"
    | "proposing"
    | "waiting_for_input"
    | "blocked"
    | "failed"
    | "stalled_flow"
    | "contradiction"
    | "burst";
  title: string;
  summary: string | null;
  actor_agent_id: string | null;
  age_seconds: number;
  source_task_id: number | null;
  stream_entry_id: number | null;
  flow_id: number | null;
  context_type: string | null;
  context_id: number | null;
  state: string | null;
  severity: number;
  inserted_at: string | null;
};

export type StreamTabCounts = {
  activity: number | null;
  needs_you: number;
  blockers: number;
  default_tab: StreamTab;
};

export type WhyLineageCard = {
  node_type: string;
  node_id: number | null;
  title: string;
  body: string;
  status: string | null;
  is_vision: boolean;
  is_target: boolean;
  edge_kind: string | null;
  stale?: boolean;
  updated_at?: string | null;
};

export type WhyContradictionRef = {
  id: number;
  severity: "low" | "medium" | "high";
  explanation: string | null;
  status: string;
  mode: string;
};

export type WhyPayload = {
  lineage: WhyLineageCard[];
  prose: string | null;
  vision_present: boolean;
  orphan: boolean;
  cached: boolean;
  error: string | null;
  contradictions?: WhyContradictionRef[];
};

export type Flow = {
  id: number;
  project_id: number;
  name: string;
  originating_task_id: number | null;
  status: "ongoing" | "complete" | "stalled" | "cancelled";
  participating_agent_ids: string[];
  task_ids: number[];
  completed_at: string | null;
  inserted_at: string;
  updated_at: string;
};

export type MentionIntent = "request_task" | "share_context" | "request_input" | "notify";

export type Mention = {
  id: number;
  project_id: number;
  source_type: string;
  source_task_id: number | null;
  source_agent_id: string | null;
  target_agent_id: string;
  target_task_id: number | null;
  intent: MentionIntent;
  content: string;
  metadata: { ambiguous_intent?: boolean; inferred?: MentionIntent } & Record<string, unknown>;
  inserted_at: string;
};
