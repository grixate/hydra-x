# Hydra-X Public Preview Checklist

This repository is now beyond the initial skeleton. Use this checklist before exposing a node to external operators or external channel traffic.

## Boot

1. Copy [.env.example](/Users/grigorymikhailov/Documents/hydra-x/.env.example) into your local environment and set `HYDRA_X_PUBLIC_URL` correctly.
2. Set `HYDRA_X_SECRET_KEY` to a long random secret so persisted provider and channel credentials are encrypted at rest with an explicit runtime key.
3. Run `mix deps.get`.
4. Run `mix hydra_x.migrate`.
5. Start the node with `mix hydra_x.serve`.
6. Export a deployment template with `mix hydra_x.install --output ./deploy`.

## Control Plane

1. Open [http://localhost:4000/setup](http://localhost:4000/setup).
2. Save the default agent and confirm its workspace root.
3. Set an operator password before exposing the app beyond localhost.
4. Confirm the login throttle policy on `/login` and `/health`, then verify sensitive setup actions still require recent re-auth after signing in.
5. Configure the primary provider or stay on the mock fallback for dry-runs.
6. Use `/settings/providers` or `mix hydra_x.providers` to edit, activate, test, and remove provider configs before exposing live traffic.
7. Use `/setup` or `mix hydra_x.mcp` to register any stdio or HTTP MCP servers you expect the node to rely on, then run at least one probe.
8. Use `/agents` or `mix hydra_x.agents mcp <agent_id> --refresh` to bind the relevant MCP servers into each exposed agent and disable any integration that should stay out of that agent's prompt. Use `mix hydra_x.mcp bindings <agent>` if you want the same binding view from the registry side.
9. Review the tool policy section and decide whether workspace writes/patches, dedicated web search, HTTP fetches, browser automation, or shell commands should be enabled.
10. Review the control policy section and confirm the recent-auth window, interactive delivery channels, scheduled-job delivery channels, and allowed ingest roots match the intended preview exposure.
11. Use `/agents` or `mix hydra_x.agents` to verify the intended default agent, confirm the runtime is actually up for each active agent, repair any workspace scaffold drift, refresh the bulletin, warm the agent provider route, and inspect any agent-specific tool or control policy overrides before going live.
12. Use `/conversations` or `mix hydra_x.conversations start ...` to confirm the control plane can run a real operator-driven chat before exposing external channels.
13. Use the conversations filters to confirm archived threads, Telegram threads, and active control-plane threads can be triaged quickly once the list grows.
14. Export one transcript, review one compaction summary, inspect one execution checkpoint, tune one agent compaction policy from `/agents` or `mix hydra_x.agents compaction ...`, and archive one completed thread from `/conversations` or `mix hydra_x.conversations export|compact|archive ...` to verify operator lifecycle workflows before preview.
15. Use `/memory` or `mix hydra_x.memory` to verify that critical operator facts, goals, and decisions can be curated, filtered, reconciled, marked as conflicted, resolved, deleted, and synced back into the workspace markdown view.
16. Use `/memory` or `mix hydra_x.ingest` to manually ingest at least one file from the workspace `ingest/` directory and verify it appears in both the ingest-backed file list and the recent ingest history.
17. Confirm a file outside the allowed ingest roots is rejected until the control policy is updated, then re-run ingest to verify the guardrail is intentional rather than accidental.
18. Select one ingest-backed memory and confirm `/memory` shows its provenance details and recent ingest runs for the same source file.

## External Channels

1. Save the Telegram, Discord, Slack, and Webchat settings you intend to use on `/setup`.
2. For Telegram, register the webhook from the UI or with `mix hydra_x.telegram.webhook register`.
3. For Telegram, refresh webhook status from the UI or with `mix hydra_x.telegram.webhook sync`.
4. Send at least one smoke test for each enabled channel from `/setup`.
5. Confirm `/health` shows the expected Telegram webhook URL and that Discord/Slack/Webchat are marked configured for the intended default agent.
6. If preview will only use one external channel, explicitly disable the others so readiness reflects the actual exposure plan.
7. If preview should only reply on a subset of channels, confirm the control policy restricts interactive delivery to that subset before exposing traffic.

## Scheduler

1. Open `/jobs` and confirm the default heartbeat and backup jobs exist.
2. Add any additional prompt, ingest, or maintenance jobs needed for preview operations, using interval, daily, weekly, or cron UTC schedules depending on the operational cadence. The UI and CLI also accept natural schedule text like `every 2 hours`, `daily 09:30`, `weekly mon,fri 08:15`, or `cron 0 9 * * 1-5`.
3. Configure timeout, retry, active-hour, and circuit cooldown settings for any job that could fail noisily or run outside operator hours.
4. If a job should report back to Telegram, Discord, Slack, or Webchat, enable delivery and set the target channel id before the first run.
5. Confirm the control policy still allows those scheduled-job delivery channels, otherwise the run ledger will correctly record them as blocked.
6. Run each job once manually before relying on the recurring scheduler.
7. Use the jobs filters or `mix hydra_x.jobs --kind ... --enabled ...` to inspect only the relevant schedule slice, `mix hydra_x.jobs runs --status ... --kind ...` to review the persisted run ledger, `mix hydra_x.jobs create|update ...` for CLI schedule management, `mix hydra_x.jobs run <id>` for CLI execution, `mix hydra_x.jobs export-runs` for operator handoff/debug bundles, and `mix hydra_x.jobs reset-circuit <id>` if an operator has intentionally recovered a paused job.
8. If you enable `ingest` jobs, confirm the workspace `ingest/` directory contains only the files you intend to import automatically and that the control policy allows the ingest roots you expect.
9. If you enable `maintenance` jobs, confirm the exported report paths and retention behavior are acceptable for the preview node.

## Safety And Observability

1. Check `/health` for provider warmup, channel readiness, MCP registry health, agent MCP bindings, tool policy, scheduler circuits, recent safety events, and secret-storage posture.
2. Export one operator report from `/health` or `mix hydra_x.report` so you have a portable markdown/JSON runtime snapshot before opening preview traffic.
3. Open `/safety` or run `mix hydra_x.safety --level error` to review the latest operator-facing incidents and recent control-plane audit actions directly, then acknowledge or resolve anything already triaged.
4. Review the runtime counters section to confirm provider requests, tool executions, gateway deliveries, scheduler jobs, OTP alarms, and backup manifests are visible.
5. If outbound fetches should be restricted, set `HYDRA_X_HTTP_ALLOWLIST` or configure the persisted tool policy in `/setup`.
6. If workspace writes/patches, browser automation, web search, or shell access are not needed, disable them in `/setup`.
7. Open `/budget` or run `mix hydra_x.budget` to confirm the active agent has the intended hard-limit action and token ceilings before preview traffic starts.
8. Use `/health` to confirm the new control-policy status matches the intended recent-auth, delivery, and ingest-root posture.

## Recovery

1. Back up `hydra_x_dev.db` and the agent workspace root together.
2. Prefer using `mix hydra_x.backup` or `./hydra_x backup` to create a timestamped archive.
3. Use `mix hydra_x.restore --verify --archive <bundle>` for a quick integrity check, then `mix hydra_x.restore --archive <bundle> --target <dir>` to validate that bundles unpack cleanly before relying on them.
4. On restart, run `mix hydra_x.migrate` before bringing the node back online.
5. Re-run `./hydra_x healthcheck` after deploys or crashes.
6. Use `mix hydra_x.healthcheck --only-warn` and `mix hydra_x.doctor --required-only --only-warn` when you want just the unresolved blockers instead of the full report.
7. Use `mix hydra_x.report --required-only --only-warn` after recovery when you want a portable operator snapshot to attach to the incident or deploy notes.
8. Use `/conversations`, `/memory`, and `/jobs` to verify persisted state after recovery.
9. Use `/conversations` or `mix hydra_x.conversations retry-delivery <id>` to retry any failed channel delivery before clearing the incident.
