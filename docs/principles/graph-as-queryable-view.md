# Principle: Graph as Queryable View

**Project:** Hydra (grixate/hydra-x)
**Cycle:** 1 (foundational principle)
**Status:** Codified principle — referenced by all graph-related decisions
**Last updated:** 2026-04-19

---

## The principle

**The graph is a queryable view of the project's typed knowledge, not a workspace where work happens.**

Work happens in **Stream** (catch-up), **Command Center** (live agent direction), **Board** (collaborative drafting), and **Library** (sources). The Graph is where the user **orients** to the project's structure, **traverses** decision lineage, and **composes views** through agent direction.

The graph is a lens onto a typed knowledge structure. It is not a canvas, not a sticky-note board, not an infinite playground. It is the visualization layer of Product Graph.

---

## What this means in practice

### Three questions the graph must answer in under 5 seconds

1. **Where does this come from?** (lineage up — from any node back toward the Vision)
2. **What depends on this?** (lineage down — what hangs off this node)
3. **What contradicts this?** (cross-graph tension — surfaced by Coherence)

If the graph answers these three questions fast and well, it is doing its job. Everything else — aesthetics, animations, layout polish — serves these three questions.

### The default view is the spine

When a user lands on the Graph surface with no query active, the default view shows **the spine** of the project: Vision at the root, Strategic Bets below, top-level Decisions visible. Everything below is collapsed until requested.

This default exists because:
- It teaches Product Graph's structure visually
- It avoids the empty-canvas problem (something is always there)
- It avoids the overflow problem (not everything is shown at once)

### Views are composed by agents, not authored by users

Users don't drag nodes around. They don't curate visual layouts. They ask questions and the graph reshapes:

- "Show me everything downstream of the authentication decision"
- "Show me all sources that contradict our pricing bet"
- "Show me Decisions made in the last 30 days that affected the architecture"

These queries are conversational — typed into the chat panel, addressed to the Strategist or another agent. The agent composes the graph view in response. The graph isn't *navigated*; it's *queried*.

This is Hydra's structural difference from Miro, FigJam, Whimsical, and any other "spatial canvas" tool.

---

## Design implications this principle locks in

### What's ruled out

- **Free-form node positioning** — users cannot manually place nodes on a canvas. ELK-computed layouts only.
- **Infinite canvas vibes** — bounded viewport with smart framing on selected nodes; no endless pan-zoom space.
- **Sticky note interactions** — no Miro-style ad hoc visual elements that aren't typed graph nodes.
- **Manual layout work** — users do not spend time arranging the graph for visual aesthetic. If the layout feels wrong, the fix is in the data model (relationships, types) not in manual positioning.
- **Decorative annotations** — no on-canvas text that isn't a node, no callout boxes, no freehand drawing.
- **Aesthetic-first features** — features whose primary value is "it looks cool on a big screen" don't get built. Clarity beats spectacle.

### What's ruled in

- **Filters and focus modes** — "show only Decisions"; "show only nodes touched in the last week"; "highlight contradictions"
- **Lineage highlights** — selecting a node visually emphasizes its ancestors and descendants
- **Contradiction overlays** — Coherence's findings render directly on the graph as visual indicators on conflicting nodes
- **Conversational view composition** — agent-driven graph reshaping in response to natural language queries
- **Smart framing** — when a node is selected or queried, the graph auto-pans/zooms to the relevant subset
- **Time-based slices** — view the graph as it existed at a specific point in time (Cycle 3+; foundation in Cycle 1)

---

## Why this principle matters

The "infinite beautiful canvas" version of Hydra is seductive but a trap. It leads to:

- Layout becoming labor (positions become precious)
- The graph drifting out of sync with reality (visual layouts don't update when content does)
- The graph becoming a place users *visit* rather than a place that *informs*
- Cognitive overload at scale (1000 nodes on an infinite canvas is unusable)
- Competing with Miro/FigJam on their turf (a fight Hydra would lose)

The "queryable view" version of Hydra is constrained but powerful:

- Layout is computed (zero user labor)
- The graph always reflects current state (it's a view, not an artifact)
- The graph is consulted, not maintained
- Scale is handled by query (you never see everything at once)
- It competes on a different axis — *typed lineage you can query* — where Hydra is alone

The principle is restrictive on purpose. The restrictions are what make Hydra work.

---

## Technical implications

### Layout algorithm
- **ELK layered** algorithm with swimlane layout (current implementation)
- Edge routing: SPLINES
- No manual positioning data stored on nodes (positions are derived, not persisted)
- Performance budget: layout computation completes in <500ms for graphs up to 200 nodes

### Rendering
- Currently `@xyflow/react` (React-based)
- Future: WebGL via Three.js or similar when graph sizes exceed React's render budget (likely Cycle 3-4 when projects start importing 1000+ documents/sources)
- The transition to WebGL is a rendering change; the principle of "queryable view" remains constant

### Interaction
- Selection and traversal: keyboard + click
- View composition: chat with agents (Strategist primary)
- Zoom: smart-bounded; auto-fit to query results; no infinite zoom

---

## What the graph IS, distilled

**The graph is to typed product knowledge what a database query result is to a database: a derived, transient, fit-for-purpose view of underlying structure.**

Users don't curate the graph any more than they curate a SQL result. They write the query (via chat); the graph renders the answer.

---

## Naming and consistency

When discussing the graph in specs, design docs, or code comments, prefer language that reflects this principle:

| Avoid | Prefer |
|---|---|
| "Lay out the graph" | "Render the view" |
| "Place the node here" | "Compose a view that includes this node" |
| "The canvas" | "The graph surface" / "the view" |
| "Move the Vision to the top" | "(don't — layout is computed)" |
| "Design the graph" | "Define the data; layout follows" |

This vocabulary discipline matters. Words shape what the team builds.

---

## When this principle should be revisited

This principle is intentionally absolute. But absolutes can become wrong over time. Revisit if:

- User research shows users repeatedly asking for manual positioning (suggests we're missing a real need)
- Query-driven view composition can't handle scenarios users care about (suggests the model is too thin)
- A new technical capability changes the cost-benefit (e.g., perfect AI layout that handles every case might let us add some user control without losing the principle)

Revisiting requires a real proposal with reasoning, not ad hoc PRs that violate the principle. Anyone proposing to violate this principle should be referred to this document and asked to explain what they think has changed.

---

## Reference in other specs

This principle is referenced by:

- `command-center-spec.md` — CC composes views; graph displays them
- `chat-architecture-spec.md` — agents in chat are the primary view-composition tool
- `why-button-spec.md` — Why-button is a specific kind of query against the graph
- `task-data-model-spec.md` — node entities have no `position` field; positions are derived

Future specs touching the graph should also reference this principle in their alignment appendix.

---

## The one-line version

If you can only remember one thing from this document:

> **The graph is queried, not curated.**

Everything else follows from that.
