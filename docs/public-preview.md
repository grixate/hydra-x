# Hydra-X Public Preview Checklist

This repository is now beyond the initial skeleton. Use this checklist before exposing a node to external operators or Telegram traffic.

## Boot

1. Copy [.env.example](/Users/grigorymikhailov/Documents/hydra-x/.env.example) into your local environment and set `HYDRA_X_PUBLIC_URL` correctly.
2. Run `mix deps.get`.
3. Run `mix hydra_x.migrate`.
4. Start the node with `mix hydra_x.serve`.
5. Export a deployment template with `mix hydra_x.install --output ./deploy`.

## Control Plane

1. Open [http://localhost:4000/setup](http://localhost:4000/setup).
2. Save the default agent and confirm its workspace root.
3. Set an operator password before exposing the app beyond localhost.
4. Configure the primary provider or stay on the mock fallback for dry-runs.
5. Use `/settings/providers` or `mix hydra_x.providers` to edit, activate, test, and remove provider configs before exposing live traffic.
6. Review the tool policy section and decide whether HTTP fetches or shell commands should be enabled.
7. Use `/agents` or `mix hydra_x.agents` to verify the intended default agent, confirm the runtime is actually up for each active agent, repair any workspace scaffold drift, and refresh the bulletin for each operator-facing agent before going live.
8. Use `/conversations` or `mix hydra_x.conversations start ...` to confirm the control plane can run a real operator-driven chat before exposing external channels.
9. Use the conversations filters to confirm archived threads, Telegram threads, and active control-plane threads can be triaged quickly once the list grows.
10. Export one transcript, review one compaction summary, tune one agent compaction policy from `/agents` or `mix hydra_x.agents compaction ...`, and archive one completed thread from `/conversations` or `mix hydra_x.conversations export|compact|archive ...` to verify operator lifecycle workflows before preview.
11. Use `/memory` or `mix hydra_x.memory` to verify that critical operator facts, goals, and decisions can be curated, filtered, reconciled, marked as conflicted, resolved, deleted, and synced back into the workspace markdown view.

## Telegram

1. Save the Telegram bot token and optional webhook secret on `/setup`.
2. Register the webhook from the UI or with `mix hydra_x.telegram.webhook register`.
3. Refresh webhook status from the UI or with `mix hydra_x.telegram.webhook sync`.
4. Send a Telegram smoke test from `/setup` or with `mix hydra_x.telegram.webhook test <chat_id> "<message>"`.
5. Confirm `/health` shows the expected webhook URL, pending update count, and no Telegram error.

## Scheduler

1. Open `/jobs` and confirm the default heartbeat and backup jobs exist.
2. Add any additional prompt jobs needed for preview operations, using interval, daily, or weekly UTC schedules depending on the operational cadence.
3. If a job should report back to Telegram, enable delivery and set the target chat id before the first run.
4. Run each job once manually before relying on the recurring scheduler.
5. Use the jobs filters or `mix hydra_x.jobs --kind ... --enabled ...` to inspect only the relevant schedule slice, `mix hydra_x.jobs create|update ...` for CLI schedule management, and `mix hydra_x.jobs run <id>` for CLI execution.

## Safety And Observability

1. Check `/health` for provider, Telegram, tool policy, scheduler, and recent safety events.
2. Export one operator report from `/health` or `mix hydra_x.report` so you have a portable markdown/JSON runtime snapshot before opening preview traffic.
3. Open `/safety` or run `mix hydra_x.safety --level error` to review the latest operator-facing incidents and recent control-plane audit actions directly, then acknowledge or resolve anything already triaged.
4. Review the runtime counters section to confirm provider requests, tool executions, gateway deliveries, scheduler jobs, OTP alarms, and backup manifests are visible.
5. If outbound fetches should be restricted, set `HYDRA_X_HTTP_ALLOWLIST` or configure the persisted tool policy in `/setup`.
6. If shell access is not needed, disable it in `/setup`.
7. Open `/budget` or run `mix hydra_x.budget` to confirm the active agent has the intended hard-limit action and token ceilings before preview traffic starts.

## Recovery

1. Back up `hydra_x_dev.db` and the agent workspace root together.
2. Prefer using `mix hydra_x.backup` or `./hydra_x backup` to create a timestamped archive.
3. Use `mix hydra_x.restore --archive <bundle> --target <dir>` to validate that bundles unpack cleanly before relying on them.
4. On restart, run `mix hydra_x.migrate` before bringing the node back online.
5. Re-run `./hydra_x healthcheck` after deploys or crashes.
6. Use `mix hydra_x.healthcheck --only-warn` and `mix hydra_x.doctor --required-only --only-warn` when you want just the unresolved blockers instead of the full report.
7. Use `mix hydra_x.report --required-only --only-warn` after recovery when you want a portable operator snapshot to attach to the incident or deploy notes.
8. Use `/conversations`, `/memory`, and `/jobs` to verify persisted state after recovery.
9. Use `/conversations` or `mix hydra_x.conversations retry-delivery <id>` to retry any failed Telegram delivery before clearing the incident.
