# Hydra-X

Hydra-X is a self-hosted Elixir agent runtime with a Phoenix control plane. This repository now includes the Stage 0 foundation from the roadmap plus a working runtime skeleton for agents, channels, workers, cortex, compaction, typed memory, and operator-facing CLI/UI surfaces.

## What is implemented

- Phoenix + LiveView application with SQLite persistence
- Agent runtime supervision tree:
  `HydraX.Agent`, `Channel`, `Branch`, `Worker`, `Cortex`, `Compactor`
- Typed memory storage with SQLite FTS-backed search and markdown export
- Workspace scaffold contract:
  `SOUL.md`, `IDENTITY.md`, `USER.md`, `TOOLS.md`, `HEARTBEAT.md`, `memory/`, `skills/`, `ingest/`
- Stable behaviours:
  `HydraX.LLM.Provider`, `HydraX.Gateway.Adapter`, `HydraX.Tool`
- Provider adapters:
  OpenAI-compatible, Anthropic, and a built-in mock fallback
- Management UI routes:
  `/`, `/setup`, `/agents`, `/conversations`, `/memory`, `/jobs`, `/safety`, `/settings/providers`, `/health`
- Telegram ingress:
  `/api/telegram/webhook` routes inbound updates into persisted channel conversations
- Budget guardrails:
  persisted token policies, preflight enforcement, usage accounting, and safety event logging
- Control-plane auth:
  session-based browser login once an operator password is configured on `/setup`
- Guarded tools:
  workspace-confined file reads, outbound HTTP fetches with basic SSRF checks, allowlisted shell commands, and a persisted tool policy surface
- Scheduler:
  recurring heartbeat/prompt/backup jobs with persisted run history, CLI/UI controls, and optional Telegram delivery-back
- Observability:
  telemetry counters for provider, tool, gateway, and scheduler activity surfaced in `/health`, plus a dedicated `/safety` ledger for operator review
- Operator commands:
  `mix hydra_x.new`, `mix hydra_x.serve`, `mix hydra_x.chat`, `mix hydra_x.migrate`, `mix hydra_x.healthcheck`, `mix hydra_x.telegram.webhook`, `mix hydra_x.providers.test`, `mix hydra_x.agents`, `mix hydra_x.jobs`, `mix hydra_x.conversations`, `mix hydra_x.safety`, `mix hydra_x.backup`, `mix hydra_x.restore`, `mix hydra_x.doctor`, `mix hydra_x.install`

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
./hydra_x jobs
./hydra_x conversations
./hydra_x budget
./hydra_x safety
./hydra_x backup
./hydra_x restore /path/to/hydra-x-backup.tar.gz
./hydra_x doctor
./hydra_x install
```

If you want to lock the management UI, set an operator password on `/setup`. After that, browser access requires signing in at `/login`.

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
mix hydra_x.memory unlink 9
mix hydra_x.memory delete 12
mix hydra_x.memory sync
```

Recurring heartbeat, prompt, and backup jobs are managed from `/jobs` or the CLI:

```bash
mix hydra_x.jobs
mix hydra_x.jobs --kind prompt --enabled true --search workspace
mix hydra_x.jobs run 1
mix hydra_x.jobs delete 1
```

Jobs can optionally deliver their run output back to Telegram by enabling `Deliver result` and setting a chat id target on `/jobs`.

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
```

Deployment templates can be exported with:

```bash
mix hydra_x.install
mix hydra_x.install --output ./deploy
```

The health page also shows active OTP alarms and the latest backup manifests so recovery state is visible without shell access.
The setup page now includes a preview-readiness preflight, and the CLI equivalent is `mix hydra_x.doctor`.
The setup page can also export the install bundle and create a backup bundle directly from the UI.
`mix hydra_x.healthcheck --only-warn --search backup` and `mix hydra_x.doctor --required-only --only-warn` can now narrow those reports to just the failing sections you care about.

## Project shape

Key runtime areas:

- `lib/hydra_x/runtime.ex`: persistence and orchestration helpers
- `lib/hydra_x/agent/`: supervised agent processes
- `lib/hydra_x/memory/`: typed memory and markdown rendering
- `lib/hydra_x/budget/`: budget policy and usage accounting
- `lib/hydra_x/safety/`: safety event logging
- `lib/hydra_x/tools/`: guarded tool implementations
- `lib/hydra_x/telemetry/`: in-process observability aggregation
- `lib/hydra_x/llm/`: provider routing and adapters
- `lib/hydra_x_web/live/`: management UI pages
- `workspace_template/`: scaffolded workspace contract
- `docs/public-preview.md`: preview deployment and recovery checklist

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

This is not the full roadmap yet. The repo now has the bootable foundation and a working end-to-end mock/runtime flow. Telegram polling, richer UI workflows, cron, and clustering are still future stages.
