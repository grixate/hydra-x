# Demo seed data — run with: mix run priv/repo/demo_seeds.exs
#
# Creates a project "Velo" (a bike-sharing app) with nodes across
# all graph types, linked via graph edges, so every view has data.

alias HydraX.Product
alias HydraX.Product.Graph

IO.puts("🌱 Seeding demo project...")

# Ensure default agent exists first
HydraX.Runtime.ensure_default_agent!()

# Create project (provisions all 5 agents)
{:ok, project} = Product.create_project(%{
  "name" => "Velo",
  "description" => "A bike-sharing platform for urban commuters",
  "trust_level" => "standard"
})

pid = project.id
IO.puts("  Created project: #{project.name} (id: #{pid})")

# --- Sources ---
{:ok, source1} = Product.create_source(project, %{
  "title" => "User Interview Batch 1 — Commuters",
  "content" => "Interview with Sarah, daily bike commuter in Portland. She says: 'I never know if a bike will be available at my usual station in the morning. I've been late to work three times this month because of it.' She checks the app before leaving home but availability changes by the time she walks to the station. She wants real-time notifications when bikes become available at her preferred station. She also mentioned that the current pricing is confusing — she's on the monthly plan but got charged extra for a ride that went over 30 minutes, which she didn't realize would happen."
})

{:ok, source2} = Product.create_source(project, %{
  "title" => "Support Ticket Analysis — Q1 2026",
  "content" => "Analyzed 342 support tickets from Q1. Top categories: 1) Billing confusion (89 tickets, 26%) — users don't understand overage charges on monthly plans. 2) Bike availability (67 tickets, 20%) — complaints about empty stations during morning rush. 3) App crashes on Android 14 (45 tickets, 13%) — reproducible crash when opening the map view. 4) Dock malfunction reports (38 tickets, 11%) — bikes stuck in docks, users charged for time while waiting for support. 5) Route suggestions (31 tickets, 9%) — users want the app to suggest bike-friendly routes."
})

IO.puts("  Created 2 sources with chunks")

# Get chunks for evidence
source1 = Product.get_source!(source1.id)
source2 = Product.get_source!(source2.id)
chunk1 = hd(source1.source_chunks)
chunk2 = hd(source2.source_chunks)

# --- Insights ---
{:ok, insight1} = Product.create_insight(project, %{
  "title" => "Bike availability anxiety drives user frustration",
  "body" => "Commuters experience significant anxiety about bike availability during morning rush hours. The gap between checking the app at home and arriving at the station creates a reliability problem. Users want real-time notifications, not just current availability snapshots.",
  "status" => "accepted",
  "evidence_chunk_ids" => [chunk1.id]
})

{:ok, insight2} = Product.create_insight(project, %{
  "title" => "Pricing confusion causes billing disputes",
  "body" => "26% of support tickets relate to billing confusion. Monthly plan users don't understand overage charges. The pricing model is not transparent at the point of decision (starting a ride).",
  "status" => "accepted",
  "evidence_chunk_ids" => [chunk2.id]
})

{:ok, insight3} = Product.create_insight(project, %{
  "title" => "Android 14 map crash is a critical stability issue",
  "body" => "13% of support tickets report a reproducible crash on Android 14 when opening the map view. This is a P0 stability issue affecting a growing segment of the user base.",
  "status" => "accepted",
  "evidence_chunk_ids" => [chunk2.id]
})

IO.puts("  Created 3 insights")

# --- Decisions ---
{:ok, decision1} = Product.create_decision(project, %{
  "title" => "Adopt real-time availability notifications",
  "body" => "We will build a real-time notification system for bike availability at preferred stations. Users can set station preferences and receive push notifications when bikes become available during their commute window. This directly addresses the availability anxiety identified in user interviews.",
  "status" => "active",
  "decided_by" => "human",
  "decided_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
  "alternatives_considered" => [
    %{"title" => "Reservation system", "description" => "Let users reserve bikes 15 minutes ahead", "rejected_reason" => "Creates artificial scarcity and complexity. Bikes sitting reserved but unused waste capacity."},
    %{"title" => "Predictive availability", "description" => "Show predicted availability based on historical patterns", "rejected_reason" => "Good idea for v2 but doesn't solve the immediate problem of real-time awareness."}
  ]
})

