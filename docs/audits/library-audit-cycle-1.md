# Library Audit — Cycle 1

**Project:** Hydra (grixate/hydra-x)
**Audit date:** 2026-04-19
**Methodology:** `library-audit-spec.md` §3 (the eight tests) + §6 principle alignment
**Status:** Audit complete — Cycle 1 Library work plan below

---

## Summary

- **Pass:** 2 of 8 tests (Source detail view, Source-to-graph connections)
- **Partial:** 4 of 8 (Ingestion, Processing visibility, Find, Agent triggering)
- **Fail:** 2 of 8 (Slice by relevance, Scale at 1000+ sources)
- **P0 gaps:** 3 structural — scale perf, relevance filters, auto-trigger on ingest
- **P1 gaps:** 6 workflow — drag-drop, URL paste, chat file attachment, bulk progress, re-analyze action, chips

The Library is **partially functional** but has structural gaps in filtering and performance that block core use at scale. Test 6 (connections) is the strongest area. Immediate fix candidates: virtualization, "unreviewed" filter, auto-Researcher on ingest.

---

## 1. Inventory (baseline)

### Frontend
- `web/src/pages/library-page.tsx` — entry; renders tab-based sources view
- `web/src/pages/library-detail-page.tsx` — single-source detail page
- `web/src/components/sources/source-list.tsx` — list w/ `ScrollArea`, fixed height, no virtualization
- `web/src/components/sources/source-detail.tsx` — detail panel (content, metadata, related insights/requirements, chunk accordion)
- `web/src/components/sources/source-intake-dialog.tsx` — upload dialog (paste text + file picker)
- `web/src/components/sources/processing-progress.tsx` — single-source progress indicator
- `web/src/components/sources/upload-zone.tsx` — drag-drop upload zone (exists, **not integrated into current tab-based flow**)
- Filters in `app.tsx`: `sourceStatusFilter` + `sourceTypeFilter` + `deferredSearch`
- Chat: `<ChatDock>` is wired on Library surface with `defaultAgent: "researcher"`, `defaultExpanded: true` (chat-architecture Cycle-1 work)

### Backend
- `lib/hydra_x_web/controllers/source_api_controller.ex` — CRUD + `POST /projects/:id/sources/bulk` + `POST /projects/:id/sources/:id/analyze`
- `analyze/2` opens a Researcher conversation with source context and submits a prompt — works but is manual-trigger only
- Source processing pipeline exists; status transitions broadcast on `source:<id>` channel (`progress` / `completed` / `failed`)

---

## 2. Test results

### TEST 1 — Source ingestion is frictionless
**RESULT:** Partial
**OBSERVED:** `SourceIntakeDialog` supports paste text + file picker (2 of 5 paths). Bulk API `POST /projects/:id/sources/bulk` works. Missing: drag-drop on canvas (zone exists but not wired), URL paste tab, add-from-chat attachment flow.
**GAP:** missing_primitive
**PRIORITY:** P1
**REMEDIATION:** Wire `upload-zone.tsx` into library-page. Add URL-paste tab. Attach chat files to source creation.
**EFFORT:** ~1 day

### TEST 2 — Processing state is visible
**RESULT:** Partial
**OBSERVED:** `ProcessingProgress` renders per-source status, stage, chunk count, error, spinner. Source list shows `processing_status` badge. Socket channel subscription on `source:<id>` drives live updates. **Gap:** `ProcessingProgress` only shown for the selected source — no list-level at-a-glance view while many sources process. Cancel action not exposed.
**GAP:** discovery_gap
**PRIORITY:** P1
**REMEDIATION:** Inline row-level progress chips on list items. Cancel button wired to a new `DELETE /projects/:id/sources/:id/processing` route.
**EFFORT:** ~0.5 day

### TEST 3 — Find a specific source quickly
**RESULT:** Partial
**OBSERVED:** `deferredSearch` filters title + content client-side. Two filter selects (status, type). No date filter, no sort control. Client-side filtering is O(n) and not scale-safe.
**GAP:** performance_gap + discovery_gap
**PRIORITY:** P1
**REMEDIATION:** Backend search endpoint once corpus > 500. Add date-added sort. Explicit "search content" toggle.
**EFFORT:** ~1 day

### TEST 4 — Slice the Library by relevance
**RESULT:** Fail
**OBSERVED:** Only two filter dimensions (status, type). Missing all five of the spec's meaningful slices (unreviewed, connected to node, contributed to decision, low-value, flagged). Source schema lacks a `reviewed_at` field or similar markers.
**GAP:** missing_primitive
**PRIORITY:** P0
**REMEDIATION:** Add `reviewed_at :utc_datetime_usec` (nullable) to `sources`. Add filter chips: "Unreviewed" (`reviewed_at IS NULL`), "Contributed to decision" (has InsightEvidence → requirement ref), "Connected to node X" (via graph edges). Low-value + flagged defer to Cycle 2.
**EFFORT:** ~1.5 days (migration + schema + filter UI)

### TEST 5 — Source detail view is informative
**RESULT:** Pass
**OBSERVED:** Shows original content (raw panel), metadata, status, related insights + requirements with links, indexed chunks accordion with evidence counts. Missing: re-process / archive / delete / share actions, but these are bolt-on.
**GAP:** workflow_gap (minor)
**PRIORITY:** P1
**REMEDIATION:** Add "Re-analyze" button wired to existing `api.analyzeSource`. Archive + delete actions behind confirm dialog. Share defers to Cycle 2.
**EFFORT:** ~0.5 day

