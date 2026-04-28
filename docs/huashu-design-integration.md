# Huashu Design Integration Notes

`alchaincyf/huashu-design` is best understood as an agent design workflow, not as a React app or Phoenix module to vendor into Hydra. Its useful idea for Hydra is a Claude Design-like loop: start from design context, collect real assets, propose distinct directions, produce tangible artifacts, verify the result, and iterate.

## Fit With Hydra

Hydra already has the right primitives:

- `designer` agent persona in `product_workspace_templates/designer`
- `design_node` graph records for flows, interaction patterns, component specs, rationale, and visual direction
- `sources` and the Library for screenshots, brand guides, briefs, and research material
- `artifacts` API for durable generated deliverables and versions
- project-scoped chat dock for steering the designer agent in context

That means the first integration should be workflow-native rather than a wholesale import of the reference repo.

## Recommended Product Shape

1. **Designer mode in the chat dock**
   - Route vague visual requests to the `designer` agent.
   - Encourage the agent to ask for or search existing design context before generating.
   - Save confirmed context into a `design_node` such as `visual_context` or `design_direction`.

2. **Design direction advisor**
   - When the operator gives a fuzzy brief, the designer proposes three distinct directions.
   - Each direction should include rationale, product fit, risks, and likely implementation cost.
   - Accepted direction becomes a graph node and can seed later artifacts.

3. **Artifact-backed prototypes**
   - Use `artifacts` for generated HTML prototype briefs, decks, review reports, or implementation specs.
   - Keep each artifact versioned, reviewable, and connected to the design nodes it came from.

4. **Asset-first library path**
   - Treat logos, screenshots, brand docs, and product imagery as Library sources.
   - The designer should cite those sources in design rationale and avoid inventing brand details when assets are missing.

5. **Review and verification loop**
   - Add a structured review pass for hierarchy, accessibility, responsiveness, consistency, empty/error/loading states, and implementation handoff.
   - Store keep/fix/next recommendations as design nodes or artifact version notes.

## What Not To Import

- Do not vendor the repo as-is into the app. It is a skills package with personal-use licensing and many standalone demo/export scripts.
- Do not copy its prompts verbatim. Hydra should keep a smaller native prompt that expresses the same workflow in product-graph terms.
- Do not turn Hydra into a generic canvas tool first. The stronger fit is a graph-grounded designer agent that produces inspectable, versioned deliverables.

## First Implementation Slice

The lowest-risk slice is already in place here:

- The `designer` persona now has a high-fidelity design operating loop.
- The loop tells the agent to gather design context, propose directions, produce draft artifacts, review craft quality, and hand off implementation details.

Next useful slices would be:

- Add artifact type filters like `prototype`, `visual_review`, and `design_direction`.
- Add a small "Design directions" panel on the designer agent page.
- Add source upload affordances labeled for brand assets and UI screenshots.
