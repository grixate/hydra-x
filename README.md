# Hydra-X

Hydra-X is a self-hosted agent runtime built in Elixir with a Phoenix control plane.

It is designed for teams that want agents to be durable, inspectable, policy-governed, and easy to operate, not just easy to demo.

## Why Hydra-X

Most agent systems optimize for raw capability first and operational discipline second. Hydra-X is built the other way around.

It gives you:

- **Powerful architecture** based on OTP supervision, persisted runtime state, resumable work items, multi-channel hx_conversations, typed memory, scheduler jobs, and operator-facing control surfaces
- **Security by default** with encrypted secrets, operator auth, tool guardrails, channel and delivery policy, recent-auth checks, budget enforcement, and safety-event auditing
- **Monitoring and operator visibility** through `/health`, `/safety`, report bundles, scheduler history, runtime telemetry, and CLI inspection tools
- **Operational simplicity** through a single Phoenix app, SQLite-first local setup, browser-based configuration, and a consistent CLI for day-to-day control

## What Hydra-X Is Good At

Hydra-X is strong when you need agents that:

- run for longer than a single request
- survive restarts and recover work safely
- operate across channels like Telegram, Slack, Discord, CLI, and Webchat
- keep durable memory and workspace context
- expose clear operator controls instead of hiding decisions in a black box
- can be constrained by policy, budget, capability, and delivery rules

This is not just a chat wrapper. It is a runtime with a control plane.

## Architecture

Hydra-X is built around a durable agent runtime rather than a stateless prompt loop.

Core architectural strengths:

- **OTP-native supervision**
  Agents, channels, workers, memory, scheduler, and control-plane services run inside a supervised Elixir application
- **Persisted runtime state**
  Conversations, work items, scheduler runs, safety events, memory, delivery attempts, and operator actions are persisted and queryable
- **Resumable execution**
  Channel hx_checkpoints, work-item replay, lease-backed ownership, and recovery-aware follow-ups let Hydra-X resume work instead of starting over
- **Separation of concerns**
  Providers, gateways, tools, and MCP integrations all sit behind explicit runtime contracts
- **Unified control plane**
  The browser UI and CLI operate on the same persisted model instead of separate hidden control paths

### Runtime model

At a high level, Hydra-X works like this:

1. An agent receives input from a channel, job, CLI, or operator action.
2. The runtime records the conversation/work state and evaluates policy, memory, and available capabilities.
3. The agent executes through guarded tools, provider routing, and scheduler-backed workflows.
4. Results, follow-ups, memory, delivery attempts, and safety events are persisted for later inspection or recovery.

That architecture is what makes the system observable and recoverable under real load.

## Security

Security is a first-class part of the product shape, not an afterthought.

Hydra-X includes:

- **Encrypted secrets at rest**
  Provider keys and channel tokens are encrypted by default
- **Environment-backed secret references**
  You can store `env:YOUR_VAR` references instead of raw secrets
- **Operator authentication**
  Browser login, recent-auth checks for sensitive actions, and failed-login throttling
- **Tool confinement**
  Workspace-scoped file access, guarded shell execution, SSRF-aware HTTP rules, and explicit tool policy controls
- **Budget and policy guardrails**
  Token budgets, control policy, delivery restrictions, and safety classifications on tool execution
- **Safety audit trail**
  `/safety` and exported reports provide a reviewable ledger of incidents, warnings, and operator actions

This gives you a safer operating model for agents that can actually act, not just respond.

## Monitoring and Operations

Hydra-X is built to be run, monitored, and debugged by humans.

Operational visibility includes:

- **`/health`**
  Runtime posture for providers, channels, jobs, MCP, worker pressure, autonomy state, and recovery behavior
- **`/safety`**
  Safety events, operator acknowledgements, and incident review
- **Report bundles**
  Exportable snapshots for agents, work items, MCP bindings, incidents, and runtime posture
- **Scheduler history**
  Run history, retries, cooldowns, and circuit-style behavior for recurring jobs
- **Telemetry**
  Provider, tool, gateway, and scheduler counters surfaced in the control plane
- **CLI parity**
  Most important operational actions are also available from `mix` tasks and the `./hydra_x` wrapper

Hydra-X tries to make the runtime explain itself:

- why a recovery path was chosen
- what was deferred
- which policies blocked execution
- what the current delivery posture is
- whether the system is under intervention pressure or just carrying stale backlog

## Simplicity

