# Hydra-X Capability Matrix

This document tracks the current implementation against the target product shape.

## Channels

| Area | Current | Target |
| --- | --- | --- |
| Telegram | Webhook ingress, outbound delivery, retry/dead-letter, setup + health visibility | Richer media download, richer formatting, deeper diagnostics |
| Discord | Webhook ingress, outbound delivery, setup + health visibility | Richer interaction support, richer formatting, command ergonomics |
| Slack | Events ingress, outbound delivery, setup + health visibility | Richer thread UX, richer formatting, stronger request diagnostics |
| Webchat | Public browser ingress, SSE-style runtime streaming, setup + health visibility | Richer attachment support, richer formatting, anonymous/session controls |
| Twitch | Not implemented | Post-Webchat phase |

## Tools

| Area | Current | Target |
| --- | --- | --- |
| Workspace access | Read, list, write, targeted patch with standardized execution summaries and safety classes | Richer diff/apply semantics |
| Shell | Allowlisted shell execution | Split read-only vs controlled-write policies |
| HTTP | Public-host fetch with allowlist support | Richer fetch semantics and provider-backed search options |
| Web search | Dedicated search tool | Better ranking, richer metadata, pluggable providers |
| Memory | Recall + save with hybrid-ranked and vector-weighted recall reasons | Richer reconciliation flows and true model-backed embeddings |
| Browser automation | Fetch page, inspect links/forms/headings/tables, preview or submit parsed forms, capture SVG snapshots, extract text with policy gating | Richer page fidelity and real browser-backed screenshots |
| Skills | Agent-scoped discovery of workspace `SKILL.md` files, enable/disable controls, prompt exposure | Installable packaging, remote catalogs, deeper worker integration |
| MCP | Persisted stdio/HTTP MCP registry, health probes, setup/CLI management, agent-scoped enablement and binding inspection, report export, prompt visibility | Deeper worker-side execution semantics |

## Memory And Ingest

| Area | Current | Target |
| --- | --- | --- |
| Memory model | Typed entries, edges, reconciliation states, markdown export, hybrid-ranked and vector-weighted recall | Richer provenance surfacing, deeper bulletin ranking, embedding-backed retrieval |
| Ingest | Markdown, text, JSON, and PDF parsing with archive tracking, restore-on-reimport, and control-policy ingest roots | Embedding-backed retrieval and richer ingest scheduling controls |
| Ingest provenance | Active ingest-backed file list, selected-entry provenance, and persisted ingest run history | Deeper per-chunk provenance surfacing and reingest controls |
| Bulletin | Sectioned bulletin prioritizing goals/todos, decisions/preferences, context, and conflict warnings | More context-aware Cortex ranking and token-aware compaction |

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
| Provider routing | Per-agent defaults, per-process overrides, fallback order, warmup state | Richer policy-based routing by workload/budget |
| Security | Single-operator auth, recent-auth checks, login throttling, encrypted secrets at rest, tool policy, cross-cutting control policy, SSRF/path guards | Browser sandboxing polish and future multi-user boundaries |
| Operator surfaces | Stable `/setup`, `/agents`, `/conversations`, `/memory`, `/jobs`, `/budget`, `/safety`, `/settings/providers`, `/health` with CLI parity for major flows | Keep stable through preview, add depth rather than new surfaces |
| Observability | Health, readiness, safety ledger, reports, telemetry summary | Deeper per-channel/provider diagnostics and richer exports |
| Clustering | Awareness plumbing only | Real distributed ownership after persistence migration |
