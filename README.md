# Hydra-X

Hydra-X is a self-hosted Elixir agent runtime with a Phoenix control plane. The current repository now includes the staged foundation plus a working multi-channel runtime for agents, channels, workers, cortex, compaction, typed memory, ingest, scheduler jobs, public Webchat, and operator-facing CLI/UI surfaces.

## What is implemented

- Phoenix + LiveView application with SQLite persistence
- Agent runtime supervision tree:
  `HydraX.Agent`, `Channel`, `Worker`, `Cortex`, `Compactor`, with persisted execution checkpoints for channel turns and replay-safe cached tool reuse during channel recovery
- Typed memory storage with SQLite FTS-backed search, hybrid-ranked recall, pluggable embeddings (local by default, OpenAI-compatible optional), and markdown export
- Structured bulletins:
  goals, todos, decisions, and context are prioritized into sectioned operator bulletins instead of a flat memory list
- Token-aware compaction:
  conversation compaction now reacts to both turn thresholds and estimated token pressure against the per-conversation budget, with soft/medium/hard trigger points at 80/90/95%
- Ingest pipeline for markdown, text, JSON, and PDF workspace content with archive tracking, restore-on-reimport, and provenance visibility
- Workspace scaffold contract:
  `SOUL.md`, `IDENTITY.md`, `USER.md`, `TOOLS.md`, `HEARTBEAT.md`, `memory/`, `skills/`, `ingest/`
- Workspace skills:
  agent-scoped discovery of `skills/<skill-name>/SKILL.md`, frontmatter metadata (`name`, `summary`, `version`, `tags`, `tools`, `channels`, `requires`), enable/disable controls in `/agents`, CLI inspection/export, planner hints, and prompt injection for enabled skills
- Skill tool:
  `skill_inspect` exposes enabled skills, versions, summaries, tags, tool hints, and channel hints to workers when they need to inspect available workspace workflows
- MCP registry:
  persisted stdio/HTTP MCP server definitions with setup UI, health probes, CLI management, agent-scoped enablement and binding inspection, operator-report export, and prompt visibility for enabled integrations
- MCP tools:
  `mcp_inspect`, `mcp_probe`, and `mcp_invoke` let workers inspect, actively probe, or invoke enabled MCP bindings before relying on them
- Stable behaviours:
  `HydraX.LLM.Provider`, `HydraX.Gateway.Adapter`, `HydraX.Tool`
- Provider adapters:
  OpenAI-compatible, Anthropic, and a built-in mock fallback
- Management UI routes:
  `/`, `/setup`, `/agents`, `/conversations`, `/memory`, `/jobs`, `/safety`, `/settings/providers`, `/health`
- Channel ingress:
  `/api/telegram/webhook`, `/api/discord/webhook`, and `/api/slack/webhook` route inbound updates into persisted channel conversations
- Budget guardrails:
  persisted token policies, preflight enforcement, usage accounting, and safety event logging
- Control-plane auth:
  session-based browser login once an operator password is configured on `/setup`, with recent-auth checks for sensitive actions and failed-login throttling
- Unified control policy:
  persisted recent-auth freshness, outbound interactive-delivery channels, job-delivery channels, and ingest-root restrictions with global defaults and per-agent overrides
- Guarded tools:
  workspace-confined file listing/reads/writes/targeted patch edits, dedicated web search, outbound HTTP fetches with basic SSRF checks, session-aware browser-style page fetch or link extraction or form/meta inspection or form-preview or submit or heading/table/image inspection or snapshot or extract flows, allowlisted shell commands, a persisted tool policy surface, and standardized tool summaries plus safety classifications in execution history
- Scheduler:
  recurring heartbeat/prompt/backup/ingest/maintenance jobs with persisted run history, CLI/UI controls, cron support, active-hour/timeout/retry/circuit controls, and optional Telegram/Discord/Slack/Webchat delivery-back
- Agent provider routing:
  per-agent provider defaults, process-specific overrides, fallback order, and warmup/readiness state surfaced in `/agents` and `/health`
- Provider adapter contract:
  explicit capabilities and healthcheck semantics for mock, OpenAI-compatible, and Anthropic providers
- Observability:
  telemetry counters for provider, tool, gateway, and scheduler activity surfaced in `/health`, plus a dedicated `/safety` ledger for operator review and exportable report bundles with agent snapshots, incidents, and audit events