### TEST 6 — Source-to-graph connections are obvious
**RESULT:** Pass
**OBSERVED:** `source-detail.tsx` has side-by-side related insights + requirements sections, clickable navigation, chunk-level "N insights, N requirements" badges. Bidirectional via `onSelectInsight` / `onSelectRequirement` callbacks.
**GAP:** n/a
**PRIORITY:** n/a
**REMEDIATION:** Verify `InsightDetail` has a back-link to source (assumed present from prior work; re-verify during implementation).

### TEST 7 — Agent triggering from Library
**RESULT:** Partial
**OBSERVED:** `api.analyzeSource` endpoint exists and creates a Researcher conversation + task. **Not exposed in source-detail UI** — user can only trigger via bulk-reprocess or from chat. No "process all pending" bulk action.
**GAP:** workflow_gap
**PRIORITY:** P1
**REMEDIATION:** "Re-analyze" button on `SourceDetail`. "Process N pending sources" button in sources-tab header.
**EFFORT:** ~0.5 day

### TEST 8 — Scale handling at 1000+ sources
**RESULT:** Fail
**OBSERVED:** `SourceList` uses `ScrollArea` with fixed height and renders all rows to DOM. No virtualization. Client-side search is O(n). At 1000 sources, DOM render + filter on every keystroke would degrade visibly.
**GAP:** performance_gap
**PRIORITY:** P0
**REMEDIATION:** Virtualize with `@tanstack/react-virtual` (same approach planned for Command Center Zone 2). Backend search endpoint replaces client-side filter when `corpus > 500`. Load test with 1000-source synthetic fixture.
**EFFORT:** ~1 day (component) + ~1 day (backend search endpoint)

---

## 3. §6 Principle alignment

| Principle | Status | Note |
|---|---|---|
| Chat panel present, Researcher default | **Pass** | ChatDock enabled on Library, `defaultAgent: "researcher"`, `defaultExpanded: true` |
| Suggestion chips Library-relevant | **Pass** | `SurfaceSuggestionChips` with `chipSurface="library"` — chips: "Summarize this source", "Find related sources", "Upload more" |
| Sidebar shows Researcher activity | **Pass** | `SidebarAgentRow` (from chat-architecture Cycle 1) now shows `state`, `summary`, `active_count` for Researcher |
| Source ingestion drives Researcher tasks | **Fail** | `create_source` does **not** auto-trigger Researcher analysis. User must click "Re-analyze" manually or use the `analyze` endpoint. **This is the biggest workflow gap** — a user uploading sources expects automatic extraction. |
| Source nodes preserve lineage | **Pass** | Source rows are referenced from `InsightEvidence` → graph flows intact |
| Library project-scoped | **Pass** | All queries scoped by `project_id` |
| Aesthetic alignment | **Pass** | shadcn + floating UI (paper/ink) matches broader product |

---

## 4. Cycle 1 work plan

### P0 — ship in Cycle 1 week 2
1. **Auto-trigger Researcher on source create** *(the big one — users expect this)*
   - On successful `create_source`, enqueue a Researcher task via `AgentTasks.create_task` with `context_type: "library_source"` and the source's body as description
   - Broadcasts to Command Center Zone 2 automatically (already wired)
   - Effort: ~0.5 day

2. **"Unreviewed" + "Connected to decision" filters**
   - Add `reviewed_at :utc_datetime_usec` column
   - Two filter chips in the sources tab header
   - Effort: ~1 day

3. **Virtualized source list**
   - Install `@tanstack/react-virtual` (if not present; also needed by CC Zone 2 polish)
   - Swap `ScrollArea` mapping for `useVirtualizer`
   - Load test with 1000-source fixture
   - Effort: ~1 day

### P1 — ship if time permits
4. Integrate `upload-zone.tsx` into the tab-based sources view (drag-drop everywhere)
5. URL paste input in intake dialog
6. "Re-analyze" button on `SourceDetail`
7. "Process all pending (N)" bulk action button
8. Per-row progress chip on `SourceList` items
9. Date-added sort control
10. Cancel-processing action

### P2 — defer to Cycle 2
- Chat message file attachment → source pipeline
- Low-value source marker
- "Flagged for re-review" filter
- Share-source action
- Archive-source action
- Source quality ratings
- Cross-project Library (shared-memory foundational sources)

---

## 5. Remediation effort estimate

- P0: ~2.5 days
- P1: ~3 days
- **Total Cycle 1 Library fix budget:** ~5–6 developer days if both P0 and P1 land

If this doesn't fit Cycle 1 alongside chat architecture + Why-button + Command Center + onboarding + stream tabs, **only P0 ships** and P1 rolls into early Cycle 2. That's an acceptable outcome per spec §8 ("If audit reveals deep gaps, Library work becomes a meaningful stream parallel to other specs").

---

## 6. What the Library does well (don't regress)

- `SourceDetail` panel is rich and well-organized (Test 5)
- Bidirectional source↔node navigation is solid (Test 6)
- Real-time per-source progress via Phoenix channels
- Already following the chat-architecture + sidebar patterns correctly

## 7. Risks

- **Auto-Researcher on ingest** might cause surprise queuing behavior if a user bulk-uploads 50 PDFs — 50 tasks suddenly show up in Command Center. Mitigation: aggregate into a single "Researcher processing 50 sources" flow task, or rate-limit by one-task-per-source-chunk-batch. Design call during implementation.
- **Virtualization + search** interaction: virtualized list + client-side search means scrolling past filtered matches. Backend search endpoint is the proper fix; client-side filter is an interim hack.

---

## Sign-off

Audit conducted per `library-audit-spec.md` §3–§6. Deliverables §9 met:
1. Inventory — §1
2. Test results — §2
3. Gap analysis — §2 + §4
4. Cycle 1 work plan — §4

No major Library issue left undocumented or undecided. Ready for implementation when prioritisation allows.