{:ok, decision2} = Product.create_decision(project, %{
  "title" => "Simplify pricing to flat monthly + per-ride cap",
  "body" => "Replace the current confusing overage model with a simple structure: monthly subscribers get unlimited rides up to 45 minutes each. Rides over 45 minutes cost $2 per additional 15-minute block. Show the cost clearly before and during the ride.",
  "status" => "active",
  "decided_by" => "human",
  "alternatives_considered" => [
    %{"title" => "Keep current pricing with better UX", "description" => "Just explain the current model better", "rejected_reason" => "The model itself is the problem, not the explanation. 26% support ticket rate won't drop with just better copy."}
  ]
})

IO.puts("  Created 2 decisions")

# --- Strategy ---
{:ok, strategy1} = Product.create_strategy(project, %{
  "title" => "Reliability-first: earn trust through predictability",
  "body" => "Our strategic direction for Q2 is to make the service predictable and trustworthy. Users should never be surprised — not by availability, not by pricing, not by app crashes. Every feature we ship this quarter should reduce uncertainty for the user.",
  "status" => "active"
})

IO.puts("  Created 1 strategy")

# --- Requirements ---
{:ok, req1} = Product.create_requirement(project, %{
  "title" => "Real-time station availability notifications",
  "body" => "Users can set 1-3 preferred stations and a commute time window. The system sends push notifications when bikes become available at those stations during the window. Notifications must be delivered within 30 seconds of availability change.",
  "status" => "accepted",
  "insight_ids" => [insight1.id]
})

{:ok, req2} = Product.create_requirement(project, %{
  "title" => "Transparent ride pricing display",
  "body" => "Show the pricing structure clearly before ride start: 'Included in your plan for 45 min. After that: $2/15min.' During the ride, show a real-time cost indicator after the 45-minute mark. At ride end, show total cost breakdown.",
  "status" => "accepted",
  "insight_ids" => [insight2.id]
})

{:ok, req3} = Product.create_requirement(project, %{
  "title" => "Fix Android 14 map view crash",
  "body" => "Identify and fix the reproducible crash on Android 14 when opening the map view. Root cause analysis required. Must not regress on other Android versions.",
  "status" => "accepted",
  "insight_ids" => [insight3.id]
})

IO.puts("  Created 3 requirements")

# --- Architecture nodes ---
{:ok, arch1} = Product.create_architecture_node(project, %{
  "title" => "WebSocket-based availability push system",
  "body" => "Use Phoenix Channels (WebSocket) to push real-time bike availability updates to mobile clients. Station availability is tracked in an ETS table updated by dock hardware events. Changes are broadcast to subscribed clients within 5 seconds of dock state change.\n\nStack: Phoenix Channels → ETS state → PubSub broadcast → Mobile WebSocket client\n\nThis avoids polling and gives us sub-second latency for availability updates.",
  "node_type" => "system_design",
  "status" => "active"
})

{:ok, arch2} = Product.create_architecture_node(project, %{
  "title" => "Ride billing service — event-sourced pricing",
  "body" => "Ride pricing calculated from an event stream: ride_started, minute_tick, ride_ended. Each event carries the pricing rule active at that moment. This makes pricing auditable and allows us to change pricing rules without affecting in-progress rides.\n\nStorage: PostgreSQL with JSONB event log per ride.\nCalculation: On ride_ended, replay events to compute final cost.",
  "node_type" => "system_design",
  "status" => "active"
})

