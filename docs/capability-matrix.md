# Hydra-X Capability Matrix

This document tracks the current implementation against the target product shape.

## Channels

| Area | Current | Target |
| --- | --- | --- |
| Telegram | Webhook ingress, outbound delivery, retry/dead-letter, setup + health visibility | Richer media download, richer formatting, deeper diagnostics |
| Discord | Webhook ingress, outbound delivery, setup + health visibility | Richer interaction support, richer formatting, command ergonomics |
| Slack | Events ingress, outbound delivery, setup + health visibility | Richer thread UX, richer formatting, stronger request diagnostics |
| Webchat | Not implemented | Session-backed web chat with SSE streaming |
| Twitch | Not implemented | Post-Webchat phase |

## Tools

| Area | Current | Target |
| --- | --- | --- |
| Workspace access | Read, list, write | Patch/apply and richer diff semantics |
| Shell | Allowlisted shell execution | Split read-only vs controlled-write policies |
| HTTP | Public-host fetch with allowlist support | Richer fetch semantics and provider-backed search options |
| Web search | Dedicated search tool | Better ranking, richer metadata, pluggable providers |
| Memory | Recall + save | Hybrid recall and richer reconciliation flows |
| Browser automation | Not implemented | Page fetch, click, fill, screenshot, extract |

## Memory And Ingest

| Area | Current | Target |
| --- | --- | --- |
| Memory model | Typed entries, edges, reconciliation states, markdown export | Hybrid recall, richer provenance surfacing, deeper bulletin ranking |
| Ingest | Markdown, text, JSON parsing with archive tracking | PDF ingest, embedding-backed retrieval, richer reingest controls |
| Ingest provenance | Active ingest-backed file list plus persisted ingest run history | Richer per-chunk provenance surfacing and reingest controls |
| Bulletin | Memory-backed bulletin and compaction summaries | More context-aware Cortex ranking and token-aware compaction |

## Scheduling And Delivery

| Area | Current | Target |
| --- | --- | --- |
| Schedule modes | Interval, daily, weekly, cron with active-hour/timeout/retry/circuit controls | Natural language scheduling |
| Delivery back | Telegram, Discord, Slack | Webchat and richer delivery diagnostics |
| Job history | Persisted runs, filtering, exports | Retention controls, circuit breaker state, richer failure semantics |

## Runtime And Deployment

| Area | Current | Target |
| --- | --- | --- |
| Runtime shape | Single deployable Phoenix/OTP monolith with domain facades | Keep monolith through preview |
| Provider routing | Per-agent defaults, per-process overrides, fallback order, warmup state | Richer policy-based routing by workload/budget |
| Security | Single-operator auth, tool policy, SSRF/path guards | Stronger secret isolation, session hardening, broader policy surface |
| Observability | Health, readiness, safety ledger, reports, telemetry summary | Deeper per-channel/provider diagnostics and richer exports |
| Clustering | Awareness plumbing only | Real distributed ownership after persistence migration |
