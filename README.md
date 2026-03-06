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
  `/`, `/setup`, `/agents`, `/conversations`, `/memory`, `/settings/providers`, `/health`
- Telegram ingress:
  `/api/telegram/webhook` routes inbound updates into persisted channel conversations
- Operator commands:
  `mix hydra_x.new`, `mix hydra_x.serve`, `mix hydra_x.chat`, `mix hydra_x.migrate`, `mix hydra_x.healthcheck`, `mix hydra_x.telegram.webhook`

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
```

The repository also includes a thin command wrapper:

```bash
./hydra_x healthcheck
./hydra_x chat -m "Hello"
```

## Project shape

Key runtime areas:

- `lib/hydra_x/runtime.ex`: persistence and orchestration helpers
- `lib/hydra_x/agent/`: supervised agent processes
- `lib/hydra_x/memory/`: typed memory and markdown rendering
- `lib/hydra_x/llm/`: provider routing and adapters
- `lib/hydra_x_web/live/`: management UI pages
- `workspace_template/`: scaffolded workspace contract

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

This is not the full roadmap yet. The repo now has the bootable foundation and a working end-to-end mock/runtime flow. Dangerous tools, auth, Telegram polling, richer UI workflows, budgets, cron, and clustering are still future stages.