{:ok, arch3} = Product.create_architecture_node(project, %{
  "title" => "PostgreSQL for all persistent storage",
  "body" => "Use PostgreSQL as the single persistent store. No Redis, no separate cache layer for v1. Simplicity over performance optimization at our current scale (< 50k daily rides). Add caching layer only when we have evidence of performance bottlenecks.",
  "node_type" => "tech_selection",
  "status" => "active"
})

IO.puts("  Created 3 architecture nodes")

# --- Design nodes ---
{:ok, design1} = Product.create_design_node(project, %{
  "title" => "Station availability notification flow",
  "body" => "Entry: User opens Settings → Notifications → Station Alerts\n1. User taps 'Add station' → shows map with stations\n2. User selects station → confirms with station name + current availability\n3. User sets time window: 'Notify me between [7:00 AM] and [9:00 AM]'\n4. User sets days: weekday/weekend/custom\n5. Confirmation: 'You'll get notified when bikes are available at [Station] during your commute'\n\nNotification: '[Station Name] has [N] bikes available now' → tap opens map centered on station with directions",
  "node_type" => "user_flow",
  "status" => "active"
})

{:ok, design2} = Product.create_design_node(project, %{
  "title" => "Ride cost indicator pattern",
  "body" => "During a ride, show a subtle cost bar at the bottom of the map:\n- First 45 min: green bar, text: 'Included in your plan'\n- At 40 min: yellow transition, text: '5 minutes remaining in included time'\n- After 45 min: amber bar, text: '$2.00 — 15 min overtime' (updates every minute)\n\nThe bar uses the same position as the ride timer, replacing it contextually. No modal interruption. The user can always see the cost without tapping.",
  "node_type" => "interaction_pattern",
  "status" => "active"
})

IO.puts("  Created 2 design nodes")

# --- Tasks ---
{:ok, task1} = Product.create_task(project, %{
  "title" => "Implement WebSocket availability channel",
  "body" => "Create a Phoenix Channel that clients subscribe to with station IDs. Broadcast availability updates when ETS state changes. Include: connection handling, subscription management, heartbeat, reconnection.",
  "status" => "ready",
  "priority" => "high",
  "assignee" => "architect"
})

{:ok, task2} = Product.create_task(project, %{
  "title" => "Build notification preferences UI",
  "body" => "Implement the station alert settings flow: station picker (map-based), time window selector, day selector, confirmation. Follow the design spec in design node 'Station availability notification flow'.",
  "status" => "backlog",
  "priority" => "high",
  "assignee" => "designer"
})

{:ok, task3} = Product.create_task(project, %{
  "title" => "Fix Android 14 map crash",
  "body" => "Root cause analysis and fix for the map view crash on Android 14. Reproduce, identify the issue (likely MapBox SDK version conflict), fix, and verify across Android 12-15.",
  "status" => "in_progress",
  "priority" => "critical"
})

{:ok, task4} = Product.create_task(project, %{
  "title" => "Redesign ride summary screen with cost breakdown",
  "body" => "Update the ride-end summary to show: ride duration, included time, overtime, cost per overtime block, total charge. Make the breakdown visual, not just a number.",
  "status" => "backlog",
  "priority" => "medium"
})

{:ok, task5} = Product.create_task(project, %{
  "title" => "Write pricing FAQ for help center",
  "body" => "Create a clear FAQ explaining the new pricing model. Include examples: 'If your ride is 50 minutes, you pay $2 for 5 minutes of overtime.' Link from the ride cost indicator.",
  "status" => "done",
  "priority" => "low"
})

IO.puts("  Created 5 tasks")

# --- Learnings ---
{:ok, learning1} = Product.create_learning(project, %{
  "title" => "Support ticket analysis reveals pricing as top pain point",
  "body" => "Q1 support ticket analysis showed billing confusion at 26% — significantly higher than expected. Previous assumption was that availability was the #1 issue, but billing is close. Both need addressing in Q2.",
  "learning_type" => "usage_data",
  "status" => "active"
})

IO.puts("  Created 1 learning")

