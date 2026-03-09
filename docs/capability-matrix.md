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
| Workspace access | Read, list, write, targeted patch | Richer diff/apply semantics |
| Shell | Allowlisted shell execution | Split read-only vs controlled-write policies |
| HTTP | Public-host fetch with allowlist support | Richer fetch semantics and provider-backed search options |
| Web search | Dedicated search tool | Better ranking, richer metadata, pluggable providers |
| Memory | Recall + save with hybrid-ranked recall reasons | Richer reconciliation flows and embedding-backed retrieval |
| Browser automation | Not implemented | Page fetch, click, fill, screenshot, extract |

## Memory And Ingest

| Area | Current | Target |
| --- | --- | --- |
| Memory model | Typed entries, edges, reconciliation states, markdown export, hybrid-ranked recall | Richer provenance surfacing, deeper bulletin ranking, embedding-backed retrieval |
| Ingest | Markdown, text, JSON, and PDF parsing with archive tracking and restore-on-reimport | Embedding-backed retrieval and richer ingest scheduling controls |
| Ingest provenance | Active ingest-backed file list, selected-entry provenance, and persisted ingest run history | Deeper per-chunk provenance surfacing and reingest controls |
| Bulletin | Memory-backed bulletin and compaction summaries | More context-aware Cortex ranking and token-aware compaction |

## Scheduling And Delivery

| Area | Current | Target |
| --- | --- | --- |
| Schedule modes | Interval, daily, weekly, cron with active-hour/timeout/retry/circuit controls | Natural language scheduling |
| Job kinds | Heartbeat, prompt, backup, ingest, maintenance | More maintenance specializations |
| Delivery back | Telegram, Discord, Slack, Webchat | Richer delivery diagnostics |
| Job history | Persisted runs, filtering, exports | Retention controls, circuit breaker state, richer failure semantics |

## Runtime And Deployment

| Area | Current | Target |
| --- | --- | --- |
| Runtime shape | Single deployable Phoenix/OTP monolith with domain facades, persisted execution checkpoints, and operator-visible execution events | Keep monolith through preview |
| Provider routing | Per-agent defaults, per-process overrides, fallback order, warmup state | Richer policy-based routing by workload/budget |
| Security | Single-operator auth, recent-auth checks, login throttling, tool policy, SSRF/path guards | Stronger secret isolation and broader policy surface |
| Observability | Health, readiness, safety ledger, reports, telemetry summary | Deeper per-channel/provider diagnostics and richer exports |
| Clustering | Awareness plumbing only | Real distributed ownership after persistence migration |
