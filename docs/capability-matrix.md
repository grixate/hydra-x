# Hydra-X Capability Matrix

This document tracks the current implementation against the target product shape.

## Channels

| Area | Current | Target |
| --- | --- | --- |
| Telegram | Webhook ingress, chunk-safe outbound delivery, retry/dead-letter, reply context, setup + health visibility | Richer media download, richer formatting, deeper diagnostics |
| Discord | Webhook ingress, chunk-aware outbound previews, reply context, setup + health visibility | Richer interaction support, richer formatting, command ergonomics |
| Slack | Events ingress, threaded outbound delivery, reply context, setup + health visibility | Richer thread UX, richer formatting, stronger request diagnostics |
| Webchat | Public browser ingress, SSE-style runtime streaming, setup + health visibility | Richer attachment support, richer formatting, anonymous/session controls |
| Twitch | Not implemented | Post-Webchat phase |

## Tools

| Area | Current | Target |
| --- | --- | --- |
| Workspace access | Read, list, write, targeted patch with standardized execution summaries and safety classes | Richer diff/apply semantics |
| Shell | Allowlisted shell execution | Split read-only vs controlled-write policies |
| HTTP | Public-host fetch with allowlist support | Richer fetch semantics and provider-backed search options |
| Web search | Dedicated search tool | Better ranking, richer metadata, pluggable providers |
| Memory | Recall + save with hybrid-ranked recall, persisted local or OpenAI-compatible embedding vectors, and explicit embedding reasons | Richer reconciliation flows and deeper external embedding-backed retrieval |
| Browser automation | Session-aware fetch page, inspect links/forms/headings/tables/images/meta/scripts/structured data, preview or submit parsed forms with cookie carryover, capture SVG snapshots with page counts, extract text with policy gating | Richer page fidelity and real browser-backed screenshots |
| Skills | Agent-scoped discovery of workspace `SKILL.md` files with richer manifest metadata, enable/disable controls, planner hints, prompt exposure, worker inspection, and exportable per-agent catalogs | Installable packaging, remote catalogs, deeper worker integration |
| MCP | Persisted stdio/HTTP MCP registry, health probes, setup/CLI management, agent-scoped enablement and binding inspection, report export, prompt visibility, worker-side inspect/probe/invoke tooling for enabled bindings, and CLI invoke flows for HTTP-backed actions | Richer protocol-native execution semantics and stdio invocation support |

## Memory And Ingest

| Area | Current | Target |
| --- | --- | --- |
| Memory model | Typed entries, edges, reconciliation states, markdown export, hybrid-ranked recall, and persisted local or OpenAI-compatible embedding vectors | Richer provenance surfacing, deeper bulletin ranking, external embedding-backed retrieval |
| Ingest | Markdown, text, JSON, and PDF parsing with archive tracking, restore-on-reimport, and control-policy ingest roots | Embedding-backed retrieval and richer ingest scheduling controls |
| Ingest provenance | Active ingest-backed file list, selected-entry provenance, and persisted ingest run history | Deeper per-chunk provenance surfacing and reingest controls |
| Bulletin | Sectioned bulletin prioritizing goals/todos, decisions/preferences, context, and conflict warnings, paired with token-aware compaction triggers at 80/90/95% of conversation budget | More context-aware Cortex ranking |

## Scheduling And Delivery

| Area | Current | Target |
| --- | --- | --- |
| Schedule modes | Interval, daily, weekly, cron plus natural schedule text normalization with active-hour/timeout/retry/circuit controls | Richer natural language parsing |
| Job kinds | Heartbeat, prompt, backup, ingest, maintenance | More maintenance specializations |
| Delivery back | Telegram, Discord, Slack, Webchat | Richer delivery diagnostics |
| Job history | Persisted runs, filtering, exports | Retention controls, circuit breaker state, richer failure semantics |

## Runtime And Deployment

| Area | Current | Target |
| --- | --- | --- |
| Runtime shape | Single deployable Phoenix/OTP monolith with domain facades, resumable persisted execution checkpoints, replay-safe tool caching across restart recovery, tracked step state, and operator-visible execution events | Keep monolith through preview |
| Provider routing | Per-agent defaults, per-process overrides, fallback order, warmup state, explicit adapter capabilities, and health probes | Richer policy-based routing by workload/budget |
| Security | Single-operator auth, recent-auth checks, login throttling, encrypted or env-backed secrets, tool policy, cross-cutting control policy, SSRF/path guards | Browser sandboxing polish and future multi-user boundaries |
| Operator surfaces | Stable `/setup`, `/agents`, `/conversations`, `/memory`, `/jobs`, `/budget`, `/safety`, `/settings/providers`, `/health` with CLI parity for major flows | Keep stable through preview, add depth rather than new surfaces |
| Observability | Health, readiness, safety ledger, reports, telemetry summary | Deeper per-channel/provider diagnostics and richer exports |
| Clustering | Awareness plumbing plus node-aware health/reporting | Persistence migration, real distributed ownership, failover, and cross-node placement |