# --- Constraints ---
{:ok, constraint1} = Product.create_constraint(project, %{
  "title" => "All user data must be GDPR compliant",
  "body" => "Location data, ride history, and payment information must follow GDPR data handling requirements. Users must be able to export and delete their data. Retention period: 2 years for ride history, 7 years for billing records (tax requirement).",
  "scope" => "business",
  "enforcement" => "strict"
})

{:ok, constraint2} = Product.create_constraint(project, %{
  "title" => "App must work offline for active rides",
  "body" => "Once a ride is started, the app must continue tracking the ride even without network connectivity. Ride data syncs when connectivity returns. Users should never lose a ride or be double-charged due to connectivity issues.",
  "scope" => "technical",
  "enforcement" => "strict"
})

{:ok, constraint3} = Product.create_constraint(project, %{
  "title" => "Prefer open-source dependencies",
  "body" => "When choosing between libraries or services, prefer open-source options over proprietary ones. Exceptions allowed when the open-source alternative is significantly less mature or maintainable.",
  "scope" => "technical",
  "enforcement" => "advisory"
})

IO.puts("  Created 3 constraints")

# --- Graph edges (lineage links) ---
# Decision ← Insight
Graph.link_nodes(pid, "insight", insight1.id, "decision", decision1.id, "lineage")
Graph.link_nodes(pid, "insight", insight2.id, "decision", decision2.id, "lineage")

# Strategy ← Decision
Graph.link_nodes(pid, "decision", decision1.id, "strategy", strategy1.id, "lineage")
Graph.link_nodes(pid, "decision", decision2.id, "strategy", strategy1.id, "lineage")

# Requirement ← Decision
Graph.link_nodes(pid, "decision", decision1.id, "requirement", req1.id, "supports")
Graph.link_nodes(pid, "decision", decision2.id, "requirement", req2.id, "supports")

# Architecture ← Requirement
Graph.link_nodes(pid, "requirement", req1.id, "architecture_node", arch1.id, "lineage")
Graph.link_nodes(pid, "requirement", req2.id, "architecture_node", arch2.id, "lineage")

# Design ← Requirement
Graph.link_nodes(pid, "requirement", req1.id, "design_node", design1.id, "lineage")
Graph.link_nodes(pid, "requirement", req2.id, "design_node", design2.id, "lineage")

# Task ← Requirement
Graph.link_nodes(pid, "requirement", req1.id, "task", task1.id, "lineage")
Graph.link_nodes(pid, "requirement", req1.id, "task", task2.id, "lineage")
Graph.link_nodes(pid, "requirement", req3.id, "task", task3.id, "lineage")
Graph.link_nodes(pid, "requirement", req2.id, "task", task4.id, "lineage")

# Architecture ← Decision
Graph.link_nodes(pid, "decision", decision1.id, "architecture_node", arch1.id, "lineage")
Graph.link_nodes(pid, "decision", decision2.id, "architecture_node", arch2.id, "lineage")

# Constraint → links
Graph.link_nodes(pid, "constraint", constraint1.id, "requirement", req2.id, "constrains")
Graph.link_nodes(pid, "constraint", constraint2.id, "architecture_node", arch1.id, "constrains")

IO.puts("  Created graph edges (lineage, supports, constrains)")

# --- Summary ---
counts = Product.project_counts(project)
IO.puts("")
IO.puts("✅ Demo project '#{project.name}' seeded successfully!")
IO.puts("   Sources: #{counts.sources}, Insights: #{counts.insights}, Decisions: #{counts.decisions}")
IO.puts("   Strategies: #{counts.strategies}, Requirements: #{counts.requirements}")
IO.puts("   Architecture: #{counts.architecture_nodes}, Design: #{counts.design_nodes}")
IO.puts("   Tasks: #{counts.tasks}, Learnings: #{counts.learnings}, Constraints: 3")
IO.puts("")
IO.puts("   Login at http://localhost:4000/login")
IO.puts("   Product app at http://localhost:4000/product/#{pid}")
IO.puts("   (Run the Vite dev server: cd web && npm run dev)")
