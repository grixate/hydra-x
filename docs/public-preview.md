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
5. Review the tool policy section and decide whether HTTP fetches or shell commands should be enabled.
6. Use `/agents` or `mix hydra_x.agents` to verify the intended default agent and repair any workspace scaffold drift before going live.

## Telegram

1. Save the Telegram bot token and optional webhook secret on `/setup`.
2. Register the webhook from the UI or with `mix hydra_x.telegram.webhook register`.
3. Refresh webhook status from the UI or with `mix hydra_x.telegram.webhook sync`.
4. Confirm `/health` shows the expected webhook URL, pending update count, and no Telegram error.

## Scheduler

1. Open `/jobs` and confirm the default heartbeat and backup jobs exist.
2. Add any additional prompt jobs needed for preview operations.
3. If a job should report back to Telegram, enable delivery and set the target chat id before the first run.
4. Run each job once manually before relying on the recurring scheduler.
5. Use `mix hydra_x.jobs` to inspect the current schedule and `mix hydra_x.jobs run <id>` for CLI execution.

## Safety And Observability

1. Check `/health` for provider, Telegram, tool policy, scheduler, and recent safety events.
2. Open `/safety` or run `mix hydra_x.safety --level error` to review the latest operator-facing incidents directly.
3. Review the runtime counters section to confirm provider requests, tool executions, gateway deliveries, scheduler jobs, OTP alarms, and backup manifests are visible.
4. If outbound fetches should be restricted, set `HYDRA_X_HTTP_ALLOWLIST` or configure the persisted tool policy in `/setup`.
5. If shell access is not needed, disable it in `/setup`.

## Recovery

1. Back up `hydra_x_dev.db` and the agent workspace root together.
2. Prefer using `mix hydra_x.backup` or `./hydra_x backup` to create a timestamped archive.
3. Use `mix hydra_x.restore --archive <bundle> --target <dir>` to validate that bundles unpack cleanly before relying on them.
4. On restart, run `mix hydra_x.migrate` before bringing the node back online.
5. Re-run `./hydra_x healthcheck` after deploys or crashes.
6. Use `/conversations`, `/memory`, and `/jobs` to verify persisted state after recovery.
7. Use `/conversations` or `mix hydra_x.conversations retry-delivery <id>` to retry any failed Telegram delivery before clearing the incident.
