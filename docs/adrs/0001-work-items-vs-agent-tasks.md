# ADR 0001 — `hx_work_items` and `agent_tasks` remain separate

**Date:** 2026-04-20
**Status:** Accepted (Stream A0.2)
**Context:** Cycle-1 introduced `agent_tasks` for Command Center; `hx_work_items` pre-existed for operator-layer autonomy.

## Decision

Keep both tables. Do not unify.

## Rationale

They solve orthogonal problems:

| Concern | `hx_work_items` | `agent_tasks` |
|---|---|---|
| Layer | Runtime / operator autonomy | Product / user-facing |
| State machine | complex (draft → proposal_only → patch_ready → validated → operator_approved → merge_ready) | simple (pending → running → proposing → terminal) |
| Consumers | validation_runner, observability, agents_live, approval_records, artifacts | CC, Stream, Chat, Flows, Proposals, Why-button |
| Payload shape | budget / runtime_state / approval_stage | progress / proposal_payload / lineage metadata |

Audit confirmed:
- No code writes to both for the same logical unit.
- No product-surface code (CC, chat, stream, graph, Why-button, onboarding) reads `work_items`.
- No operator-layer code depends on `agent_tasks`.
- Tests for each layer only touch their own table.

Unifying would force orchestration-heavy fields onto user-facing rows (or vice versa) and collapse two distinct state machines into a permissive superset. The cost of keeping both is one extra table; the cost of merging is semantic muddling in every consumer.

## Consequences

- Runtime docs should make the layer boundary explicit (operator = internal autonomy; product = user-facing).
- Future cross-layer hooks (e.g., surfacing an autonomy work-item failure to the user) go through a small translator, not a shared table.
- New product-layer work extends `agent_tasks`. New autonomy/operator work extends `hx_work_items`.

## Supersedes

None.