Hydra-X takes a pragmatic approach to self-hosting.

You do not need a sprawling distributed stack to get started:

- one Phoenix application
- SQLite-first local setup
- browser-based `/setup`
- consistent CLI commands
- built-in scheduler
- built-in control-plane UI

That makes it useful for local development, single-node deployment, and gradual operational hardening.

It is designed so you can start simple and add complexity only when you need it.

## Included Capabilities

Hydra-X already includes a substantial runtime surface:

- multi-channel hx_conversations for CLI, Telegram, Slack, Discord, and Webchat
- typed memory with search, ranking, and export
- ingest pipeline for workspace documents
- recurring jobs for prompts, ingest, maintenance, and backups
- provider routing with health and fallback behavior
- workspace skills and MCP registry/invocation
- delivery controls for interactive and scheduled channels
- operator UI for agents, hx_conversations, memory, jobs, safety, providers, and health

## Quick Start

```bash
mix setup
mix hydra_x.migrate
mix hydra_x.serve
```

Open [http://localhost:4000](http://localhost:4000), complete `/setup`, create or configure an agent, and then try:

```bash
mix hydra_x.chat -m "Remember that Hydra-X is bootable."
mix hydra_x.chat -m "What do you remember about Hydra-X?"
```

You can also use the wrapper script:

```bash
./hydra_x healthcheck
./hydra_x chat -m "Hello"
./hydra_x agents
./hydra_x jobs
./hydra_x safety
./hydra_x report
```

## Main Control Surfaces

Browser UI:

- `/setup`
- `/agents`
- `/hx_conversations`
- `/memory`
- `/jobs`
- `/safety`
- `/settings/providers`
- `/health`

Key CLI surfaces:

- `mix hydra_x.chat`
- `mix hydra_x.agents`
- `mix hydra_x.jobs`
- `mix hydra_x.hx_conversations`
- `mix hydra_x.memory`
- `mix hydra_x.safety`
- `mix hydra_x.report`
- `mix hydra_x.mcp`

## Channel and Delivery Support

Hydra-X supports inbound and operator-controlled workflows across:

- CLI
- Telegram
- Slack
- Discord
- Webchat

Channel ingress is persisted, delivery attempts are tracked, and retries or failures are visible from the control plane.

## Production Deployment

### Operating Modes

Hydra-X operates in two modes:

- **Local single-node** (default): SQLite, single process. Suitable for development and small deployments.
- **Production multi-node**: PostgreSQL, OTP clustering. Suitable for production workloads with durability and multi-node coordination.

Run `mix hydra_x.deploy mode` to see the current operating mode.

### Migration from Local to Production

1. Configure PostgreSQL: set `DATABASE_URL` and run `mix hydra_x.migrate`
2. Set `SECRET_KEY_BASE` (generate with `mix phx.gen.secret`)
3. Set `HYDRA_X_SECRET_KEY` for at-rest encryption of provider keys and tokens
4. Configure `PHX_HOST` to your production domain
5. Set `PHX_SERVER=true` to enable the HTTP endpoint
6. Configure an operator password via `/setup`
7. Optionally enable clustering: set `HYDRA_CLUSTER_ENABLED=true` (requires PostgreSQL)
8. Run `mix hydra_x.deploy check` to verify all requirements

### Secrets

- `HYDRA_X_SECRET_KEY`: AES-256-GCM encryption key for provider tokens, MCP auth, and channel secrets
- Use `envref:v1:VAR_NAME` references to resolve secrets from environment variables at runtime
- Review `/health` for unresolved secret posture or delivery problems

### Operator Access

Configure the operator password on `/setup` and use the login flow at `/login` to lock down the management UI.

### Observability

- `/health` for runtime health, readiness, and deployment posture
- `mix hydra_x.report` for detailed runtime snapshots (markdown + JSON)
- `mix hydra_x.deploy check` for production readiness checklist
- Telemetry events for provider calls, tool execution, and gateway delivery

## Status

Hydra-X already has strong foundations for:

- durable agent execution
- policy-governed autonomy
- security and operator control
- runtime observability
- simple self-hosted deployment

The project is especially strong if you care about how agent systems behave in production, not just how they look in a benchmark.

## Philosophy

Hydra-X is built around a simple idea:

**agent systems should be recoverable, inspectable, secure, and boring to operate.**

Capability matters. But in real systems, architecture, safety, monitoring, and simplicity matter just as much.