- Operator commands:
  `mix hydra_x.new`, `mix hydra_x.serve`, `mix hydra_x.chat`, `mix hydra_x.migrate`, `mix hydra_x.healthcheck`, `mix hydra_x.telegram.webhook`, `mix hydra_x.providers.test`, `mix hydra_x.agents`, `mix hydra_x.jobs`, `mix hydra_x.conversations`, `mix hydra_x.safety`, `mix hydra_x.backup`, `mix hydra_x.restore`, `mix hydra_x.doctor`, `mix hydra_x.install`, `mix hydra_x.report`, `mix hydra_x.mcp`

## Quick start

```bash
mix setup
mix hydra_x.migrate
mix hydra_x.serve
```

Open [http://localhost:4000](http://localhost:4000), go to `/setup`, configure an agent and optionally a provider, then run a one-shot chat:

```bash
mix hydra_x.chat -m "Remember that Hydra-X is bootable."
mix hydra_x.chat -m "What do you remember about Hydra-X?"
```

To enable Telegram, configure the bot token on `/setup`, then set the Telegram webhook to:

```text
https://<your-host>/api/telegram/webhook
```

You can inspect or register the webhook from the CLI:

```bash
mix hydra_x.telegram.webhook
mix hydra_x.telegram.webhook register
mix hydra_x.telegram.webhook sync
mix hydra_x.telegram.webhook delete
mix hydra_x.telegram.webhook test 4242 "Hydra-X smoke test"
```

The repository also includes a thin command wrapper:

```bash
./hydra_x healthcheck
./hydra_x chat -m "Hello"
./hydra_x provider-test
./hydra_x providers
./hydra_x agents
./hydra_x skills 1 --refresh
./hydra_x skills 1 --show 3
./hydra_x skills 1 --export tmp/skills
./hydra_x ingest
./hydra_x jobs
./hydra_x conversations
./hydra_x budget
./hydra_x safety
./hydra_x backup
./hydra_x restore /path/to/hydra-x-backup.tar.gz
./hydra_x doctor
./hydra_x install
./hydra_x report
./hydra_x mcp
```

If you want to lock the management UI, set an operator password on `/setup`. After that, browser access requires signing in at `/login`, and repeated failed sign-in attempts from the same IP are temporarily blocked by the login throttle window.

Persisted provider keys and channel tokens are encrypted at rest by default. You can also store an environment-backed reference instead of a secret value by saving `env:YOUR_ENV_VAR_NAME` in the UI or CLI; Hydra-X persists only the env reference and resolves the real secret at runtime. Set `HYDRA_X_SECRET_KEY` in production so Hydra-X uses an explicit runtime secret instead of the endpoint fallback key, and check `/health` for any remaining plaintext or unresolved env-backed records.

MCP servers can be managed from `/setup` or the CLI:

```bash
mix hydra_x.mcp
mix hydra_x.mcp save --name "Docs MCP" --transport stdio --command cat
mix hydra_x.mcp save --name "Remote MCP" --transport http --url https://mcp.example.test --healthcheck_path /health
mix hydra_x.mcp test 1
mix hydra_x.mcp refresh-bindings hydra-primary
mix hydra_x.mcp bindings hydra-primary
mix hydra_x.mcp invoke hydra-primary search_docs --server Remote --json '{"query":"hydra"}'
mix hydra_x.mcp delete 1
```

Use `mix hydra_x.agents mcp <agent_id> --refresh` to bind the current MCP registry into a specific agent, then `--enable <binding_id>` or `--disable <binding_id>` to tune that agent’s MCP surface. The dedicated `mix hydra_x.mcp bindings <agent>` view exposes per-agent MCP binding health from the registry side as well. Enabled MCP integrations are surfaced in the system prompt under `## MCP Integrations`, `/health` now shows bound MCP status per agent, and report bundles now include both `mcp.json` and `agent_mcp.json`.

Provider lifecycle can be managed from `/settings/providers` or the CLI:

```bash
mix hydra_x.providers
mix hydra_x.providers activate 2
mix hydra_x.providers toggle 2
mix hydra_x.providers delete 2
mix hydra_x.providers.test
```

Agent lifecycle can be managed from `/agents` or the CLI:

```bash
mix hydra_x.agents
mix hydra_x.agents start 2
mix hydra_x.agents restart 2
mix hydra_x.agents stop 2
mix hydra_x.agents reconcile
mix hydra_x.agents default 2
mix hydra_x.agents repair 2
mix hydra_x.agents toggle 2
mix hydra_x.agents bulletin 2
mix hydra_x.agents compaction 2
mix hydra_x.agents compaction 2 --soft 8 --medium 12 --hard 16
mix hydra_x.agents provider-routing 2
mix hydra_x.agents provider-routing 2 --default-provider 4 --fallbacks 5,6
mix hydra_x.agents warmup 2
mix hydra_x.agents skills 2 --refresh
mix hydra_x.agents skills 2 --show 5
mix hydra_x.agents skills 2 --export tmp/skills
mix hydra_x.agents tool-policy 2
mix hydra_x.agents tool-policy 2 --workspace-write true --web-search false --shell false
mix hydra_x.agents tool-policy 2 --reset
mix hydra_x.agents control-policy 2
mix hydra_x.agents control-policy 2 --recent-auth-minutes 5 --interactive-channels cli,webchat --job-delivery-channels discord
mix hydra_x.agents control-policy 2 --reset
```

Typed memory can now be curated from `/memory` or the CLI:

```bash
mix hydra_x.memory
mix hydra_x.memory --type Fact --search "operator" --min_importance 0.8
mix hydra_x.memory --status superseded
mix hydra_x.memory create Fact "Hydra-X stores typed memory."
mix hydra_x.memory update 12 "Hydra-X stores curated typed memory."
mix hydra_x.memory link 12 13 supports
mix hydra_x.memory merge 12 13 --content "Merged canonical memory"
mix hydra_x.memory supersede 14 13
mix hydra_x.memory conflict 15 16 --reason "Operator guidance disagrees"
mix hydra_x.memory resolve 15 16 --content "Canonical memory after review" --note "Conflict resolved"
mix hydra_x.memory unlink 9
mix hydra_x.memory delete 12
mix hydra_x.memory sync
```

Ingest-backed workspace files can now be managed from `/memory` or the CLI:

```bash
mix hydra_x.ingest --agent hydra-primary
mix hydra_x.ingest import ops.md --agent hydra-primary
mix hydra_x.ingest history --agent hydra-primary
mix hydra_x.ingest history --agent hydra-primary --file ops.md
mix hydra_x.ingest archive ops.md --agent hydra-primary
```

`/memory` now exposes source provenance for ingest-backed memories, including source file/path, section metadata, content/document hashes, and the recent ingest runs for the same file.

Recurring heartbeat, prompt, backup, ingest, and maintenance jobs are managed from `/jobs` or the CLI:

```bash
mix hydra_x.jobs
mix hydra_x.jobs --kind prompt --enabled true --search workspace
mix hydra_x.jobs create --name "Standup digest" --kind prompt --schedule "daily 09:30"
mix hydra_x.jobs create --name "Morning review" --kind prompt --schedule_mode daily --run_hour 6 --run_minute 30
mix hydra_x.jobs create --name "Weekly review" --kind prompt --schedule_mode weekly --weekday_csv mon,fri --run_hour 8 --run_minute 15
mix hydra_x.jobs create --name "Ingest sweep" --kind ingest --schedule_mode interval --interval_minutes 30
mix hydra_x.jobs create --name "Maintenance sweep" --kind maintenance --schedule_mode daily --run_hour 2 --run_minute 0
mix hydra_x.jobs update 12 --timeout_seconds 45 --retry_limit 2 --retry_backoff_seconds 5 --pause_after_failures 3 --cooldown_minutes 30
mix hydra_x.jobs reset-circuit 12
mix hydra_x.jobs update 12 --enabled false --weekday_csv wed --run_hour 9 --run_minute 0
mix hydra_x.jobs run 1
mix hydra_x.jobs runs --status success --kind backup --search review
mix hydra_x.jobs export-runs --status error --output tmp/reports
mix hydra_x.jobs delete 1
```

Jobs now support fixed intervals plus daily, weekly, and cron UTC schedules, and the UI/CLI also accept natural schedule text such as `every 2 hours`, `daily 09:30`, `weekly mon,fri 08:15`, or `cron 0 9 * * 1-5`, which is normalized into the persisted schedule fields. They also support timeout, retry, active-hour, retention, and cooldown-based circuit settings from `/jobs` or the CLI. `ingest` jobs process supported files from the agent workspace `ingest/` directory, and `maintenance` jobs prune old run history, refresh the agent bulletin, and export a fresh operator report snapshot. Scheduled delivery-back now also respects the persisted control policy, so operators can allow or block delivery channels without changing job definitions.

Discord, Slack, and Webchat can now be configured from `/setup` as well, and scheduled jobs can deliver to those channels using the same delivery controls.

Webchat is exposed publicly at `/webchat` and uses a session-backed browser conversation mapped into the same agent runtime as the other channels.

Failed Telegram deliveries can be retried from `/conversations` or the CLI:

```bash
mix hydra_x.conversations
mix hydra_x.conversations retry-delivery 42
```

The conversations surface can also start control-plane conversations and send replies from either the UI or the CLI:

```bash
mix hydra_x.conversations start "Summarize the current workspace." --title "Ops Chat"
mix hydra_x.conversations send 42 "What do you remember?"
mix hydra_x.conversations --status archived --search "Ops"
mix hydra_x.conversations export 42
mix hydra_x.conversations archive 42
mix hydra_x.conversations compact 42
mix hydra_x.conversations reset-compact 42

`/conversations` now also shows the latest persisted channel execution checkpoint for each selected thread, including the planned turn mode, suggested tools, executed tool summaries, and final provider status.
```

Recent safety events and operator action audits can be reviewed from `/safety` or the CLI:

```bash
mix hydra_x.safety
mix hydra_x.safety --level error --category gateway --limit 20
mix hydra_x.safety acknowledge 7 --note "triaged"
mix hydra_x.safety resolve 7 --note "delivery restored"
```

Budget policy can be inspected and updated from `/budget` or the CLI:

```bash
mix hydra_x.budget
mix hydra_x.budget --agent hydra-primary --daily-limit 30000 --conversation-limit 6000 --hard-limit-action warn
```

Backup archives can be produced with:

```bash
mix hydra_x.backup
mix hydra_x.backup --output /var/backups/hydra-x
```

Portable restore bundles can be unpacked into a clean target directory with:

```bash
mix hydra_x.restore /var/backups/hydra-x/hydra-x-backup-20260307-010000.tar.gz
mix hydra_x.restore --archive /var/backups/hydra-x/hydra-x-backup-20260307-010000.tar.gz --target ./restore-staging
mix hydra_x.restore --verify --archive /var/backups/hydra-x/hydra-x-backup-20260307-010000.tar.gz
```

Deployment templates can be exported with:

```bash
mix hydra_x.install
mix hydra_x.install --output ./deploy
```

Operator reports can be exported in markdown and JSON with:

```bash
mix hydra_x.report
mix hydra_x.report --required-only --only-warn --search telegram
```

The health page also shows active OTP alarms and the latest backup manifests so recovery state is visible without shell access.
The setup page now includes a preview-readiness preflight, and the CLI equivalent is `mix hydra_x.doctor`.
The health page can also export a full operator report directly from the UI.
The setup page can also export the install bundle and create a backup bundle directly from the UI.
`mix hydra_x.healthcheck --only-warn --search backup`, `mix hydra_x.doctor --required-only --only-warn`, and `mix hydra_x.report --required-only --only-warn` can now narrow those reports to just the failing sections you care about.

## Project shape

Key runtime areas:

- `lib/hydra_x/runtime.ex`: thin facade over the runtime domains
- `lib/hydra_x/agent/`: supervised agent processes
- `lib/hydra_x/memory/`: typed memory and markdown rendering
- `lib/hydra_x/ingest/`: ingest parser, pipeline, and watcher
- `lib/hydra_x/budget/`: budget policy and usage accounting
- `lib/hydra_x/safety/`: safety event logging
- `lib/hydra_x/tools/`: guarded tool implementations
- `lib/hydra_x/telemetry/`: in-process observability aggregation
- `lib/hydra_x/llm/`: provider routing and adapters
- `lib/hydra_x_web/live/`: management UI pages
- `workspace_template/`: scaffolded workspace contract
- `docs/public-preview.md`: preview deployment and recovery checklist
- `docs/capability-matrix.md`: current-vs-target capability map

## Verification

Verified locally with:

```bash
mix compile --warnings-as-errors
mix test
mix hydra_x.migrate
./hydra_x healthcheck
mix hydra_x.serve
```

## Current scope

This is not the full roadmap yet. The repo now has a working multi-channel monolith with ingest, hybrid recall, cron scheduling, operator reporting, public Webchat, targeted workspace patch tooling, richer browser-style automation with structured headings, scripts, metadata, and tables, encrypted or env-backed secrets, unified cross-cutting control policy, installable workspace skills with richer manifests and exportable catalogs, an MCP registry layer with worker-visible inspect/probe/invoke tools plus CLI invoke flows, channel-native reply/thread handling with chunk-safe outbound previews, resumable execution checkpoints with replay-safe tool caching, and node-aware cluster posture reporting. Real browser-backed rendering and true multi-node clustering remain future stages.
