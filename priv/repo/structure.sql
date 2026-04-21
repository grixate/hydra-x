--
-- PostgreSQL database dump
--

\restrict OzBhP96lIjyieCISIZlmVX5pJjuXMAB099Drd37J4gi5X2ktKAorhTEBWTeueC5

-- Dumped from database version 16.11 (Homebrew)
-- Dumped by pg_dump version 16.11 (Homebrew)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: vector; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA public;


--
-- Name: EXTENSION vector; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION vector IS 'vector data type and ivfflat and hnsw access methods';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: architecture_nodes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.architecture_nodes (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    title character varying(255) NOT NULL,
    body text NOT NULL,
    node_type character varying(255) NOT NULL,
    status character varying(255) DEFAULT 'active'::character varying NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    search_vector tsvector GENERATED ALWAYS AS ((setweight(to_tsvector('english'::regconfig, (COALESCE(title, ''::character varying))::text), 'A'::"char") || setweight(to_tsvector('english'::regconfig, COALESCE(body, ''::text)), 'B'::"char"))) STORED
);


--
-- Name: architecture_nodes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.architecture_nodes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: architecture_nodes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.architecture_nodes_id_seq OWNED BY public.architecture_nodes.id;


--
-- Name: artifact_versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.artifact_versions (
    id bigint NOT NULL,
    artifact_id bigint NOT NULL,
    version integer NOT NULL,
    body text NOT NULL,
    change_summary character varying(255),
    updated_by character varying(255) NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: artifact_versions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.artifact_versions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: artifact_versions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.artifact_versions_id_seq OWNED BY public.artifact_versions.id;


--
-- Name: artifacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.artifacts (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    title character varying(255) NOT NULL,
    artifact_type character varying(255) NOT NULL,
    body text NOT NULL,
    owner_persona character varying(255) NOT NULL,
    status character varying(255) DEFAULT 'active'::character varying NOT NULL,
    version integer DEFAULT 1 NOT NULL,
    last_updated_by character varying(255),
    metadata jsonb DEFAULT '{}'::jsonb,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: artifacts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.artifacts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: artifacts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.artifacts_id_seq OWNED BY public.artifacts.id;


--
-- Name: board_edges; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.board_edges (
    id bigint NOT NULL,
    board_session_id bigint NOT NULL,
    from_board_node_id bigint NOT NULL,
    to_board_node_id bigint NOT NULL,
    kind character varying(255) NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: board_edges_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.board_edges_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: board_edges_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.board_edges_id_seq OWNED BY public.board_edges.id;


--
-- Name: board_nodes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.board_nodes (
    id bigint NOT NULL,
    board_session_id bigint NOT NULL,
    project_id bigint NOT NULL,
    node_type character varying(255) NOT NULL,
    title character varying(255) NOT NULL,
    body text NOT NULL,
    status character varying(255) DEFAULT 'draft'::character varying NOT NULL,
    promoted_node_type character varying(255),
    promoted_node_id integer,
    created_by character varying(255) DEFAULT 'agent'::character varying NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: board_nodes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.board_nodes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: board_nodes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.board_nodes_id_seq OWNED BY public.board_nodes.id;


--
-- Name: board_session_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.board_session_events (
    id bigint NOT NULL,
    board_session_id integer NOT NULL,
    event_type character varying(255) NOT NULL,
    actor_type character varying(255) NOT NULL,
    actor_name character varying(255) NOT NULL,
    target_type character varying(255),
    target_id integer,
    target_title character varying(255),
    metadata jsonb DEFAULT '{}'::jsonb,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: board_session_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.board_session_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: board_session_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.board_session_events_id_seq OWNED BY public.board_session_events.id;


--
-- Name: board_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.board_sessions (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    title character varying(255) NOT NULL,
    description text,
    status character varying(255) DEFAULT 'active'::character varying NOT NULL,
    created_by_user_id character varying(255),
    metadata jsonb DEFAULT '{}'::jsonb,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: board_sessions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.board_sessions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: board_sessions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.board_sessions_id_seq OWNED BY public.board_sessions.id;


--
-- Name: constraints; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.constraints (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    title character varying(255) NOT NULL,
    body text NOT NULL,
    scope character varying(255) DEFAULT 'global'::character varying NOT NULL,
    enforcement character varying(255) DEFAULT 'strict'::character varying NOT NULL,
    status character varying(255) DEFAULT 'active'::character varying NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    search_vector tsvector GENERATED ALWAYS AS ((setweight(to_tsvector('english'::regconfig, (COALESCE(title, ''::character varying))::text), 'A'::"char") || setweight(to_tsvector('english'::regconfig, COALESCE(body, ''::text)), 'B'::"char"))) STORED
);


--
-- Name: constraints_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.constraints_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: constraints_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.constraints_id_seq OWNED BY public.constraints.id;


--
-- Name: decisions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.decisions (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    title character varying(255) NOT NULL,
    body text NOT NULL,
    status character varying(255) DEFAULT 'active'::character varying NOT NULL,
    decided_by character varying(255),
    decided_at timestamp(0) without time zone,
    alternatives_considered jsonb DEFAULT '[]'::jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    search_vector tsvector GENERATED ALWAYS AS ((setweight(to_tsvector('english'::regconfig, (COALESCE(title, ''::character varying))::text), 'A'::"char") || setweight(to_tsvector('english'::regconfig, COALESCE(body, ''::text)), 'B'::"char"))) STORED
);


--
-- Name: decisions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.decisions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: decisions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.decisions_id_seq OWNED BY public.decisions.id;


--
-- Name: design_nodes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.design_nodes (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    title character varying(255) NOT NULL,
    body text NOT NULL,
    node_type character varying(255) NOT NULL,
    status character varying(255) DEFAULT 'active'::character varying NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    search_vector tsvector GENERATED ALWAYS AS ((setweight(to_tsvector('english'::regconfig, (COALESCE(title, ''::character varying))::text), 'A'::"char") || setweight(to_tsvector('english'::regconfig, COALESCE(body, ''::text)), 'B'::"char"))) STORED
);


--
-- Name: design_nodes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.design_nodes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: design_nodes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.design_nodes_id_seq OWNED BY public.design_nodes.id;


--
-- Name: graph_flags; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.graph_flags (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    node_type character varying(255) NOT NULL,
    node_id integer NOT NULL,
    flag_type character varying(255) NOT NULL,
    reason text,
    source_agent character varying(255),
    status character varying(255) DEFAULT 'open'::character varying NOT NULL,
    resolved_by character varying(255),
    resolved_at timestamp(0) without time zone,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: graph_flags_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.graph_flags_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: graph_flags_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.graph_flags_id_seq OWNED BY public.graph_flags.id;


--
-- Name: hx_agent_mcp_servers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hx_agent_mcp_servers (
    id bigint NOT NULL,
    agent_id bigint NOT NULL,
    mcp_server_config_id bigint NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: hx_agent_mcp_servers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hx_agent_mcp_servers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hx_agent_mcp_servers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hx_agent_mcp_servers_id_seq OWNED BY public.hx_agent_mcp_servers.id;


--
-- Name: hx_agent_profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hx_agent_profiles (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    slug character varying(255) NOT NULL,
    status character varying(255) DEFAULT 'active'::character varying NOT NULL,
    workspace_root character varying(255) NOT NULL,
    description text,
    is_default boolean DEFAULT false NOT NULL,
    last_started_at timestamp without time zone,
    runtime_state jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    role character varying(255) DEFAULT 'operator'::character varying NOT NULL,
    capability_profile jsonb DEFAULT '{}'::jsonb NOT NULL
);


--
-- Name: hx_agent_profiles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hx_agent_profiles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hx_agent_profiles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hx_agent_profiles_id_seq OWNED BY public.hx_agent_profiles.id;


--
-- Name: hx_approval_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hx_approval_records (
    id bigint NOT NULL,
    subject_type character varying(255) NOT NULL,
    subject_id integer NOT NULL,
    requested_action character varying(255) NOT NULL,
    decision character varying(255) NOT NULL,
    rationale text,
    promoted_at timestamp without time zone,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    work_item_id bigint,
    reviewer_agent_id bigint,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: hx_approval_records_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hx_approval_records_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hx_approval_records_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hx_approval_records_id_seq OWNED BY public.hx_approval_records.id;


--
-- Name: hx_artifacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hx_artifacts (
    id bigint NOT NULL,
    type character varying(255) NOT NULL,
    title character varying(255) NOT NULL,
    summary text,
    body text,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    version integer DEFAULT 1 NOT NULL,
    provenance jsonb DEFAULT '{}'::jsonb NOT NULL,
    confidence double precision,
    review_status character varying(255) DEFAULT 'draft'::character varying NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    work_item_id bigint NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: hx_artifacts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hx_artifacts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hx_artifacts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hx_artifacts_id_seq OWNED BY public.hx_artifacts.id;


--
-- Name: hx_budget_policies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hx_budget_policies (
    id bigint NOT NULL,
    agent_id bigint NOT NULL,
    daily_limit integer DEFAULT 20000 NOT NULL,
    conversation_limit integer DEFAULT 4000 NOT NULL,
    soft_warning_at double precision DEFAULT 0.8 NOT NULL,
    hard_limit_action character varying(255) DEFAULT 'reject'::character varying NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: hx_budget_policies_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hx_budget_policies_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hx_budget_policies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hx_budget_policies_id_seq OWNED BY public.hx_budget_policies.id;


--
-- Name: hx_budget_usages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hx_budget_usages (
    id bigint NOT NULL,
    agent_id bigint NOT NULL,
    conversation_id bigint,
    scope character varying(255) NOT NULL,
    tokens_in integer DEFAULT 0 NOT NULL,
    tokens_out integer DEFAULT 0 NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: hx_budget_usages_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hx_budget_usages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hx_budget_usages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hx_budget_usages_id_seq OWNED BY public.hx_budget_usages.id;


--
-- Name: hx_checkpoints; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hx_checkpoints (
    id bigint NOT NULL,
    conversation_id bigint NOT NULL,
    process_type character varying(255) NOT NULL,
    state jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: hx_checkpoints_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hx_checkpoints_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hx_checkpoints_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hx_checkpoints_id_seq OWNED BY public.hx_checkpoints.id;


--
-- Name: hx_control_policies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hx_control_policies (
    id bigint NOT NULL,
    scope character varying(255) DEFAULT 'default'::character varying NOT NULL,
    require_recent_auth_for_sensitive_actions boolean DEFAULT true NOT NULL,
    recent_auth_window_minutes integer DEFAULT 15 NOT NULL,
    interactive_delivery_channels_csv character varying(255) DEFAULT 'telegram,discord,slack,webchat'::character varying NOT NULL,
    job_delivery_channels_csv character varying(255) DEFAULT 'telegram,discord,slack,webchat'::character varying NOT NULL,
    ingest_roots_csv character varying(255) DEFAULT 'ingest'::character varying NOT NULL,
    agent_id bigint,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: hx_control_policies_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hx_control_policies_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hx_control_policies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hx_control_policies_id_seq OWNED BY public.hx_control_policies.id;


--
-- Name: hx_conversation_branches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hx_conversation_branches (
    id bigint NOT NULL,
    conversation_id bigint NOT NULL,
    branch_uuid uuid NOT NULL,
    label character varying(255) DEFAULT 'main'::character varying NOT NULL,
    parent_branch_id bigint,
    forked_from_sequence integer,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: hx_conversation_branches_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hx_conversation_branches_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hx_conversation_branches_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hx_conversation_branches_id_seq OWNED BY public.hx_conversation_branches.id;


--
-- Name: hx_conversations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hx_conversations (
    id bigint NOT NULL,
    agent_id bigint NOT NULL,
    channel character varying(255) NOT NULL,
    external_ref character varying(255),
    status character varying(255) DEFAULT 'active'::character varying NOT NULL,
    title character varying(255),
    last_message_at timestamp without time zone,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    active_branch_id uuid
);


--
-- Name: hx_conversations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hx_conversations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hx_conversations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hx_conversations_id_seq OWNED BY public.hx_conversations.id;


--
-- Name: hx_coordination_leases; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hx_coordination_leases (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    owner character varying(255) NOT NULL,
    owner_node character varying(255) NOT NULL,
    lease_type character varying(255) DEFAULT 'exclusive'::character varying NOT NULL,
    expires_at timestamp without time zone NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: hx_coordination_leases_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hx_coordination_leases_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hx_coordination_leases_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hx_coordination_leases_id_seq OWNED BY public.hx_coordination_leases.id;


--
-- Name: hx_discord_configs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hx_discord_configs (
    id bigint NOT NULL,
    bot_token character varying(255) NOT NULL,
    application_id character varying(255),
    webhook_secret character varying(255),
    enabled boolean DEFAULT false NOT NULL,
    default_agent_id bigint,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: hx_discord_configs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hx_discord_configs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hx_discord_configs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hx_discord_configs_id_seq OWNED BY public.hx_discord_configs.id;


--
-- Name: hx_ingest_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hx_ingest_runs (
    id bigint NOT NULL,
    agent_id bigint NOT NULL,
    source_file character varying(255) NOT NULL,
    source_path text,
    status character varying(255) NOT NULL,
    chunk_count integer DEFAULT 0 NOT NULL,
    created_count integer DEFAULT 0 NOT NULL,
    skipped_count integer DEFAULT 0 NOT NULL,
    archived_count integer DEFAULT 0 NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: hx_ingest_runs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hx_ingest_runs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hx_ingest_runs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hx_ingest_runs_id_seq OWNED BY public.hx_ingest_runs.id;


--
-- Name: hx_job_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hx_job_runs (
    id bigint NOT NULL,
    scheduled_job_id bigint NOT NULL,
    agent_id bigint NOT NULL,
    status character varying(255) NOT NULL,
    started_at timestamp without time zone NOT NULL,
    finished_at timestamp without time zone,
    output text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: hx_job_runs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hx_job_runs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hx_job_runs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hx_job_runs_id_seq OWNED BY public.hx_job_runs.id;


--
-- Name: hx_mcp_server_configs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hx_mcp_server_configs (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    transport character varying(255) NOT NULL,
    command character varying(255),
    args_csv character varying(255),
    cwd character varying(255),
    url character varying(255),
    healthcheck_path character varying(255) DEFAULT '/health'::character varying,
    auth_token text,
    enabled boolean DEFAULT true NOT NULL,
    retry_limit integer DEFAULT 2 NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: hx_mcp_server_configs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hx_mcp_server_configs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hx_mcp_server_configs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hx_mcp_server_configs_id_seq OWNED BY public.hx_mcp_server_configs.id;


--
-- Name: hx_memory_edges; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hx_memory_edges (
    id bigint NOT NULL,
    from_memory_id bigint NOT NULL,
    to_memory_id bigint NOT NULL,
    kind character varying(255) NOT NULL,
    weight double precision DEFAULT 1.0 NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: hx_memory_edges_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hx_memory_edges_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hx_memory_edges_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hx_memory_edges_id_seq OWNED BY public.hx_memory_edges.id;


--
-- Name: hx_memory_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hx_memory_entries (
    id bigint NOT NULL,
    agent_id bigint NOT NULL,
    conversation_id bigint,
    type character varying(255) NOT NULL,
    content text NOT NULL,
    importance double precision DEFAULT 0.5 NOT NULL,
    embedding public.vector(768),
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    last_seen_at timestamp without time zone,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    search_vector tsvector GENERATED ALWAYS AS ((setweight(to_tsvector('english'::regconfig, COALESCE(content, ''::text)), 'A'::"char") || setweight(to_tsvector('english'::regconfig, (COALESCE(type, ''::character varying))::text), 'B'::"char"))) STORED,
    status character varying(255) DEFAULT 'active'::character varying NOT NULL
);


--
-- Name: hx_memory_entries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hx_memory_entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hx_memory_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hx_memory_entries_id_seq OWNED BY public.hx_memory_entries.id;


--
-- Name: hx_operator_secrets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hx_operator_secrets (
    id bigint NOT NULL,
    scope character varying(255) DEFAULT 'control_plane'::character varying NOT NULL,
    password_hash text NOT NULL,
    password_salt text NOT NULL,
    last_rotated_at timestamp without time zone,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: hx_operator_secrets_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hx_operator_secrets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hx_operator_secrets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hx_operator_secrets_id_seq OWNED BY public.hx_operator_secrets.id;


--
-- Name: hx_product_workspaces; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hx_product_workspaces (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    fs_path text NOT NULL,
    sandbox_mode character varying(255) DEFAULT 'host'::character varying NOT NULL,
    container_id character varying(255),
    status character varying(255) DEFAULT 'provisioning'::character varying NOT NULL,
    git_origin text,
    last_used_at timestamp without time zone,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: hx_product_workspaces_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hx_product_workspaces_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hx_product_workspaces_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hx_product_workspaces_id_seq OWNED BY public.hx_product_workspaces.id;


--
-- Name: hx_provider_configs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hx_provider_configs (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    kind character varying(255) NOT NULL,
    base_url character varying(255),
    api_key text,
    model character varying(255) NOT NULL,
    enabled boolean DEFAULT false NOT NULL,
    config jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: hx_provider_configs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hx_provider_configs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hx_provider_configs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hx_provider_configs_id_seq OWNED BY public.hx_provider_configs.id;


--
-- Name: hx_safety_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hx_safety_events (
    id bigint NOT NULL,
    agent_id bigint NOT NULL,
    conversation_id bigint,
    category character varying(255) NOT NULL,
    level character varying(255) NOT NULL,
    message text NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    status character varying(255) DEFAULT 'open'::character varying NOT NULL,
    acknowledged_at timestamp without time zone,
    acknowledged_by character varying(255),
    resolved_at timestamp without time zone,
    resolved_by character varying(255),
    operator_note text
);


--
-- Name: hx_safety_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hx_safety_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hx_safety_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hx_safety_events_id_seq OWNED BY public.hx_safety_events.id;


--
-- Name: hx_scheduled_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hx_scheduled_jobs (
    id bigint NOT NULL,
    agent_id bigint NOT NULL,
    name character varying(255) NOT NULL,
    kind character varying(255) NOT NULL,
    prompt text,
    interval_minutes integer DEFAULT 60 NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    next_run_at timestamp without time zone,
    last_run_at timestamp without time zone,
    config jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    delivery_enabled boolean DEFAULT false NOT NULL,
    delivery_channel text,
    delivery_target text,
    schedule_mode character varying(255) DEFAULT 'interval'::character varying NOT NULL,
    weekday_csv character varying(255),
    run_hour integer,
    run_minute integer,
    cron_expression character varying(255),
    active_hour_start integer,
    active_hour_end integer,
    timeout_seconds integer DEFAULT 120 NOT NULL,
    retry_limit integer DEFAULT 0 NOT NULL,
    retry_backoff_seconds integer DEFAULT 0 NOT NULL,
    pause_after_failures integer DEFAULT 0 NOT NULL,
    cooldown_minutes integer DEFAULT 0 NOT NULL,
    consecutive_failures integer DEFAULT 0 NOT NULL,
    circuit_state character varying(255) DEFAULT 'closed'::character varying NOT NULL,
    circuit_opened_at timestamp without time zone,
    paused_until timestamp without time zone,
    last_failure_at timestamp without time zone,
    last_failure_reason text,
    run_retention_days integer DEFAULT 30 NOT NULL
);


--
-- Name: hx_scheduled_jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hx_scheduled_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hx_scheduled_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hx_scheduled_jobs_id_seq OWNED BY public.hx_scheduled_jobs.id;


--
-- Name: hx_skill_installs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hx_skill_installs (
    id bigint NOT NULL,
    agent_id bigint NOT NULL,
    slug character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    path character varying(255) NOT NULL,
    description text,
    source character varying(255) DEFAULT 'workspace'::character varying NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: hx_skill_installs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hx_skill_installs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hx_skill_installs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hx_skill_installs_id_seq OWNED BY public.hx_skill_installs.id;


--
-- Name: hx_slack_configs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hx_slack_configs (
    id bigint NOT NULL,
    bot_token character varying(255) NOT NULL,
    signing_secret character varying(255),
    enabled boolean DEFAULT false NOT NULL,
    default_agent_id bigint,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: hx_slack_configs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hx_slack_configs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hx_slack_configs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hx_slack_configs_id_seq OWNED BY public.hx_slack_configs.id;


--
-- Name: hx_telegram_configs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hx_telegram_configs (
    id bigint NOT NULL,
    bot_token text NOT NULL,
    bot_username character varying(255),
    webhook_secret character varying(255),
    enabled boolean DEFAULT false NOT NULL,
    default_agent_id bigint,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    webhook_url character varying(255),
    webhook_registered_at timestamp without time zone,
    webhook_last_checked_at timestamp without time zone,
    webhook_pending_update_count integer DEFAULT 0 NOT NULL,
    webhook_last_error text
);


--
-- Name: hx_telegram_configs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hx_telegram_configs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hx_telegram_configs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hx_telegram_configs_id_seq OWNED BY public.hx_telegram_configs.id;


--
-- Name: hx_tool_policies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hx_tool_policies (
    id bigint NOT NULL,
    scope character varying(255) NOT NULL,
    workspace_read_enabled boolean DEFAULT true NOT NULL,
    http_fetch_enabled boolean DEFAULT true NOT NULL,
    shell_command_enabled boolean DEFAULT true NOT NULL,
    shell_allowlist_csv text DEFAULT ''::text NOT NULL,
    http_allowlist_csv text DEFAULT ''::text NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    agent_id bigint,
    workspace_list_enabled boolean DEFAULT true NOT NULL,
    workspace_write_enabled boolean DEFAULT false NOT NULL,
    web_search_enabled boolean DEFAULT true NOT NULL,
    workspace_write_channels_csv text DEFAULT ''::text NOT NULL,
    http_fetch_channels_csv text DEFAULT ''::text NOT NULL,
    web_search_channels_csv text DEFAULT ''::text NOT NULL,
    shell_command_channels_csv text DEFAULT ''::text NOT NULL,
    browser_automation_enabled boolean DEFAULT false NOT NULL,
    browser_automation_channels_csv character varying(255) DEFAULT ''::character varying NOT NULL
);


--
-- Name: hx_tool_policies_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hx_tool_policies_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hx_tool_policies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hx_tool_policies_id_seq OWNED BY public.hx_tool_policies.id;


--
-- Name: hx_turns; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hx_turns (
    id bigint NOT NULL,
    conversation_id bigint NOT NULL,
    sequence integer NOT NULL,
    role character varying(255) NOT NULL,
    kind character varying(255) DEFAULT 'message'::character varying NOT NULL,
    content text NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    branch_id uuid NOT NULL
);


--
-- Name: hx_turns_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hx_turns_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hx_turns_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hx_turns_id_seq OWNED BY public.hx_turns.id;


--
-- Name: hx_webchat_configs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hx_webchat_configs (
    id bigint NOT NULL,
    title character varying(255),
    subtitle text,
    welcome_prompt text,
    composer_placeholder character varying(255),
    enabled boolean DEFAULT false NOT NULL,
    default_agent_id bigint,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    allow_anonymous_messages boolean DEFAULT true NOT NULL,
    session_max_age_minutes integer DEFAULT 1440 NOT NULL,
    session_idle_timeout_minutes integer DEFAULT 120 NOT NULL,
    attachments_enabled boolean DEFAULT true NOT NULL,
    max_attachment_count integer DEFAULT 3 NOT NULL,
    max_attachment_size_kb integer DEFAULT 2048 NOT NULL
);


--
-- Name: hx_webchat_configs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hx_webchat_configs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hx_webchat_configs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hx_webchat_configs_id_seq OWNED BY public.hx_webchat_configs.id;


--
-- Name: hx_work_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hx_work_items (
    id bigint NOT NULL,
    kind character varying(255) DEFAULT 'task'::character varying NOT NULL,
    goal text NOT NULL,
    status character varying(255) DEFAULT 'planned'::character varying NOT NULL,
    execution_mode character varying(255) DEFAULT 'execute'::character varying NOT NULL,
    assigned_role character varying(255) DEFAULT 'operator'::character varying NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    autonomy_level character varying(255) DEFAULT 'recommend'::character varying NOT NULL,
    review_required boolean DEFAULT true NOT NULL,
    approval_stage character varying(255) DEFAULT 'draft'::character varying NOT NULL,
    deadline_at timestamp without time zone,
    budget jsonb DEFAULT '{}'::jsonb NOT NULL,
    input_artifact_refs jsonb DEFAULT '{}'::jsonb NOT NULL,
    required_outputs jsonb DEFAULT '{}'::jsonb NOT NULL,
    deliverables jsonb DEFAULT '{}'::jsonb NOT NULL,
    result_refs jsonb DEFAULT '{}'::jsonb NOT NULL,
    runtime_state jsonb DEFAULT '{}'::jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    assigned_agent_id bigint,
    delegated_by_agent_id bigint,
    parent_work_item_id bigint,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: hx_work_items_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hx_work_items_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hx_work_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hx_work_items_id_seq OWNED BY public.hx_work_items.id;


--
-- Name: hx_workspace_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hx_workspace_events (
    id bigint NOT NULL,
    workspace_id bigint NOT NULL,
    project_id bigint NOT NULL,
    kind character varying(255) NOT NULL,
    path text,
    command jsonb,
    exit_code integer,
    outcome character varying(255) NOT NULL,
    error text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: hx_workspace_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hx_workspace_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hx_workspace_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hx_workspace_events_id_seq OWNED BY public.hx_workspace_events.id;


--
-- Name: insight_evidence; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.insight_evidence (
    id bigint NOT NULL,
    insight_id bigint NOT NULL,
    source_chunk_id bigint NOT NULL,
    quote text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: insight_evidence_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.insight_evidence_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: insight_evidence_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.insight_evidence_id_seq OWNED BY public.insight_evidence.id;


--
-- Name: insights; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.insights (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    title character varying(255) NOT NULL,
    body text NOT NULL,
    status character varying(255) DEFAULT 'draft'::character varying NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: insights_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.insights_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: insights_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.insights_id_seq OWNED BY public.insights.id;


--
-- Name: knowledge_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.knowledge_entries (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    title character varying(255) NOT NULL,
    content text NOT NULL,
    entry_type character varying(255) DEFAULT 'custom'::character varying NOT NULL,
    assigned_personas character varying(255)[] DEFAULT ARRAY[]::character varying[] NOT NULL,
    source_type character varying(255) DEFAULT 'manual'::character varying NOT NULL,
    source_url character varying(255),
    status character varying(255) DEFAULT 'active'::character varying NOT NULL,
    embedding public.vector(768),
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: knowledge_entries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.knowledge_entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: knowledge_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.knowledge_entries_id_seq OWNED BY public.knowledge_entries.id;


--
-- Name: learnings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.learnings (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    title character varying(255) NOT NULL,
    body text NOT NULL,
    learning_type character varying(255) NOT NULL,
    status character varying(255) DEFAULT 'active'::character varying NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    search_vector tsvector GENERATED ALWAYS AS ((setweight(to_tsvector('english'::regconfig, (COALESCE(title, ''::character varying))::text), 'A'::"char") || setweight(to_tsvector('english'::regconfig, COALESCE(body, ''::text)), 'B'::"char"))) STORED
);


--
-- Name: learnings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.learnings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: learnings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.learnings_id_seq OWNED BY public.learnings.id;


--
-- Name: product_conversations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.product_conversations (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    hydra_conversation_id bigint NOT NULL,
    persona character varying(255) NOT NULL,
    title character varying(255),
    status character varying(255) DEFAULT 'active'::character varying NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    board_session_id bigint
);


--
-- Name: product_conversations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.product_conversations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: product_conversations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.product_conversations_id_seq OWNED BY public.product_conversations.id;


--
-- Name: product_graph_edges; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.product_graph_edges (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    from_node_type character varying(255) NOT NULL,
    from_node_id integer NOT NULL,
    to_node_type character varying(255) NOT NULL,
    to_node_id integer NOT NULL,
    kind character varying(255) NOT NULL,
    weight double precision DEFAULT 1.0 NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: product_graph_edges_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.product_graph_edges_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: product_graph_edges_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.product_graph_edges_id_seq OWNED BY public.product_graph_edges.id;


--
-- Name: product_messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.product_messages (
    id bigint NOT NULL,
    product_conversation_id bigint NOT NULL,
    hydra_turn_id bigint,
    role character varying(255) NOT NULL,
    content text NOT NULL,
    citations jsonb[] DEFAULT ARRAY[]::jsonb[] NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: product_messages_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.product_messages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: product_messages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.product_messages_id_seq OWNED BY public.product_messages.id;


--
-- Name: product_simulations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.product_simulations (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    simulation_id bigint,
    scenario_summary text,
    archetype_summary jsonb DEFAULT '[]'::jsonb,
    status character varying(255) DEFAULT 'configuring'::character varying NOT NULL,
    results_imported boolean DEFAULT false NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: product_simulations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.product_simulations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: product_simulations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.product_simulations_id_seq OWNED BY public.product_simulations.id;


--
-- Name: projects; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.projects (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    slug character varying(255) NOT NULL,
    description text,
    status character varying(255) DEFAULT 'active'::character varying NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    researcher_agent_id bigint NOT NULL,
    strategist_agent_id bigint NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    architect_agent_id bigint,
    designer_agent_id bigint,
    memory_agent_id bigint,
    trust_level character varying(255) DEFAULT 'standard'::character varying NOT NULL,
    coder_agent_id bigint
);


--
-- Name: projects_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.projects_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: projects_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.projects_id_seq OWNED BY public.projects.id;


--
-- Name: requirement_insights; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.requirement_insights (
    id bigint NOT NULL,
    requirement_id bigint NOT NULL,
    insight_id bigint NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: requirement_insights_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.requirement_insights_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: requirement_insights_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.requirement_insights_id_seq OWNED BY public.requirement_insights.id;


--
-- Name: requirements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.requirements (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    title character varying(255) NOT NULL,
    body text NOT NULL,
    status character varying(255) DEFAULT 'draft'::character varying NOT NULL,
    grounded boolean DEFAULT false NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: requirements_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.requirements_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: requirements_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.requirements_id_seq OWNED BY public.requirements.id;


--
-- Name: routine_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.routine_runs (
    id bigint NOT NULL,
    routine_id bigint NOT NULL,
    started_at timestamp(0) without time zone NOT NULL,
    completed_at timestamp(0) without time zone,
    status character varying(255) DEFAULT 'running'::character varying NOT NULL,
    prompt_resolved text,
    output text,
    token_count integer,
    cost_cents integer,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: routine_runs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.routine_runs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: routine_runs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.routine_runs_id_seq OWNED BY public.routine_runs.id;


--
-- Name: routines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.routines (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    title character varying(255) NOT NULL,
    description text,
    prompt_template text NOT NULL,
    assigned_persona character varying(255) NOT NULL,
    schedule_type character varying(255) DEFAULT 'cron'::character varying NOT NULL,
    cron_expression character varying(255),
    event_trigger character varying(255),
    timezone character varying(255) DEFAULT 'UTC'::character varying NOT NULL,
    output_target character varying(255) DEFAULT 'stream_item'::character varying NOT NULL,
    status character varying(255) DEFAULT 'active'::character varying NOT NULL,
    last_run_at timestamp(0) without time zone,
    last_run_status character varying(255),
    last_run_tokens integer,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: routines_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.routines_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: routines_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.routines_id_seq OWNED BY public.routines.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version bigint NOT NULL,
    inserted_at timestamp(0) without time zone
);


--
-- Name: sim_agent_profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sim_agent_profiles (
    id bigint NOT NULL,
    simulation_id bigint NOT NULL,
    agent_key character varying(255) NOT NULL,
    persona jsonb NOT NULL,
    initial_beliefs jsonb DEFAULT '{}'::jsonb,
    initial_relationships jsonb DEFAULT '{}'::jsonb,
    final_state jsonb,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: sim_agent_profiles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sim_agent_profiles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sim_agent_profiles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sim_agent_profiles_id_seq OWNED BY public.sim_agent_profiles.id;


--
-- Name: sim_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sim_events (
    id bigint NOT NULL,
    simulation_id bigint NOT NULL,
    tick integer NOT NULL,
    event_type character varying(255) NOT NULL,
    source character varying(255),
    target character varying(255),
    description text,
    properties jsonb DEFAULT '{}'::jsonb,
    stakes double precision,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: sim_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sim_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sim_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sim_events_id_seq OWNED BY public.sim_events.id;


--
-- Name: sim_reports; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sim_reports (
    id bigint NOT NULL,
    simulation_id bigint NOT NULL,
    content text NOT NULL,
    statistical_summary jsonb,
    generated_at timestamp(0) without time zone,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: sim_reports_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sim_reports_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sim_reports_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sim_reports_id_seq OWNED BY public.sim_reports.id;


--
-- Name: sim_ticks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sim_ticks (
    id bigint NOT NULL,
    simulation_id bigint NOT NULL,
    tick_number integer NOT NULL,
    duration_us integer,
    tier_counts jsonb,
    llm_calls integer,
    tokens_used integer,
    world_delta jsonb,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: sim_ticks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sim_ticks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sim_ticks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sim_ticks_id_seq OWNED BY public.sim_ticks.id;


--
-- Name: simulations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.simulations (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    status character varying(255) DEFAULT 'configuring'::character varying,
    config jsonb NOT NULL,
    seed_material text,
    world_snapshot jsonb,
    total_ticks integer DEFAULT 0,
    total_llm_calls integer DEFAULT 0,
    total_tokens_used integer DEFAULT 0,
    total_cost_cents integer DEFAULT 0,
    started_at timestamp(0) without time zone,
    completed_at timestamp(0) without time zone,
    agent_id bigint,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: simulations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.simulations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: simulations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.simulations_id_seq OWNED BY public.simulations.id;


--
-- Name: source_chunks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.source_chunks (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    source_id bigint NOT NULL,
    ordinal integer NOT NULL,
    content text NOT NULL,
    token_count integer,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    embedding public.vector(768),
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    search_vector tsvector GENERATED ALWAYS AS (setweight(to_tsvector('english'::regconfig, COALESCE(content, ''::text)), 'A'::"char")) STORED
);


--
-- Name: source_chunks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.source_chunks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: source_chunks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.source_chunks_id_seq OWNED BY public.source_chunks.id;


--
-- Name: sources; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sources (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    title character varying(255) NOT NULL,
    source_type character varying(255) NOT NULL,
    content text,
    external_ref character varying(255),
    processing_status character varying(255) DEFAULT 'pending'::character varying NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: sources_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sources_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sources_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sources_id_seq OWNED BY public.sources.id;


--
-- Name: strategies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.strategies (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    title character varying(255) NOT NULL,
    body text NOT NULL,
    status character varying(255) DEFAULT 'active'::character varying NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    search_vector tsvector GENERATED ALWAYS AS ((setweight(to_tsvector('english'::regconfig, (COALESCE(title, ''::character varying))::text), 'A'::"char") || setweight(to_tsvector('english'::regconfig, COALESCE(body, ''::text)), 'B'::"char"))) STORED
);


--
-- Name: strategies_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.strategies_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: strategies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.strategies_id_seq OWNED BY public.strategies.id;


--
-- Name: task_feedback; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.task_feedback (
    id bigint NOT NULL,
    task_id bigint NOT NULL,
    rating character varying(255) NOT NULL,
    comment text,
    feedback_tags character varying(255)[] DEFAULT ARRAY[]::character varying[] NOT NULL,
    created_by character varying(255) DEFAULT 'human'::character varying NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: task_feedback_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.task_feedback_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: task_feedback_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.task_feedback_id_seq OWNED BY public.task_feedback.id;


--
-- Name: tasks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tasks (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    title character varying(255) NOT NULL,
    body text NOT NULL,
    status character varying(255) DEFAULT 'backlog'::character varying NOT NULL,
    assignee character varying(255),
    effort_estimate character varying(255),
    priority character varying(255) DEFAULT 'medium'::character varying NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    search_vector tsvector GENERATED ALWAYS AS ((setweight(to_tsvector('english'::regconfig, (COALESCE(title, ''::character varying))::text), 'A'::"char") || setweight(to_tsvector('english'::regconfig, COALESCE(body, ''::text)), 'B'::"char"))) STORED
);


--
-- Name: tasks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tasks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tasks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tasks_id_seq OWNED BY public.tasks.id;


--
-- Name: watch_targets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.watch_targets (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    target_type character varying(255) NOT NULL,
    value character varying(255) NOT NULL,
    check_interval_hours integer DEFAULT 24 NOT NULL,
    last_checked_at timestamp(0) without time zone,
    status character varying(255) DEFAULT 'active'::character varying NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: watch_targets_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.watch_targets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: watch_targets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.watch_targets_id_seq OWNED BY public.watch_targets.id;


--
-- Name: architecture_nodes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.architecture_nodes ALTER COLUMN id SET DEFAULT nextval('public.architecture_nodes_id_seq'::regclass);


--
-- Name: artifact_versions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.artifact_versions ALTER COLUMN id SET DEFAULT nextval('public.artifact_versions_id_seq'::regclass);


--
-- Name: artifacts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.artifacts ALTER COLUMN id SET DEFAULT nextval('public.artifacts_id_seq'::regclass);


--
-- Name: board_edges id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.board_edges ALTER COLUMN id SET DEFAULT nextval('public.board_edges_id_seq'::regclass);


--
-- Name: board_nodes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.board_nodes ALTER COLUMN id SET DEFAULT nextval('public.board_nodes_id_seq'::regclass);


--
-- Name: board_session_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.board_session_events ALTER COLUMN id SET DEFAULT nextval('public.board_session_events_id_seq'::regclass);


--
-- Name: board_sessions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.board_sessions ALTER COLUMN id SET DEFAULT nextval('public.board_sessions_id_seq'::regclass);


--
-- Name: constraints id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.constraints ALTER COLUMN id SET DEFAULT nextval('public.constraints_id_seq'::regclass);


--
-- Name: decisions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.decisions ALTER COLUMN id SET DEFAULT nextval('public.decisions_id_seq'::regclass);


--
-- Name: design_nodes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.design_nodes ALTER COLUMN id SET DEFAULT nextval('public.design_nodes_id_seq'::regclass);


--
-- Name: graph_flags id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.graph_flags ALTER COLUMN id SET DEFAULT nextval('public.graph_flags_id_seq'::regclass);


--
-- Name: hx_agent_mcp_servers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_agent_mcp_servers ALTER COLUMN id SET DEFAULT nextval('public.hx_agent_mcp_servers_id_seq'::regclass);


--
-- Name: hx_agent_profiles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_agent_profiles ALTER COLUMN id SET DEFAULT nextval('public.hx_agent_profiles_id_seq'::regclass);


--
-- Name: hx_approval_records id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_approval_records ALTER COLUMN id SET DEFAULT nextval('public.hx_approval_records_id_seq'::regclass);


--
-- Name: hx_artifacts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_artifacts ALTER COLUMN id SET DEFAULT nextval('public.hx_artifacts_id_seq'::regclass);


--
-- Name: hx_budget_policies id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_budget_policies ALTER COLUMN id SET DEFAULT nextval('public.hx_budget_policies_id_seq'::regclass);


--
-- Name: hx_budget_usages id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_budget_usages ALTER COLUMN id SET DEFAULT nextval('public.hx_budget_usages_id_seq'::regclass);


--
-- Name: hx_checkpoints id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_checkpoints ALTER COLUMN id SET DEFAULT nextval('public.hx_checkpoints_id_seq'::regclass);


--
-- Name: hx_control_policies id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_control_policies ALTER COLUMN id SET DEFAULT nextval('public.hx_control_policies_id_seq'::regclass);


--
-- Name: hx_conversation_branches id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_conversation_branches ALTER COLUMN id SET DEFAULT nextval('public.hx_conversation_branches_id_seq'::regclass);


--
-- Name: hx_conversations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_conversations ALTER COLUMN id SET DEFAULT nextval('public.hx_conversations_id_seq'::regclass);


--
-- Name: hx_coordination_leases id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_coordination_leases ALTER COLUMN id SET DEFAULT nextval('public.hx_coordination_leases_id_seq'::regclass);


--
-- Name: hx_discord_configs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_discord_configs ALTER COLUMN id SET DEFAULT nextval('public.hx_discord_configs_id_seq'::regclass);


--
-- Name: hx_ingest_runs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_ingest_runs ALTER COLUMN id SET DEFAULT nextval('public.hx_ingest_runs_id_seq'::regclass);


--
-- Name: hx_job_runs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_job_runs ALTER COLUMN id SET DEFAULT nextval('public.hx_job_runs_id_seq'::regclass);


--
-- Name: hx_mcp_server_configs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_mcp_server_configs ALTER COLUMN id SET DEFAULT nextval('public.hx_mcp_server_configs_id_seq'::regclass);


--
-- Name: hx_memory_edges id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_memory_edges ALTER COLUMN id SET DEFAULT nextval('public.hx_memory_edges_id_seq'::regclass);


--
-- Name: hx_memory_entries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_memory_entries ALTER COLUMN id SET DEFAULT nextval('public.hx_memory_entries_id_seq'::regclass);


--
-- Name: hx_operator_secrets id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_operator_secrets ALTER COLUMN id SET DEFAULT nextval('public.hx_operator_secrets_id_seq'::regclass);


--
-- Name: hx_product_workspaces id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_product_workspaces ALTER COLUMN id SET DEFAULT nextval('public.hx_product_workspaces_id_seq'::regclass);


--
-- Name: hx_provider_configs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_provider_configs ALTER COLUMN id SET DEFAULT nextval('public.hx_provider_configs_id_seq'::regclass);


--
-- Name: hx_safety_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_safety_events ALTER COLUMN id SET DEFAULT nextval('public.hx_safety_events_id_seq'::regclass);


--
-- Name: hx_scheduled_jobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_scheduled_jobs ALTER COLUMN id SET DEFAULT nextval('public.hx_scheduled_jobs_id_seq'::regclass);


--
-- Name: hx_skill_installs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_skill_installs ALTER COLUMN id SET DEFAULT nextval('public.hx_skill_installs_id_seq'::regclass);


--
-- Name: hx_slack_configs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_slack_configs ALTER COLUMN id SET DEFAULT nextval('public.hx_slack_configs_id_seq'::regclass);


--
-- Name: hx_telegram_configs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_telegram_configs ALTER COLUMN id SET DEFAULT nextval('public.hx_telegram_configs_id_seq'::regclass);


--
-- Name: hx_tool_policies id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_tool_policies ALTER COLUMN id SET DEFAULT nextval('public.hx_tool_policies_id_seq'::regclass);


--
-- Name: hx_turns id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_turns ALTER COLUMN id SET DEFAULT nextval('public.hx_turns_id_seq'::regclass);


--
-- Name: hx_webchat_configs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_webchat_configs ALTER COLUMN id SET DEFAULT nextval('public.hx_webchat_configs_id_seq'::regclass);


--
-- Name: hx_work_items id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_work_items ALTER COLUMN id SET DEFAULT nextval('public.hx_work_items_id_seq'::regclass);


--
-- Name: hx_workspace_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_workspace_events ALTER COLUMN id SET DEFAULT nextval('public.hx_workspace_events_id_seq'::regclass);


--
-- Name: insight_evidence id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.insight_evidence ALTER COLUMN id SET DEFAULT nextval('public.insight_evidence_id_seq'::regclass);


--
-- Name: insights id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.insights ALTER COLUMN id SET DEFAULT nextval('public.insights_id_seq'::regclass);


--
-- Name: knowledge_entries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knowledge_entries ALTER COLUMN id SET DEFAULT nextval('public.knowledge_entries_id_seq'::regclass);


--
-- Name: learnings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.learnings ALTER COLUMN id SET DEFAULT nextval('public.learnings_id_seq'::regclass);


--
-- Name: product_conversations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_conversations ALTER COLUMN id SET DEFAULT nextval('public.product_conversations_id_seq'::regclass);


--
-- Name: product_graph_edges id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_graph_edges ALTER COLUMN id SET DEFAULT nextval('public.product_graph_edges_id_seq'::regclass);


--
-- Name: product_messages id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_messages ALTER COLUMN id SET DEFAULT nextval('public.product_messages_id_seq'::regclass);


--
-- Name: product_simulations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_simulations ALTER COLUMN id SET DEFAULT nextval('public.product_simulations_id_seq'::regclass);


--
-- Name: projects id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects ALTER COLUMN id SET DEFAULT nextval('public.projects_id_seq'::regclass);


--
-- Name: requirement_insights id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.requirement_insights ALTER COLUMN id SET DEFAULT nextval('public.requirement_insights_id_seq'::regclass);


--
-- Name: requirements id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.requirements ALTER COLUMN id SET DEFAULT nextval('public.requirements_id_seq'::regclass);


--
-- Name: routine_runs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.routine_runs ALTER COLUMN id SET DEFAULT nextval('public.routine_runs_id_seq'::regclass);


--
-- Name: routines id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.routines ALTER COLUMN id SET DEFAULT nextval('public.routines_id_seq'::regclass);


--
-- Name: sim_agent_profiles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sim_agent_profiles ALTER COLUMN id SET DEFAULT nextval('public.sim_agent_profiles_id_seq'::regclass);


--
-- Name: sim_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sim_events ALTER COLUMN id SET DEFAULT nextval('public.sim_events_id_seq'::regclass);


--
-- Name: sim_reports id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sim_reports ALTER COLUMN id SET DEFAULT nextval('public.sim_reports_id_seq'::regclass);


--
-- Name: sim_ticks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sim_ticks ALTER COLUMN id SET DEFAULT nextval('public.sim_ticks_id_seq'::regclass);


--
-- Name: simulations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.simulations ALTER COLUMN id SET DEFAULT nextval('public.simulations_id_seq'::regclass);


--
-- Name: source_chunks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.source_chunks ALTER COLUMN id SET DEFAULT nextval('public.source_chunks_id_seq'::regclass);


--
-- Name: sources id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sources ALTER COLUMN id SET DEFAULT nextval('public.sources_id_seq'::regclass);


--
-- Name: strategies id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strategies ALTER COLUMN id SET DEFAULT nextval('public.strategies_id_seq'::regclass);


--
-- Name: task_feedback id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_feedback ALTER COLUMN id SET DEFAULT nextval('public.task_feedback_id_seq'::regclass);


--
-- Name: tasks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks ALTER COLUMN id SET DEFAULT nextval('public.tasks_id_seq'::regclass);


--
-- Name: watch_targets id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.watch_targets ALTER COLUMN id SET DEFAULT nextval('public.watch_targets_id_seq'::regclass);


--
-- Name: architecture_nodes architecture_nodes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.architecture_nodes
    ADD CONSTRAINT architecture_nodes_pkey PRIMARY KEY (id);


--
-- Name: artifact_versions artifact_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.artifact_versions
    ADD CONSTRAINT artifact_versions_pkey PRIMARY KEY (id);


--
-- Name: artifacts artifacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.artifacts
    ADD CONSTRAINT artifacts_pkey PRIMARY KEY (id);


--
-- Name: board_edges board_edges_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.board_edges
    ADD CONSTRAINT board_edges_pkey PRIMARY KEY (id);


--
-- Name: board_nodes board_nodes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.board_nodes
    ADD CONSTRAINT board_nodes_pkey PRIMARY KEY (id);


--
-- Name: board_session_events board_session_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.board_session_events
    ADD CONSTRAINT board_session_events_pkey PRIMARY KEY (id);


--
-- Name: board_sessions board_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.board_sessions
    ADD CONSTRAINT board_sessions_pkey PRIMARY KEY (id);


--
-- Name: constraints constraints_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.constraints
    ADD CONSTRAINT constraints_pkey PRIMARY KEY (id);


--
-- Name: decisions decisions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.decisions
    ADD CONSTRAINT decisions_pkey PRIMARY KEY (id);


--
-- Name: design_nodes design_nodes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.design_nodes
    ADD CONSTRAINT design_nodes_pkey PRIMARY KEY (id);


--
-- Name: graph_flags graph_flags_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.graph_flags
    ADD CONSTRAINT graph_flags_pkey PRIMARY KEY (id);


--
-- Name: hx_agent_mcp_servers hx_agent_mcp_servers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_agent_mcp_servers
    ADD CONSTRAINT hx_agent_mcp_servers_pkey PRIMARY KEY (id);


--
-- Name: hx_agent_profiles hx_agent_profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_agent_profiles
    ADD CONSTRAINT hx_agent_profiles_pkey PRIMARY KEY (id);


--
-- Name: hx_approval_records hx_approval_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_approval_records
    ADD CONSTRAINT hx_approval_records_pkey PRIMARY KEY (id);


--
-- Name: hx_artifacts hx_artifacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_artifacts
    ADD CONSTRAINT hx_artifacts_pkey PRIMARY KEY (id);


--
-- Name: hx_budget_policies hx_budget_policies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_budget_policies
    ADD CONSTRAINT hx_budget_policies_pkey PRIMARY KEY (id);


--
-- Name: hx_budget_usages hx_budget_usages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_budget_usages
    ADD CONSTRAINT hx_budget_usages_pkey PRIMARY KEY (id);


--
-- Name: hx_checkpoints hx_checkpoints_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_checkpoints
    ADD CONSTRAINT hx_checkpoints_pkey PRIMARY KEY (id);


--
-- Name: hx_control_policies hx_control_policies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_control_policies
    ADD CONSTRAINT hx_control_policies_pkey PRIMARY KEY (id);


--
-- Name: hx_conversation_branches hx_conversation_branches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_conversation_branches
    ADD CONSTRAINT hx_conversation_branches_pkey PRIMARY KEY (id);


--
-- Name: hx_conversations hx_conversations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_conversations
    ADD CONSTRAINT hx_conversations_pkey PRIMARY KEY (id);


--
-- Name: hx_coordination_leases hx_coordination_leases_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_coordination_leases
    ADD CONSTRAINT hx_coordination_leases_pkey PRIMARY KEY (id);


--
-- Name: hx_discord_configs hx_discord_configs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_discord_configs
    ADD CONSTRAINT hx_discord_configs_pkey PRIMARY KEY (id);


--
-- Name: hx_ingest_runs hx_ingest_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_ingest_runs
    ADD CONSTRAINT hx_ingest_runs_pkey PRIMARY KEY (id);


--
-- Name: hx_job_runs hx_job_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_job_runs
    ADD CONSTRAINT hx_job_runs_pkey PRIMARY KEY (id);


--
-- Name: hx_mcp_server_configs hx_mcp_server_configs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_mcp_server_configs
    ADD CONSTRAINT hx_mcp_server_configs_pkey PRIMARY KEY (id);


--
-- Name: hx_memory_edges hx_memory_edges_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_memory_edges
    ADD CONSTRAINT hx_memory_edges_pkey PRIMARY KEY (id);


--
-- Name: hx_memory_entries hx_memory_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_memory_entries
    ADD CONSTRAINT hx_memory_entries_pkey PRIMARY KEY (id);


--
-- Name: hx_operator_secrets hx_operator_secrets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_operator_secrets
    ADD CONSTRAINT hx_operator_secrets_pkey PRIMARY KEY (id);


--
-- Name: hx_product_workspaces hx_product_workspaces_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_product_workspaces
    ADD CONSTRAINT hx_product_workspaces_pkey PRIMARY KEY (id);


--
-- Name: hx_provider_configs hx_provider_configs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_provider_configs
    ADD CONSTRAINT hx_provider_configs_pkey PRIMARY KEY (id);


--
-- Name: hx_safety_events hx_safety_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_safety_events
    ADD CONSTRAINT hx_safety_events_pkey PRIMARY KEY (id);


--
-- Name: hx_scheduled_jobs hx_scheduled_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_scheduled_jobs
    ADD CONSTRAINT hx_scheduled_jobs_pkey PRIMARY KEY (id);


--
-- Name: hx_skill_installs hx_skill_installs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_skill_installs
    ADD CONSTRAINT hx_skill_installs_pkey PRIMARY KEY (id);


--
-- Name: hx_slack_configs hx_slack_configs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_slack_configs
    ADD CONSTRAINT hx_slack_configs_pkey PRIMARY KEY (id);


--
-- Name: hx_telegram_configs hx_telegram_configs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_telegram_configs
    ADD CONSTRAINT hx_telegram_configs_pkey PRIMARY KEY (id);


--
-- Name: hx_tool_policies hx_tool_policies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_tool_policies
    ADD CONSTRAINT hx_tool_policies_pkey PRIMARY KEY (id);


--
-- Name: hx_turns hx_turns_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_turns
    ADD CONSTRAINT hx_turns_pkey PRIMARY KEY (id);


--
-- Name: hx_webchat_configs hx_webchat_configs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_webchat_configs
    ADD CONSTRAINT hx_webchat_configs_pkey PRIMARY KEY (id);


--
-- Name: hx_work_items hx_work_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_work_items
    ADD CONSTRAINT hx_work_items_pkey PRIMARY KEY (id);


--
-- Name: hx_workspace_events hx_workspace_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_workspace_events
    ADD CONSTRAINT hx_workspace_events_pkey PRIMARY KEY (id);


--
-- Name: insight_evidence insight_evidence_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.insight_evidence
    ADD CONSTRAINT insight_evidence_pkey PRIMARY KEY (id);


--
-- Name: insights insights_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.insights
    ADD CONSTRAINT insights_pkey PRIMARY KEY (id);


--
-- Name: knowledge_entries knowledge_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knowledge_entries
    ADD CONSTRAINT knowledge_entries_pkey PRIMARY KEY (id);


--
-- Name: learnings learnings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.learnings
    ADD CONSTRAINT learnings_pkey PRIMARY KEY (id);


--
-- Name: product_conversations product_conversations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_conversations
    ADD CONSTRAINT product_conversations_pkey PRIMARY KEY (id);


--
-- Name: product_graph_edges product_graph_edges_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_graph_edges
    ADD CONSTRAINT product_graph_edges_pkey PRIMARY KEY (id);


--
-- Name: product_messages product_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_messages
    ADD CONSTRAINT product_messages_pkey PRIMARY KEY (id);


--
-- Name: product_simulations product_simulations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_simulations
    ADD CONSTRAINT product_simulations_pkey PRIMARY KEY (id);


--
-- Name: projects projects_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_pkey PRIMARY KEY (id);


--
-- Name: requirement_insights requirement_insights_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.requirement_insights
    ADD CONSTRAINT requirement_insights_pkey PRIMARY KEY (id);


--
-- Name: requirements requirements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.requirements
    ADD CONSTRAINT requirements_pkey PRIMARY KEY (id);


--
-- Name: routine_runs routine_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.routine_runs
    ADD CONSTRAINT routine_runs_pkey PRIMARY KEY (id);


--
-- Name: routines routines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.routines
    ADD CONSTRAINT routines_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: sim_agent_profiles sim_agent_profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sim_agent_profiles
    ADD CONSTRAINT sim_agent_profiles_pkey PRIMARY KEY (id);


--
-- Name: sim_events sim_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sim_events
    ADD CONSTRAINT sim_events_pkey PRIMARY KEY (id);


--
-- Name: sim_reports sim_reports_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sim_reports
    ADD CONSTRAINT sim_reports_pkey PRIMARY KEY (id);


--
-- Name: sim_ticks sim_ticks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sim_ticks
    ADD CONSTRAINT sim_ticks_pkey PRIMARY KEY (id);


--
-- Name: simulations simulations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.simulations
    ADD CONSTRAINT simulations_pkey PRIMARY KEY (id);


--
-- Name: source_chunks source_chunks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.source_chunks
    ADD CONSTRAINT source_chunks_pkey PRIMARY KEY (id);


--
-- Name: sources sources_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sources
    ADD CONSTRAINT sources_pkey PRIMARY KEY (id);


--
-- Name: strategies strategies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strategies
    ADD CONSTRAINT strategies_pkey PRIMARY KEY (id);


--
-- Name: task_feedback task_feedback_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_feedback
    ADD CONSTRAINT task_feedback_pkey PRIMARY KEY (id);


--
-- Name: tasks tasks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT tasks_pkey PRIMARY KEY (id);


--
-- Name: watch_targets watch_targets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.watch_targets
    ADD CONSTRAINT watch_targets_pkey PRIMARY KEY (id);


--
-- Name: architecture_nodes_node_type_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX architecture_nodes_node_type_index ON public.architecture_nodes USING btree (node_type);


--
-- Name: architecture_nodes_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX architecture_nodes_project_id_index ON public.architecture_nodes USING btree (project_id);


--
-- Name: architecture_nodes_search_vector_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX architecture_nodes_search_vector_index ON public.architecture_nodes USING gin (search_vector);


--
-- Name: architecture_nodes_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX architecture_nodes_status_index ON public.architecture_nodes USING btree (status);


--
-- Name: artifact_versions_artifact_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX artifact_versions_artifact_id_index ON public.artifact_versions USING btree (artifact_id);


--
-- Name: artifact_versions_artifact_id_version_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX artifact_versions_artifact_id_version_index ON public.artifact_versions USING btree (artifact_id, version);


--
-- Name: artifacts_project_id_artifact_type_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX artifacts_project_id_artifact_type_index ON public.artifacts USING btree (project_id, artifact_type);


--
-- Name: artifacts_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX artifacts_project_id_index ON public.artifacts USING btree (project_id);


--
-- Name: artifacts_project_id_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX artifacts_project_id_status_index ON public.artifacts USING btree (project_id, status);


--
-- Name: board_edges_board_session_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX board_edges_board_session_id_index ON public.board_edges USING btree (board_session_id);


--
-- Name: board_edges_from_board_node_id_to_board_node_id_kind_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX board_edges_from_board_node_id_to_board_node_id_kind_index ON public.board_edges USING btree (from_board_node_id, to_board_node_id, kind);


--
-- Name: board_nodes_board_session_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX board_nodes_board_session_id_index ON public.board_nodes USING btree (board_session_id);


--
-- Name: board_nodes_node_type_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX board_nodes_node_type_index ON public.board_nodes USING btree (node_type);


--
-- Name: board_nodes_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX board_nodes_project_id_index ON public.board_nodes USING btree (project_id);


--
-- Name: board_nodes_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX board_nodes_status_index ON public.board_nodes USING btree (status);


--
-- Name: board_session_events_board_session_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX board_session_events_board_session_id_index ON public.board_session_events USING btree (board_session_id);


--
-- Name: board_session_events_board_session_id_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX board_session_events_board_session_id_inserted_at_index ON public.board_session_events USING btree (board_session_id, inserted_at);


--
-- Name: board_sessions_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX board_sessions_project_id_index ON public.board_sessions USING btree (project_id);


--
-- Name: board_sessions_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX board_sessions_status_index ON public.board_sessions USING btree (status);


--
-- Name: constraints_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX constraints_project_id_index ON public.constraints USING btree (project_id);


--
-- Name: constraints_search_vector_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX constraints_search_vector_index ON public.constraints USING gin (search_vector);


--
-- Name: constraints_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX constraints_status_index ON public.constraints USING btree (status);


--
-- Name: decisions_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX decisions_project_id_index ON public.decisions USING btree (project_id);


--
-- Name: decisions_search_vector_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX decisions_search_vector_index ON public.decisions USING gin (search_vector);


--
-- Name: decisions_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX decisions_status_index ON public.decisions USING btree (status);


--
-- Name: design_nodes_node_type_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX design_nodes_node_type_index ON public.design_nodes USING btree (node_type);


--
-- Name: design_nodes_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX design_nodes_project_id_index ON public.design_nodes USING btree (project_id);


--
-- Name: design_nodes_search_vector_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX design_nodes_search_vector_index ON public.design_nodes USING gin (search_vector);


--
-- Name: design_nodes_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX design_nodes_status_index ON public.design_nodes USING btree (status);


--
-- Name: graph_flags_flag_type_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX graph_flags_flag_type_index ON public.graph_flags USING btree (flag_type);


--
-- Name: graph_flags_node_type_node_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX graph_flags_node_type_node_id_index ON public.graph_flags USING btree (node_type, node_id);


--
-- Name: graph_flags_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX graph_flags_project_id_index ON public.graph_flags USING btree (project_id);


--
-- Name: graph_flags_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX graph_flags_status_index ON public.graph_flags USING btree (status);


--
-- Name: hx_agent_mcp_servers_agent_id_enabled_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_agent_mcp_servers_agent_id_enabled_index ON public.hx_agent_mcp_servers USING btree (agent_id, enabled);


--
-- Name: hx_agent_mcp_servers_agent_id_mcp_server_config_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX hx_agent_mcp_servers_agent_id_mcp_server_config_id_index ON public.hx_agent_mcp_servers USING btree (agent_id, mcp_server_config_id);


--
-- Name: hx_agent_profiles_slug_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX hx_agent_profiles_slug_index ON public.hx_agent_profiles USING btree (slug);


--
-- Name: hx_approval_records_decision_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_approval_records_decision_index ON public.hx_approval_records USING btree (decision);


--
-- Name: hx_approval_records_reviewer_agent_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_approval_records_reviewer_agent_id_index ON public.hx_approval_records USING btree (reviewer_agent_id);


--
-- Name: hx_approval_records_subject_type_subject_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_approval_records_subject_type_subject_id_index ON public.hx_approval_records USING btree (subject_type, subject_id);


--
-- Name: hx_approval_records_work_item_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_approval_records_work_item_id_index ON public.hx_approval_records USING btree (work_item_id);


--
-- Name: hx_artifacts_type_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_artifacts_type_index ON public.hx_artifacts USING btree (type);


--
-- Name: hx_artifacts_work_item_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_artifacts_work_item_id_index ON public.hx_artifacts USING btree (work_item_id);


--
-- Name: hx_budget_policies_agent_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX hx_budget_policies_agent_id_index ON public.hx_budget_policies USING btree (agent_id);


--
-- Name: hx_budget_usages_agent_id_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_budget_usages_agent_id_inserted_at_index ON public.hx_budget_usages USING btree (agent_id, inserted_at);


--
-- Name: hx_budget_usages_conversation_id_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_budget_usages_conversation_id_inserted_at_index ON public.hx_budget_usages USING btree (conversation_id, inserted_at);


--
-- Name: hx_checkpoints_conversation_id_process_type_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX hx_checkpoints_conversation_id_process_type_index ON public.hx_checkpoints USING btree (conversation_id, process_type);


--
-- Name: hx_control_policies_scope_agent_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX hx_control_policies_scope_agent_id_index ON public.hx_control_policies USING btree (scope, agent_id);


--
-- Name: hx_conversation_branches_conversation_id_branch_uuid_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX hx_conversation_branches_conversation_id_branch_uuid_index ON public.hx_conversation_branches USING btree (conversation_id, branch_uuid);


--
-- Name: hx_conversation_branches_conversation_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_conversation_branches_conversation_id_index ON public.hx_conversation_branches USING btree (conversation_id);


--
-- Name: hx_conversation_branches_conversation_id_label_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX hx_conversation_branches_conversation_id_label_index ON public.hx_conversation_branches USING btree (conversation_id, label);


--
-- Name: hx_conversations_agent_id_channel_external_ref_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX hx_conversations_agent_id_channel_external_ref_index ON public.hx_conversations USING btree (agent_id, channel, external_ref);


--
-- Name: hx_conversations_agent_id_channel_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_conversations_agent_id_channel_index ON public.hx_conversations USING btree (agent_id, channel);


--
-- Name: hx_coordination_leases_expires_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_coordination_leases_expires_at_index ON public.hx_coordination_leases USING btree (expires_at);


--
-- Name: hx_coordination_leases_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX hx_coordination_leases_name_index ON public.hx_coordination_leases USING btree (name);


--
-- Name: hx_ingest_runs_agent_id_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_ingest_runs_agent_id_inserted_at_index ON public.hx_ingest_runs USING btree (agent_id, inserted_at);


--
-- Name: hx_ingest_runs_agent_id_source_file_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_ingest_runs_agent_id_source_file_index ON public.hx_ingest_runs USING btree (agent_id, source_file);


--
-- Name: hx_ingest_runs_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_ingest_runs_status_index ON public.hx_ingest_runs USING btree (status);


--
-- Name: hx_job_runs_agent_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_job_runs_agent_id_index ON public.hx_job_runs USING btree (agent_id);


--
-- Name: hx_job_runs_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_job_runs_inserted_at_index ON public.hx_job_runs USING btree (inserted_at);


--
-- Name: hx_job_runs_scheduled_job_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_job_runs_scheduled_job_id_index ON public.hx_job_runs USING btree (scheduled_job_id);


--
-- Name: hx_mcp_server_configs_enabled_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_mcp_server_configs_enabled_index ON public.hx_mcp_server_configs USING btree (enabled);


--
-- Name: hx_memory_edges_from_memory_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_memory_edges_from_memory_id_index ON public.hx_memory_edges USING btree (from_memory_id);


--
-- Name: hx_memory_edges_to_memory_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_memory_edges_to_memory_id_index ON public.hx_memory_edges USING btree (to_memory_id);


--
-- Name: hx_memory_entries_agent_id_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_memory_entries_agent_id_status_index ON public.hx_memory_entries USING btree (agent_id, status);


--
-- Name: hx_memory_entries_agent_id_type_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_memory_entries_agent_id_type_index ON public.hx_memory_entries USING btree (agent_id, type);


--
-- Name: hx_memory_entries_conversation_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_memory_entries_conversation_id_index ON public.hx_memory_entries USING btree (conversation_id);


--
-- Name: hx_memory_entries_embedding_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_memory_entries_embedding_idx ON public.hx_memory_entries USING ivfflat (embedding public.vector_cosine_ops) WITH (lists='100');


--
-- Name: hx_memory_entries_search_vector_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_memory_entries_search_vector_idx ON public.hx_memory_entries USING gin (search_vector);


--
-- Name: hx_operator_secrets_scope_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX hx_operator_secrets_scope_index ON public.hx_operator_secrets USING btree (scope);


--
-- Name: hx_product_workspaces_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX hx_product_workspaces_project_id_index ON public.hx_product_workspaces USING btree (project_id);


--
-- Name: hx_product_workspaces_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_product_workspaces_status_index ON public.hx_product_workspaces USING btree (status);


--
-- Name: hx_safety_events_agent_id_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_safety_events_agent_id_inserted_at_index ON public.hx_safety_events USING btree (agent_id, inserted_at);


--
-- Name: hx_safety_events_conversation_id_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_safety_events_conversation_id_inserted_at_index ON public.hx_safety_events USING btree (conversation_id, inserted_at);


--
-- Name: hx_safety_events_status_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_safety_events_status_inserted_at_index ON public.hx_safety_events USING btree (status, inserted_at);


--
-- Name: hx_scheduled_jobs_agent_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_scheduled_jobs_agent_id_index ON public.hx_scheduled_jobs USING btree (agent_id);


--
-- Name: hx_scheduled_jobs_circuit_state_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_scheduled_jobs_circuit_state_index ON public.hx_scheduled_jobs USING btree (circuit_state);


--
-- Name: hx_scheduled_jobs_enabled_next_run_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_scheduled_jobs_enabled_next_run_at_index ON public.hx_scheduled_jobs USING btree (enabled, next_run_at);


--
-- Name: hx_scheduled_jobs_paused_until_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_scheduled_jobs_paused_until_index ON public.hx_scheduled_jobs USING btree (paused_until);


--
-- Name: hx_skill_installs_agent_id_enabled_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_skill_installs_agent_id_enabled_index ON public.hx_skill_installs USING btree (agent_id, enabled);


--
-- Name: hx_skill_installs_agent_id_slug_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX hx_skill_installs_agent_id_slug_index ON public.hx_skill_installs USING btree (agent_id, slug);


--
-- Name: hx_telegram_configs_default_agent_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_telegram_configs_default_agent_id_index ON public.hx_telegram_configs USING btree (default_agent_id);


--
-- Name: hx_tool_policies_scope_agent_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX hx_tool_policies_scope_agent_id_index ON public.hx_tool_policies USING btree (scope, agent_id);


--
-- Name: hx_turns_conversation_id_branch_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_turns_conversation_id_branch_id_index ON public.hx_turns USING btree (conversation_id, branch_id);


--
-- Name: hx_turns_conversation_id_branch_id_sequence_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX hx_turns_conversation_id_branch_id_sequence_index ON public.hx_turns USING btree (conversation_id, branch_id, sequence);


--
-- Name: hx_work_items_assigned_agent_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_work_items_assigned_agent_id_index ON public.hx_work_items USING btree (assigned_agent_id);


--
-- Name: hx_work_items_assigned_role_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_work_items_assigned_role_index ON public.hx_work_items USING btree (assigned_role);


--
-- Name: hx_work_items_delegated_by_agent_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_work_items_delegated_by_agent_id_index ON public.hx_work_items USING btree (delegated_by_agent_id);


--
-- Name: hx_work_items_kind_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_work_items_kind_index ON public.hx_work_items USING btree (kind);


--
-- Name: hx_work_items_parent_work_item_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_work_items_parent_work_item_id_index ON public.hx_work_items USING btree (parent_work_item_id);


--
-- Name: hx_work_items_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_work_items_status_index ON public.hx_work_items USING btree (status);


--
-- Name: hx_workspace_events_kind_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_workspace_events_kind_index ON public.hx_workspace_events USING btree (kind);


--
-- Name: hx_workspace_events_project_id_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_workspace_events_project_id_inserted_at_index ON public.hx_workspace_events USING btree (project_id, inserted_at);


--
-- Name: hx_workspace_events_workspace_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hx_workspace_events_workspace_id_index ON public.hx_workspace_events USING btree (workspace_id);


--
-- Name: insight_evidence_insight_id_source_chunk_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX insight_evidence_insight_id_source_chunk_id_index ON public.insight_evidence USING btree (insight_id, source_chunk_id);


--
-- Name: insight_evidence_source_chunk_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX insight_evidence_source_chunk_id_index ON public.insight_evidence USING btree (source_chunk_id);


--
-- Name: insights_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX insights_project_id_index ON public.insights USING btree (project_id);


--
-- Name: insights_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX insights_status_index ON public.insights USING btree (status);


--
-- Name: knowledge_entries_entry_type_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX knowledge_entries_entry_type_index ON public.knowledge_entries USING btree (entry_type);


--
-- Name: knowledge_entries_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX knowledge_entries_project_id_index ON public.knowledge_entries USING btree (project_id);


--
-- Name: knowledge_entries_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX knowledge_entries_status_index ON public.knowledge_entries USING btree (status);


--
-- Name: learnings_learning_type_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX learnings_learning_type_index ON public.learnings USING btree (learning_type);


--
-- Name: learnings_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX learnings_project_id_index ON public.learnings USING btree (project_id);


--
-- Name: learnings_search_vector_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX learnings_search_vector_index ON public.learnings USING gin (search_vector);


--
-- Name: learnings_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX learnings_status_index ON public.learnings USING btree (status);


--
-- Name: product_conversations_board_session_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX product_conversations_board_session_id_index ON public.product_conversations USING btree (board_session_id);


--
-- Name: product_conversations_hydra_conversation_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX product_conversations_hydra_conversation_id_index ON public.product_conversations USING btree (hydra_conversation_id);


--
-- Name: product_conversations_persona_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX product_conversations_persona_index ON public.product_conversations USING btree (persona);


--
-- Name: product_conversations_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX product_conversations_project_id_index ON public.product_conversations USING btree (project_id);


--
-- Name: product_graph_edges_from_node_type_from_node_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX product_graph_edges_from_node_type_from_node_id_index ON public.product_graph_edges USING btree (from_node_type, from_node_id);


--
-- Name: product_graph_edges_from_node_type_from_node_id_to_node_type_to; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX product_graph_edges_from_node_type_from_node_id_to_node_type_to ON public.product_graph_edges USING btree (from_node_type, from_node_id, to_node_type, to_node_id, kind);


--
-- Name: product_graph_edges_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX product_graph_edges_project_id_index ON public.product_graph_edges USING btree (project_id);


--
-- Name: product_graph_edges_to_node_type_to_node_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX product_graph_edges_to_node_type_to_node_id_index ON public.product_graph_edges USING btree (to_node_type, to_node_id);


--
-- Name: product_messages_hydra_turn_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX product_messages_hydra_turn_id_index ON public.product_messages USING btree (hydra_turn_id);


--
-- Name: product_messages_product_conversation_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX product_messages_product_conversation_id_index ON public.product_messages USING btree (product_conversation_id);


--
-- Name: product_simulations_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX product_simulations_project_id_index ON public.product_simulations USING btree (project_id);


--
-- Name: product_simulations_simulation_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX product_simulations_simulation_id_index ON public.product_simulations USING btree (simulation_id);


--
-- Name: product_simulations_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX product_simulations_status_index ON public.product_simulations USING btree (status);


--
-- Name: projects_architect_agent_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX projects_architect_agent_id_index ON public.projects USING btree (architect_agent_id);


--
-- Name: projects_coder_agent_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX projects_coder_agent_id_index ON public.projects USING btree (coder_agent_id);


--
-- Name: projects_designer_agent_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX projects_designer_agent_id_index ON public.projects USING btree (designer_agent_id);


--
-- Name: projects_memory_agent_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX projects_memory_agent_id_index ON public.projects USING btree (memory_agent_id);


--
-- Name: projects_researcher_agent_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX projects_researcher_agent_id_index ON public.projects USING btree (researcher_agent_id);


--
-- Name: projects_slug_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX projects_slug_index ON public.projects USING btree (slug);


--
-- Name: projects_strategist_agent_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX projects_strategist_agent_id_index ON public.projects USING btree (strategist_agent_id);


--
-- Name: requirement_insights_insight_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX requirement_insights_insight_id_index ON public.requirement_insights USING btree (insight_id);


--
-- Name: requirement_insights_requirement_id_insight_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX requirement_insights_requirement_id_insight_id_index ON public.requirement_insights USING btree (requirement_id, insight_id);


--
-- Name: requirements_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX requirements_project_id_index ON public.requirements USING btree (project_id);


--
-- Name: requirements_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX requirements_status_index ON public.requirements USING btree (status);


--
-- Name: routine_runs_routine_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX routine_runs_routine_id_index ON public.routine_runs USING btree (routine_id);


--
-- Name: routine_runs_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX routine_runs_status_index ON public.routine_runs USING btree (status);


--
-- Name: routines_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX routines_project_id_index ON public.routines USING btree (project_id);


--
-- Name: routines_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX routines_status_index ON public.routines USING btree (status);


--
-- Name: sim_agent_profiles_simulation_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sim_agent_profiles_simulation_id_index ON public.sim_agent_profiles USING btree (simulation_id);


--
-- Name: sim_events_simulation_id_tick_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sim_events_simulation_id_tick_index ON public.sim_events USING btree (simulation_id, tick);


--
-- Name: sim_reports_simulation_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sim_reports_simulation_id_index ON public.sim_reports USING btree (simulation_id);


--
-- Name: sim_ticks_simulation_id_tick_number_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sim_ticks_simulation_id_tick_number_index ON public.sim_ticks USING btree (simulation_id, tick_number);


--
-- Name: source_chunks_embedding_ivfflat_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX source_chunks_embedding_ivfflat_idx ON public.source_chunks USING ivfflat (embedding public.vector_cosine_ops) WITH (lists='100');


--
-- Name: source_chunks_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX source_chunks_project_id_index ON public.source_chunks USING btree (project_id);


--
-- Name: source_chunks_search_vector_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX source_chunks_search_vector_index ON public.source_chunks USING gin (search_vector);


--
-- Name: source_chunks_source_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX source_chunks_source_id_index ON public.source_chunks USING btree (source_id);


--
-- Name: source_chunks_source_id_ordinal_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX source_chunks_source_id_ordinal_index ON public.source_chunks USING btree (source_id, ordinal);


--
-- Name: sources_processing_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sources_processing_status_index ON public.sources USING btree (processing_status);


--
-- Name: sources_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sources_project_id_index ON public.sources USING btree (project_id);


--
-- Name: strategies_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX strategies_project_id_index ON public.strategies USING btree (project_id);


--
-- Name: strategies_search_vector_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX strategies_search_vector_index ON public.strategies USING gin (search_vector);


--
-- Name: strategies_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX strategies_status_index ON public.strategies USING btree (status);


--
-- Name: task_feedback_task_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX task_feedback_task_id_index ON public.task_feedback USING btree (task_id);


--
-- Name: tasks_priority_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tasks_priority_index ON public.tasks USING btree (priority);


--
-- Name: tasks_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tasks_project_id_index ON public.tasks USING btree (project_id);


--
-- Name: tasks_search_vector_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tasks_search_vector_index ON public.tasks USING gin (search_vector);


--
-- Name: tasks_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tasks_status_index ON public.tasks USING btree (status);


--
-- Name: watch_targets_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX watch_targets_project_id_index ON public.watch_targets USING btree (project_id);


--
-- Name: watch_targets_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX watch_targets_status_index ON public.watch_targets USING btree (status);


--
-- Name: architecture_nodes architecture_nodes_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.architecture_nodes
    ADD CONSTRAINT architecture_nodes_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- Name: artifact_versions artifact_versions_artifact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.artifact_versions
    ADD CONSTRAINT artifact_versions_artifact_id_fkey FOREIGN KEY (artifact_id) REFERENCES public.artifacts(id) ON DELETE CASCADE;


--
-- Name: artifacts artifacts_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.artifacts
    ADD CONSTRAINT artifacts_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- Name: board_edges board_edges_board_session_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.board_edges
    ADD CONSTRAINT board_edges_board_session_id_fkey FOREIGN KEY (board_session_id) REFERENCES public.board_sessions(id) ON DELETE CASCADE;


--
-- Name: board_edges board_edges_from_board_node_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.board_edges
    ADD CONSTRAINT board_edges_from_board_node_id_fkey FOREIGN KEY (from_board_node_id) REFERENCES public.board_nodes(id) ON DELETE CASCADE;


--
-- Name: board_edges board_edges_to_board_node_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.board_edges
    ADD CONSTRAINT board_edges_to_board_node_id_fkey FOREIGN KEY (to_board_node_id) REFERENCES public.board_nodes(id) ON DELETE CASCADE;


--
-- Name: board_nodes board_nodes_board_session_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.board_nodes
    ADD CONSTRAINT board_nodes_board_session_id_fkey FOREIGN KEY (board_session_id) REFERENCES public.board_sessions(id) ON DELETE CASCADE;


--
-- Name: board_nodes board_nodes_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.board_nodes
    ADD CONSTRAINT board_nodes_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- Name: board_sessions board_sessions_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.board_sessions
    ADD CONSTRAINT board_sessions_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- Name: constraints constraints_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.constraints
    ADD CONSTRAINT constraints_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- Name: decisions decisions_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.decisions
    ADD CONSTRAINT decisions_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- Name: design_nodes design_nodes_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.design_nodes
    ADD CONSTRAINT design_nodes_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- Name: graph_flags graph_flags_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.graph_flags
    ADD CONSTRAINT graph_flags_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- Name: hx_agent_mcp_servers hx_agent_mcp_servers_agent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_agent_mcp_servers
    ADD CONSTRAINT hx_agent_mcp_servers_agent_id_fkey FOREIGN KEY (agent_id) REFERENCES public.hx_agent_profiles(id) ON DELETE CASCADE;


--
-- Name: hx_agent_mcp_servers hx_agent_mcp_servers_mcp_server_config_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_agent_mcp_servers
    ADD CONSTRAINT hx_agent_mcp_servers_mcp_server_config_id_fkey FOREIGN KEY (mcp_server_config_id) REFERENCES public.hx_mcp_server_configs(id) ON DELETE CASCADE;


--
-- Name: hx_approval_records hx_approval_records_reviewer_agent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_approval_records
    ADD CONSTRAINT hx_approval_records_reviewer_agent_id_fkey FOREIGN KEY (reviewer_agent_id) REFERENCES public.hx_agent_profiles(id) ON DELETE SET NULL;


--
-- Name: hx_approval_records hx_approval_records_work_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_approval_records
    ADD CONSTRAINT hx_approval_records_work_item_id_fkey FOREIGN KEY (work_item_id) REFERENCES public.hx_work_items(id) ON DELETE SET NULL;


--
-- Name: hx_artifacts hx_artifacts_work_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_artifacts
    ADD CONSTRAINT hx_artifacts_work_item_id_fkey FOREIGN KEY (work_item_id) REFERENCES public.hx_work_items(id) ON DELETE CASCADE;


--
-- Name: hx_budget_policies hx_budget_policies_agent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_budget_policies
    ADD CONSTRAINT hx_budget_policies_agent_id_fkey FOREIGN KEY (agent_id) REFERENCES public.hx_agent_profiles(id) ON DELETE CASCADE;


--
-- Name: hx_budget_usages hx_budget_usages_agent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_budget_usages
    ADD CONSTRAINT hx_budget_usages_agent_id_fkey FOREIGN KEY (agent_id) REFERENCES public.hx_agent_profiles(id) ON DELETE CASCADE;


--
-- Name: hx_budget_usages hx_budget_usages_conversation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_budget_usages
    ADD CONSTRAINT hx_budget_usages_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.hx_conversations(id) ON DELETE CASCADE;


--
-- Name: hx_checkpoints hx_checkpoints_conversation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_checkpoints
    ADD CONSTRAINT hx_checkpoints_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.hx_conversations(id) ON DELETE CASCADE;


--
-- Name: hx_control_policies hx_control_policies_agent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_control_policies
    ADD CONSTRAINT hx_control_policies_agent_id_fkey FOREIGN KEY (agent_id) REFERENCES public.hx_agent_profiles(id) ON DELETE CASCADE;


--
-- Name: hx_conversation_branches hx_conversation_branches_conversation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_conversation_branches
    ADD CONSTRAINT hx_conversation_branches_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.hx_conversations(id) ON DELETE CASCADE;


--
-- Name: hx_conversation_branches hx_conversation_branches_parent_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_conversation_branches
    ADD CONSTRAINT hx_conversation_branches_parent_branch_id_fkey FOREIGN KEY (parent_branch_id) REFERENCES public.hx_conversation_branches(id) ON DELETE SET NULL;


--
-- Name: hx_conversations hx_conversations_agent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_conversations
    ADD CONSTRAINT hx_conversations_agent_id_fkey FOREIGN KEY (agent_id) REFERENCES public.hx_agent_profiles(id) ON DELETE CASCADE;


--
-- Name: hx_discord_configs hx_discord_configs_default_agent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_discord_configs
    ADD CONSTRAINT hx_discord_configs_default_agent_id_fkey FOREIGN KEY (default_agent_id) REFERENCES public.hx_agent_profiles(id) ON DELETE SET NULL;


--
-- Name: hx_ingest_runs hx_ingest_runs_agent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_ingest_runs
    ADD CONSTRAINT hx_ingest_runs_agent_id_fkey FOREIGN KEY (agent_id) REFERENCES public.hx_agent_profiles(id) ON DELETE CASCADE;


--
-- Name: hx_job_runs hx_job_runs_agent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_job_runs
    ADD CONSTRAINT hx_job_runs_agent_id_fkey FOREIGN KEY (agent_id) REFERENCES public.hx_agent_profiles(id) ON DELETE CASCADE;


--
-- Name: hx_job_runs hx_job_runs_scheduled_job_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_job_runs
    ADD CONSTRAINT hx_job_runs_scheduled_job_id_fkey FOREIGN KEY (scheduled_job_id) REFERENCES public.hx_scheduled_jobs(id) ON DELETE CASCADE;


--
-- Name: hx_memory_edges hx_memory_edges_from_memory_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_memory_edges
    ADD CONSTRAINT hx_memory_edges_from_memory_id_fkey FOREIGN KEY (from_memory_id) REFERENCES public.hx_memory_entries(id) ON DELETE CASCADE;


--
-- Name: hx_memory_edges hx_memory_edges_to_memory_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_memory_edges
    ADD CONSTRAINT hx_memory_edges_to_memory_id_fkey FOREIGN KEY (to_memory_id) REFERENCES public.hx_memory_entries(id) ON DELETE CASCADE;


--
-- Name: hx_memory_entries hx_memory_entries_agent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_memory_entries
    ADD CONSTRAINT hx_memory_entries_agent_id_fkey FOREIGN KEY (agent_id) REFERENCES public.hx_agent_profiles(id) ON DELETE CASCADE;


--
-- Name: hx_memory_entries hx_memory_entries_conversation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_memory_entries
    ADD CONSTRAINT hx_memory_entries_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.hx_conversations(id) ON DELETE SET NULL;


--
-- Name: hx_product_workspaces hx_product_workspaces_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_product_workspaces
    ADD CONSTRAINT hx_product_workspaces_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- Name: hx_safety_events hx_safety_events_agent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_safety_events
    ADD CONSTRAINT hx_safety_events_agent_id_fkey FOREIGN KEY (agent_id) REFERENCES public.hx_agent_profiles(id) ON DELETE CASCADE;


--
-- Name: hx_safety_events hx_safety_events_conversation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_safety_events
    ADD CONSTRAINT hx_safety_events_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.hx_conversations(id) ON DELETE SET NULL;


--
-- Name: hx_scheduled_jobs hx_scheduled_jobs_agent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_scheduled_jobs
    ADD CONSTRAINT hx_scheduled_jobs_agent_id_fkey FOREIGN KEY (agent_id) REFERENCES public.hx_agent_profiles(id) ON DELETE CASCADE;


--
-- Name: hx_skill_installs hx_skill_installs_agent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_skill_installs
    ADD CONSTRAINT hx_skill_installs_agent_id_fkey FOREIGN KEY (agent_id) REFERENCES public.hx_agent_profiles(id) ON DELETE CASCADE;


--
-- Name: hx_slack_configs hx_slack_configs_default_agent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_slack_configs
    ADD CONSTRAINT hx_slack_configs_default_agent_id_fkey FOREIGN KEY (default_agent_id) REFERENCES public.hx_agent_profiles(id) ON DELETE SET NULL;


--
-- Name: hx_telegram_configs hx_telegram_configs_default_agent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_telegram_configs
    ADD CONSTRAINT hx_telegram_configs_default_agent_id_fkey FOREIGN KEY (default_agent_id) REFERENCES public.hx_agent_profiles(id) ON DELETE CASCADE;


--
-- Name: hx_tool_policies hx_tool_policies_agent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_tool_policies
    ADD CONSTRAINT hx_tool_policies_agent_id_fkey FOREIGN KEY (agent_id) REFERENCES public.hx_agent_profiles(id) ON DELETE CASCADE;


--
-- Name: hx_turns hx_turns_conversation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_turns
    ADD CONSTRAINT hx_turns_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.hx_conversations(id) ON DELETE CASCADE;


--
-- Name: hx_webchat_configs hx_webchat_configs_default_agent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_webchat_configs
    ADD CONSTRAINT hx_webchat_configs_default_agent_id_fkey FOREIGN KEY (default_agent_id) REFERENCES public.hx_agent_profiles(id) ON DELETE SET NULL;


--
-- Name: hx_work_items hx_work_items_assigned_agent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_work_items
    ADD CONSTRAINT hx_work_items_assigned_agent_id_fkey FOREIGN KEY (assigned_agent_id) REFERENCES public.hx_agent_profiles(id) ON DELETE SET NULL;


--
-- Name: hx_work_items hx_work_items_delegated_by_agent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_work_items
    ADD CONSTRAINT hx_work_items_delegated_by_agent_id_fkey FOREIGN KEY (delegated_by_agent_id) REFERENCES public.hx_agent_profiles(id) ON DELETE SET NULL;


--
-- Name: hx_work_items hx_work_items_parent_work_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_work_items
    ADD CONSTRAINT hx_work_items_parent_work_item_id_fkey FOREIGN KEY (parent_work_item_id) REFERENCES public.hx_work_items(id) ON DELETE SET NULL;


--
-- Name: hx_workspace_events hx_workspace_events_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_workspace_events
    ADD CONSTRAINT hx_workspace_events_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- Name: hx_workspace_events hx_workspace_events_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hx_workspace_events
    ADD CONSTRAINT hx_workspace_events_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.hx_product_workspaces(id) ON DELETE CASCADE;


--
-- Name: insight_evidence insight_evidence_insight_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.insight_evidence
    ADD CONSTRAINT insight_evidence_insight_id_fkey FOREIGN KEY (insight_id) REFERENCES public.insights(id) ON DELETE CASCADE;


--
-- Name: insight_evidence insight_evidence_source_chunk_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.insight_evidence
    ADD CONSTRAINT insight_evidence_source_chunk_id_fkey FOREIGN KEY (source_chunk_id) REFERENCES public.source_chunks(id) ON DELETE CASCADE;


--
-- Name: insights insights_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.insights
    ADD CONSTRAINT insights_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- Name: knowledge_entries knowledge_entries_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knowledge_entries
    ADD CONSTRAINT knowledge_entries_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- Name: learnings learnings_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.learnings
    ADD CONSTRAINT learnings_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- Name: product_conversations product_conversations_board_session_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_conversations
    ADD CONSTRAINT product_conversations_board_session_id_fkey FOREIGN KEY (board_session_id) REFERENCES public.board_sessions(id) ON DELETE SET NULL;


--
-- Name: product_conversations product_conversations_hydra_conversation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_conversations
    ADD CONSTRAINT product_conversations_hydra_conversation_id_fkey FOREIGN KEY (hydra_conversation_id) REFERENCES public.hx_conversations(id) ON DELETE SET NULL;


--
-- Name: product_conversations product_conversations_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_conversations
    ADD CONSTRAINT product_conversations_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- Name: product_graph_edges product_graph_edges_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_graph_edges
    ADD CONSTRAINT product_graph_edges_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- Name: product_messages product_messages_hydra_turn_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_messages
    ADD CONSTRAINT product_messages_hydra_turn_id_fkey FOREIGN KEY (hydra_turn_id) REFERENCES public.hx_turns(id) ON DELETE SET NULL;


--
-- Name: product_messages product_messages_product_conversation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_messages
    ADD CONSTRAINT product_messages_product_conversation_id_fkey FOREIGN KEY (product_conversation_id) REFERENCES public.product_conversations(id) ON DELETE CASCADE;


--
-- Name: product_simulations product_simulations_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_simulations
    ADD CONSTRAINT product_simulations_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- Name: product_simulations product_simulations_simulation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_simulations
    ADD CONSTRAINT product_simulations_simulation_id_fkey FOREIGN KEY (simulation_id) REFERENCES public.simulations(id) ON DELETE SET NULL;


--
-- Name: projects projects_architect_agent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_architect_agent_id_fkey FOREIGN KEY (architect_agent_id) REFERENCES public.hx_agent_profiles(id) ON DELETE SET NULL;


--
-- Name: projects projects_coder_agent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_coder_agent_id_fkey FOREIGN KEY (coder_agent_id) REFERENCES public.hx_agent_profiles(id) ON DELETE SET NULL;


--
-- Name: projects projects_designer_agent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_designer_agent_id_fkey FOREIGN KEY (designer_agent_id) REFERENCES public.hx_agent_profiles(id) ON DELETE SET NULL;


--
-- Name: projects projects_memory_agent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_memory_agent_id_fkey FOREIGN KEY (memory_agent_id) REFERENCES public.hx_agent_profiles(id) ON DELETE SET NULL;


--
-- Name: projects projects_researcher_agent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_researcher_agent_id_fkey FOREIGN KEY (researcher_agent_id) REFERENCES public.hx_agent_profiles(id) ON DELETE SET NULL;


--
-- Name: projects projects_strategist_agent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_strategist_agent_id_fkey FOREIGN KEY (strategist_agent_id) REFERENCES public.hx_agent_profiles(id) ON DELETE SET NULL;


--
-- Name: requirement_insights requirement_insights_insight_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.requirement_insights
    ADD CONSTRAINT requirement_insights_insight_id_fkey FOREIGN KEY (insight_id) REFERENCES public.insights(id) ON DELETE CASCADE;


--
-- Name: requirement_insights requirement_insights_requirement_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.requirement_insights
    ADD CONSTRAINT requirement_insights_requirement_id_fkey FOREIGN KEY (requirement_id) REFERENCES public.requirements(id) ON DELETE CASCADE;


--
-- Name: requirements requirements_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.requirements
    ADD CONSTRAINT requirements_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- Name: routine_runs routine_runs_routine_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.routine_runs
    ADD CONSTRAINT routine_runs_routine_id_fkey FOREIGN KEY (routine_id) REFERENCES public.routines(id) ON DELETE CASCADE;


--
-- Name: routines routines_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.routines
    ADD CONSTRAINT routines_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- Name: sim_agent_profiles sim_agent_profiles_simulation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sim_agent_profiles
    ADD CONSTRAINT sim_agent_profiles_simulation_id_fkey FOREIGN KEY (simulation_id) REFERENCES public.simulations(id) ON DELETE CASCADE;


--
-- Name: sim_events sim_events_simulation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sim_events
    ADD CONSTRAINT sim_events_simulation_id_fkey FOREIGN KEY (simulation_id) REFERENCES public.simulations(id) ON DELETE CASCADE;


--
-- Name: sim_reports sim_reports_simulation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sim_reports
    ADD CONSTRAINT sim_reports_simulation_id_fkey FOREIGN KEY (simulation_id) REFERENCES public.simulations(id) ON DELETE CASCADE;


--
-- Name: sim_ticks sim_ticks_simulation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sim_ticks
    ADD CONSTRAINT sim_ticks_simulation_id_fkey FOREIGN KEY (simulation_id) REFERENCES public.simulations(id) ON DELETE CASCADE;


--
-- Name: simulations simulations_agent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.simulations
    ADD CONSTRAINT simulations_agent_id_fkey FOREIGN KEY (agent_id) REFERENCES public.hx_agent_profiles(id) ON DELETE SET NULL;


--
-- Name: source_chunks source_chunks_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.source_chunks
    ADD CONSTRAINT source_chunks_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- Name: source_chunks source_chunks_source_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.source_chunks
    ADD CONSTRAINT source_chunks_source_id_fkey FOREIGN KEY (source_id) REFERENCES public.sources(id) ON DELETE CASCADE;


--
-- Name: sources sources_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sources
    ADD CONSTRAINT sources_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- Name: strategies strategies_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strategies
    ADD CONSTRAINT strategies_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- Name: task_feedback task_feedback_task_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_feedback
    ADD CONSTRAINT task_feedback_task_id_fkey FOREIGN KEY (task_id) REFERENCES public.tasks(id) ON DELETE CASCADE;


--
-- Name: tasks tasks_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT tasks_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- Name: watch_targets watch_targets_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.watch_targets
    ADD CONSTRAINT watch_targets_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict OzBhP96lIjyieCISIZlmVX5pJjuXMAB099Drd37J4gi5X2ktKAorhTEBWTeueC5

INSERT INTO public."schema_migrations" (version) VALUES (20260306193000);
INSERT INTO public."schema_migrations" (version) VALUES (20260306195500);
INSERT INTO public."schema_migrations" (version) VALUES (20260306211000);
INSERT INTO public."schema_migrations" (version) VALUES (20260306214500);
INSERT INTO public."schema_migrations" (version) VALUES (20260306223000);
INSERT INTO public."schema_migrations" (version) VALUES (20260307003000);
INSERT INTO public."schema_migrations" (version) VALUES (20260307004500);
INSERT INTO public."schema_migrations" (version) VALUES (20260307005000);
INSERT INTO public."schema_migrations" (version) VALUES (20260307021000);
INSERT INTO public."schema_migrations" (version) VALUES (20260307030000);
INSERT INTO public."schema_migrations" (version) VALUES (20260307113000);
INSERT INTO public."schema_migrations" (version) VALUES (20260307121500);
INSERT INTO public."schema_migrations" (version) VALUES (20260308100000);
INSERT INTO public."schema_migrations" (version) VALUES (20260308110000);
INSERT INTO public."schema_migrations" (version) VALUES (20260308120000);
INSERT INTO public."schema_migrations" (version) VALUES (20260308133000);
INSERT INTO public."schema_migrations" (version) VALUES (20260308152000);
INSERT INTO public."schema_migrations" (version) VALUES (20260308160000);
INSERT INTO public."schema_migrations" (version) VALUES (20260309093000);
INSERT INTO public."schema_migrations" (version) VALUES (20260309113000);
INSERT INTO public."schema_migrations" (version) VALUES (20260309124500);
INSERT INTO public."schema_migrations" (version) VALUES (20260309141500);
INSERT INTO public."schema_migrations" (version) VALUES (20260309150000);
INSERT INTO public."schema_migrations" (version) VALUES (20260309163000);
INSERT INTO public."schema_migrations" (version) VALUES (20260309170000);
INSERT INTO public."schema_migrations" (version) VALUES (20260309174500);
INSERT INTO public."schema_migrations" (version) VALUES (20260311123000);
INSERT INTO public."schema_migrations" (version) VALUES (20260311150000);
INSERT INTO public."schema_migrations" (version) VALUES (20260315120000);
INSERT INTO public."schema_migrations" (version) VALUES (20260316090000);
INSERT INTO public."schema_migrations" (version) VALUES (20260326183000);
INSERT INTO public."schema_migrations" (version) VALUES (20260327100000);
INSERT INTO public."schema_migrations" (version) VALUES (20260327120000);
INSERT INTO public."schema_migrations" (version) VALUES (20260327130000);
INSERT INTO public."schema_migrations" (version) VALUES (20260327140000);
INSERT INTO public."schema_migrations" (version) VALUES (20260327150000);
INSERT INTO public."schema_migrations" (version) VALUES (20260327160000);
INSERT INTO public."schema_migrations" (version) VALUES (20260328100000);
INSERT INTO public."schema_migrations" (version) VALUES (20260331100000);
INSERT INTO public."schema_migrations" (version) VALUES (20260401100000);
INSERT INTO public."schema_migrations" (version) VALUES (20260409100000);
INSERT INTO public."schema_migrations" (version) VALUES (20260413120000);
INSERT INTO public."schema_migrations" (version) VALUES (20260413120100);
INSERT INTO public."schema_migrations" (version) VALUES (20260413140000);
INSERT INTO public."schema_migrations" (version) VALUES (20260413140100);
INSERT INTO public."schema_migrations" (version) VALUES (20260413140200);
INSERT INTO public."schema_migrations" (version) VALUES (20260413160000);
