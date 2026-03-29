# Rich seed data — run with: mix run priv/repo/rich_seeds.exs
#
# Adds substantial data to the existing Velo project (id: 1)
# for testing the graph visualization, stream cards, and board.

alias HydraX.Product
alias HydraX.Product.Graph

project_id = 1
IO.puts("🌱 Enriching Velo project with graph-dense data...")

# Helper to create and return
defmodule Seeds do
  def src(pid, title, content) do
    {:ok, s} = Product.create_source(pid, %{"title" => title, "content" => content})
    s = Product.get_source!(s.id)
    {s, hd(s.source_chunks)}
  end

  def insight(pid, title, body, chunk_ids, status \\ "accepted") do
    {:ok, i} = Product.create_insight(pid, %{
      "title" => title, "body" => body, "status" => status,
      "evidence_chunk_ids" => chunk_ids
    })
    i
  end

  def decision(pid, title, body, alts \\ [], status \\ "active") do
    {:ok, d} = Product.create_decision(pid, %{
      "title" => title, "body" => body, "status" => status,
      "decided_by" => "human", "decided_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "alternatives_considered" => alts
    })
    d
  end

  def requirement(pid, title, body, insight_ids, status \\ "accepted") do
    {:ok, r} = Product.create_requirement(pid, %{
      "title" => title, "body" => body, "status" => status,
      "insight_ids" => insight_ids
    })
    r
  end

  def arch(pid, title, body, node_type) do
    {:ok, a} = Product.create_architecture_node(pid, %{
      "title" => title, "body" => body, "node_type" => node_type, "status" => "active"
    })
    a
  end

  def design(pid, title, body, node_type) do
    {:ok, d} = Product.create_design_node(pid, %{
      "title" => title, "body" => body, "node_type" => node_type, "status" => "active"
    })
    d
  end

  def task(pid, title, body, status, priority, assignee \\ nil) do
    {:ok, t} = Product.create_task(pid, %{
      "title" => title, "body" => body, "status" => status,
      "priority" => priority, "assignee" => assignee
    })
    t
  end

  def learning(pid, title, body, type) do
    {:ok, l} = Product.create_learning(pid, %{
      "title" => title, "body" => body, "learning_type" => type, "status" => "active"
    })
    l
  end

  def strategy(pid, title, body) do
    {:ok, s} = Product.create_strategy(pid, %{
      "title" => title, "body" => body, "status" => "active"
    })
    s
  end

  def constraint(pid, title, body, scope, enforcement) do
    {:ok, c} = Product.create_constraint(pid, %{
      "title" => title, "body" => body, "scope" => scope, "enforcement" => enforcement
    })
    c
  end
end

pid = project_id

# ═══════════════════════════════════════════════
# SOURCES — research material
# ═══════════════════════════════════════════════

{s3, c3} = Seeds.src(pid,
  "Competitor Analysis — Lime, Citibike, Bolt",
  "Lime charges $1 to unlock + $0.39/min in most US cities. No subscription model. Citibike offers annual membership ($205/yr) with unlimited 45-min classic rides. Bolt (EU) has a freemium tier with limited daily rides. Key differentiator: Citibike's station density in Manhattan is 3x higher than any competitor. Lime has no stations (dockless). Users report that Citibike's reliability makes it a commute replacement, while Lime is used for leisure. Bolt's pricing is the most transparent — cost is shown before ride start."
)

{s4, c4} = Seeds.src(pid,
  "User Research — Power Users (10+ rides/week)",
  "Interviewed 8 power users who ride 10+ times per week. Common themes: 1) They plan routes around station density, not shortest path. 2) They have mental maps of which stations are reliably stocked at what times. 3) They consider the bike their primary transport, not a supplement. 4) Weather is the only deterrent. 5) They want a 'commuter mode' that pre-plans their route and alerts them about station issues. 6) All 8 use the monthly plan. 7) Three users track their own ride data in spreadsheets because the app's history view is inadequate. 8) They want a 'streak' or 'stats' feature showing total distance, CO2 saved, calories."
)

{s5, c5} = Seeds.src(pid,
  "Analytics Report — Ride Patterns Q1 2026",
  "Peak usage: 7:30-9:00 AM and 5:00-6:30 PM weekdays. Weekend usage is 40% of weekday volume but rides are 2.3x longer on average. Station depletion events (0 bikes available) occur 12 times/day on average across the network, concentrated at 15 stations near transit hubs. Median ride duration: 14 minutes weekday, 32 minutes weekend. 23% of rides result in the user docking at a different station than intended because their target station was full. Only 8% of registered users are monthly subscribers, but they account for 47% of total rides."
)

{s6, c6} = Seeds.src(pid,
  "User Feedback — App Store Reviews (sample of 200)",
  "Categorized 200 recent app store reviews (3.2 avg rating). Top complaints: 'App is slow to load the map' (31 mentions), 'Bike was broken but I still got charged' (28 mentions), 'Can never find a bike when I need one' (24 mentions), 'Don't understand the pricing' (19 mentions), 'Wish I could report broken bikes more easily' (15 mentions). Top praise: 'Saves me money on parking' (22 mentions), 'Great for short commutes' (18 mentions), 'Healthier than driving' (12 mentions)."
)

IO.puts("  + 4 sources")

# ═══════════════════════════════════════════════
# INSIGHTS — coded from research
# ═══════════════════════════════════════════════

i4 = Seeds.insight(pid,
  "Power users treat the service as primary transport, not supplementary",
  "Users riding 10+ times/week consider the bike their primary mode of transportation. They plan routes around station availability, not distance. This means system reliability directly impacts their daily routine — any failure is not an inconvenience but a transportation crisis.",
  [c4.id]
)

i5 = Seeds.insight(pid,
  "Station density near transit hubs is the critical infrastructure bottleneck",
  "12 station depletion events per day concentrated at 15 transit hub stations. 23% of rides end at unintended stations because the target was full. The physical network, not the app, is the primary constraint on user satisfaction.",
  [c5.id]
)

i6 = Seeds.insight(pid,
  "Broken bike charges erode trust faster than any other issue",
  "28 out of 200 app reviews mention being charged for broken bikes. This is a trust-destroying experience — the user did nothing wrong but was punished. Current process requires contacting support for a refund, which takes 3-5 days.",
  [c6.id]
)

i7 = Seeds.insight(pid,
  "8% of users generate 47% of rides — the power user segment is disproportionately valuable",
  "Monthly subscribers are only 8% of the user base but drive nearly half of all rides. Losing a single power user has 6x the impact of losing a casual user. Retention investment should be weighted accordingly.",
  [c5.id]
)

i8 = Seeds.insight(pid,
  "Users want personal ride statistics and environmental impact tracking",
  "3 out of 8 power users manually track ride data in spreadsheets. All 8 expressed desire for stats: total distance, CO2 saved, calories burned. This is both a retention feature and a marketing asset.",
  [c4.id]
)

i9 = Seeds.insight(pid,
  "Competitor Citibike succeeds because of station density, not app quality",
  "Citibike's Manhattan station density is 3x competitors. Users describe it as 'reliable' — meaning bikes are always available. The lesson: infrastructure investment trumps app features for commuter adoption.",
  [c3.id]
)

i10 = Seeds.insight(pid,
  "App performance is a top-3 complaint — map load time is a barrier",
  "31 out of 200 reviews mention slow map loading. For a service where users need information in the moment (walking to a station), even 3-second delays feel unacceptable. Performance is a feature.",
  [c6.id]
)

i11 = Seeds.insight(pid,
  "Weekend riders have fundamentally different needs than commuters",
  "Weekend rides are 2.3x longer, 40% of weekday volume, and more exploratory. These users need route suggestions, points of interest, and longer ride allowances. They are not well-served by a commuter-optimized product.",
  [c5.id], "draft"
)

IO.puts("  + 8 insights (1 draft)")

# ═══════════════════════════════════════════════
# DECISIONS — choices made
# ═══════════════════════════════════════════════

d3 = Seeds.decision(pid,
  "Prioritize power user retention over casual user acquisition",
  "Given that 8% of users generate 47% of rides, retention of power users is more impactful than acquiring casual users. Product roadmap for Q2 will weight features that serve daily commuters. Marketing spend will shift from awareness to retention.",
  [
    %{"title" => "Equal investment in both segments", "description" => "Split resources evenly between casual and power users", "rejected_reason" => "Ignores the 6x impact difference per user. Limited resources should go where they have the most effect."},
    %{"title" => "Focus on casual conversion", "description" => "Focus on converting casual users to monthly subscribers", "rejected_reason" => "Conversion funnel data shows the biggest drop-off is at the infrastructure level (no bikes available), not at the pricing level."}
  ]
)

d4 = Seeds.decision(pid,
  "Implement instant broken-bike refund with photo verification",
  "Users who scan a broken bike and submit a photo get an instant credit — no support ticket needed. This addresses the #2 complaint category and directly builds trust. The cost of occasional fraud is lower than the cost of lost trust.",
  [
    %{"title" => "Keep current support-based refund process", "description" => "Maintain the 3-5 day refund via support ticket", "rejected_reason" => "Trust erosion from delayed refunds is quantifiable in churn data. 28/200 reviews cite this — it's a top-3 issue."},
    %{"title" => "Automated refund without photo", "description" => "Auto-refund any ride under 2 minutes", "rejected_reason" => "Opens fraud vector — users could scan, immediately dock, get free credit. Photo verification adds accountability without adding friction."}
  ]
)

d5 = Seeds.decision(pid,
  "Build ride statistics dashboard for power users",
  "Add a personal stats view showing: total rides, distance, CO2 saved, calories, ride streaks, most-used stations. This serves retention (users invest in their history) and marketing (shareable stats).",
  []
)

d6 = Seeds.decision(pid,
  "Defer weekend-specific features to Q3",
  "Weekend riders have different needs (longer rides, route suggestions, POI), but the power user / commuter segment is higher priority. Weekend features are deferred, not rejected. Revisit in Q3 with dedicated research.",
  [
    %{"title" => "Build weekend features in Q2", "description" => "Include route suggestions and extended ride time in Q2 scope", "rejected_reason" => "Spreading resources across both segments dilutes impact. Q2 should be focused."}
  ]
)

d7 = Seeds.decision(pid,
  "Optimize map load time as a P0 performance initiative",
  "Map load time is a top-3 complaint (31/200 reviews). Treat this as a critical performance bug, not a feature request. Target: sub-1-second map render on 4G connection. Investigate: lazy tile loading, vector tiles, client-side caching.",
  [], "active"
)

IO.puts("  + 5 decisions")

# ═══════════════════════════════════════════════
# STRATEGIES — coherent direction clusters
# ═══════════════════════════════════════════════

st2 = Seeds.strategy(pid,
  "Power User Flywheel — retain through reliability, data, and trust",
  "Q2 strategy: create a virtuous cycle for power users. Reliability (real-time notifications, station density data) → Trust (instant broken-bike refunds, transparent pricing) → Engagement (ride stats, streaks) → Retention (users invest in their history and habits). Each element reinforces the others. Success metric: reduce monthly subscriber churn by 30%."
)

IO.puts("  + 1 strategy")

# ═══════════════════════════════════════════════
# REQUIREMENTS — what to build
# ═══════════════════════════════════════════════

r4 = Seeds.requirement(pid,
  "Instant broken-bike refund with photo submission",
  "When a user scans a bike QR code and the bike is broken, they can tap 'Report broken' → take a photo → receive instant ride credit. No support ticket. Photo stored for fraud review. Credit appears within 5 seconds.",
  [i6.id]
)

r5 = Seeds.requirement(pid,
  "Personal ride statistics dashboard",
  "A new tab in the app showing: total rides (all time + this month), total distance (km), estimated CO2 saved vs driving, estimated calories burned, current ride streak (consecutive days), most-used stations (top 5), monthly ride chart. Data calculated from ride history.",
  [i8.id, i7.id]
)

r6 = Seeds.requirement(pid,
  "Map performance optimization — sub-1s render",
  "Map view must render in under 1 second on a 4G connection with a cold cache. Investigate: switch to vector tiles, implement progressive loading, add client-side tile cache (IndexedDB), lazy-load station markers outside viewport.",
  [i10.id]
)

r7 = Seeds.requirement(pid,
  "Station depletion prediction (30-minute lookahead)",
  "Using historical ride pattern data, predict which stations will be depleted in the next 30 minutes and surface this in the station detail view. 'This station may run out of bikes by 8:30 AM based on typical weekday patterns.' Accuracy target: 75% precision.",
  [i5.id, i9.id]
)

r8 = Seeds.requirement(pid,
  "Commuter mode — save preferred routes and get proactive alerts",
  "Users can save a 'commute' (origin station, destination station, departure time window). The app proactively notifies them of: station depletion risk, dock availability at destination, weather warnings, service disruptions. Max 3 saved commutes per user.",
  [i4.id, i5.id], "draft"
)

IO.puts("  + 5 requirements (1 draft)")

# ═══════════════════════════════════════════════
# ARCHITECTURE — how to build it
# ═══════════════════════════════════════════════

a4 = Seeds.arch(pid,
  "Ride statistics calculation service",
  "Calculate stats from the ride event log. On ride completion, update running aggregates in a `user_stats` table: total_rides, total_distance_km, total_duration_minutes, co2_saved_kg (distance * 0.21 kg/km), calories (duration * 4.5 cal/min). Streak tracking: maintain `current_streak` and `last_ride_date`. Break streak if gap > 36 hours.\n\nNo real-time calculation needed — aggregates are updated asynchronously after ride_ended event.",
  "system_design"
)

a5 = Seeds.arch(pid,
  "Photo verification pipeline for broken-bike reports",
  "Flow: mobile app captures photo → uploads to S3 presigned URL → sends report to API with photo URL → API creates refund record with `status: auto_approved` → credit applied immediately.\n\nFraud review: async job reviews reports where: same user > 3 reports/month, photo is blurry/black, report within 1 minute of scan. Flagged reports get manual review but refund is NOT reversed unless confirmed fraud.",
  "system_design"
)

a6 = Seeds.arch(pid,
  "Vector tile map with client-side caching",
  "Replace raster tile provider with Mapbox Vector Tiles (MVT). Station markers rendered as a GeoJSON overlay, not individual DOM elements. Client caches tiles in IndexedDB with 24h TTL. Progressive loading: render map frame first, load station data asynchronously.\n\nExpected improvement: 3.2s → 0.8s on 4G cold cache, instant on warm cache.",
  "tech_selection"
)

a7 = Seeds.arch(pid,
  "Station depletion prediction — time-series model",
  "Use 90 days of hourly station-level bike count data. Fit a simple seasonal model (day-of-week + hour-of-day) per station. At each hour, compare current inventory to predicted inventory at +30min. If predicted < 2 bikes, mark as 'at risk.'\n\nNo ML needed — a histogram-based model achieves 78% precision on historical data. Serve predictions from a pre-computed lookup table refreshed hourly.",
  "data_model"
)

a8 = Seeds.arch(pid,
  "API contract: GET /api/v1/stations/:id/prediction",
  "Returns: { station_id, current_bikes, predicted_bikes_30m, risk_level: 'low' | 'medium' | 'high', prediction_confidence: float, last_updated: datetime }.\n\nCached in Redis with 5-minute TTL. Mobile client polls every 2 minutes when station detail is open.",
  "api_contract"
)

IO.puts("  + 5 architecture nodes")

# ═══════════════════════════════════════════════
# DESIGN — UX specifications
# ═══════════════════════════════════════════════

dn3 = Seeds.design(pid,
  "Broken-bike report flow",
  "Entry: User scans bike QR → screen shows bike info → if broken: 'Report Issue' button (prominent, not hidden)\n\n1. Tap 'Report Issue' → camera opens with overlay: 'Take a photo of the issue'\n2. User takes photo → preview with 'Submit' and 'Retake'\n3. Submit → full-screen confirmation: '✓ Credit applied. Sorry about that.' (shows credit amount)\n4. Auto-dismisses after 3 seconds → returns to map\n\nTotal flow: 3 taps, <10 seconds. No text input required.",
  "user_flow"
)

dn4 = Seeds.design(pid,
  "Ride statistics dashboard layout",
  "Tab bar position: 4th tab (after Map, Rides, Stations)\n\nHero section: large number — 'X rides this month' with trend arrow\nStats grid (2x3): Total distance, CO2 saved, Calories, Current streak, Avg ride time, Top station\nMonthly chart: bar chart showing rides per week, last 12 weeks\nFun facts: 'You've biked the equivalent of [city] to [city]'\n\nAll numbers animate on load (count up from 0). Shareable card: tap 'Share my stats' → generates branded image with key stats.",
  "user_flow"
)

dn5 = Seeds.design(pid,
  "Station depletion warning pattern",
  "On station detail screen, when prediction shows risk:\n- Low risk: no indicator\n- Medium risk: amber badge '⚠ May be busy by 8:30 AM'\n- High risk: red badge '🔴 Likely empty by 8:15 AM — consider nearby stations'\n\nNearby stations suggestion: show 3 nearest alternatives with distance and current bike count.\n\nOn map view: at-risk stations show a pulsing amber/red ring around the marker.",
  "interaction_pattern"
)

dn6 = Seeds.design(pid,
  "Commuter mode setup wizard",
  "Settings → Commuter Mode → 'Set up your commute'\n\n1. Origin: 'Where do you start?' → map with station picker (current location pre-selected)\n2. Destination: 'Where are you going?' → map with station picker\n3. Time: 'When do you usually leave?' → time picker with AM/PM, day selector (weekdays/weekends/custom)\n4. Confirmation: summary card showing origin → destination, time, days\n\nAfter setup: commute appears as a card on the home screen above the map. Shows: origin station status, weather, ETA.",
  "user_flow"
)

IO.puts("  + 4 design nodes")

# ═══════════════════════════════════════════════
# TASKS — work to be done
# ═══════════════════════════════════════════════

t6 = Seeds.task(pid, "Build ride stats aggregation service", "Implement the async ride stats calculator that updates user_stats on ride completion. Include: total rides, distance, CO2, calories, streak logic.", "ready", "high", "architect")
t7 = Seeds.task(pid, "Design and implement stats dashboard UI", "Build the stats tab per the design spec. Hero number, stats grid, weekly chart, share card.", "backlog", "high", "designer")
t8 = Seeds.task(pid, "Implement broken-bike photo report flow", "Camera integration, S3 upload, API call, instant credit confirmation. Follow the 3-tap flow spec.", "in_progress", "critical", "architect")
t9 = Seeds.task(pid, "Build station depletion prediction model", "Implement the histogram-based prediction model using 90 days of historical data. Hourly refresh job.", "ready", "high", "architect")
t10 = Seeds.task(pid, "Add depletion warnings to station detail screen", "Amber/red badges per the interaction pattern spec. Include nearby station suggestions for high-risk stations.", "backlog", "medium", "designer")
t11 = Seeds.task(pid, "Switch map to vector tiles (Mapbox MVT)", "Replace current raster tiles. Implement IndexedDB caching. Progressive loading for station markers.", "in_progress", "critical")
t12 = Seeds.task(pid, "Build commuter mode backend", "Save commute preferences, query origin/destination stations, generate notifications.", "backlog", "medium")
t13 = Seeds.task(pid, "Design commuter mode home screen card", "The persistent card that shows commute status on the home screen.", "backlog", "low", "designer")
t14 = Seeds.task(pid, "Implement fraud review queue for bike reports", "Admin view showing flagged reports. Bulk approve/reject. Metrics: reports per user, photo quality score.", "backlog", "low")
t15 = Seeds.task(pid, "Add CO2 and calorie formulas to docs", "Document the calculation formulas for stats transparency. Link from the stats dashboard.", "done", "low")
t16 = Seeds.task(pid, "Performance benchmark: measure current map load time", "Set up Lighthouse CI to track map load time. Establish baseline before vector tile migration.", "done", "medium")
t17 = Seeds.task(pid, "User test the broken-bike flow with 5 riders", "Prototype test with 5 current users. Record: time to complete, confusion points, satisfaction.", "review", "high")

IO.puts("  + 12 tasks across all statuses")

# ═══════════════════════════════════════════════
# LEARNINGS
# ═══════════════════════════════════════════════

l2 = Seeds.learning(pid, "Photo-based reporting reduces support tickets by 60% in pilot", "Piloted the instant broken-bike refund at 10 stations for 2 weeks. Support tickets for those stations dropped 60%. False positive rate: 4% (acceptable). Users reported feeling 'trusted' by the system.", "experiment_result")
l3 = Seeds.learning(pid, "Vector tile migration cut map load from 3.2s to 0.9s in staging", "Staging environment shows 0.9s cold cache, 0.2s warm cache. Production deployment pending. Note: tile set size is 40% smaller than raster, reducing CDN costs.", "usage_data")
l4 = Seeds.learning(pid, "Sprint 1 retrospective — scope was too ambitious", "We tried to ship both the stats dashboard and the broken-bike flow in Sprint 1. The stats dashboard got deprioritized mid-sprint. Lesson: one major feature per sprint, not two. The broken-bike flow shipped on time because it had clear scope.", "retrospective")

IO.puts("  + 3 learnings")

# ═══════════════════════════════════════════════
# CONSTRAINTS
# ═══════════════════════════════════════════════

cn4 = Seeds.constraint(pid, "Maximum 45-minute ride for monthly subscribers", "The 45-minute included ride time is a regulatory agreement with the city. It cannot be changed without renegotiating the operating license. All pricing and UX must work within this constraint.", "business", "strict")
cn5 = Seeds.constraint(pid, "Station hardware API has 10-second polling interval", "The dock hardware reports bike counts via an API with a minimum polling interval of 10 seconds. Real-time availability data has this inherent latency. UX should never promise 'live' data — use 'updated seconds ago' language.", "technical", "strict")

IO.puts("  + 2 constraints")

# ═══════════════════════════════════════════════
# GRAPH EDGES — deep interconnections
# ═══════════════════════════════════════════════

# Insights → Decisions
Graph.link_nodes(pid, "insight", i4.id, "decision", d3.id, "lineage")
Graph.link_nodes(pid, "insight", i7.id, "decision", d3.id, "lineage")
Graph.link_nodes(pid, "insight", i6.id, "decision", d4.id, "lineage")
Graph.link_nodes(pid, "insight", i8.id, "decision", d5.id, "lineage")
Graph.link_nodes(pid, "insight", i7.id, "decision", d5.id, "supports")
Graph.link_nodes(pid, "insight", i11.id, "decision", d6.id, "lineage")
Graph.link_nodes(pid, "insight", i10.id, "decision", d7.id, "lineage")
Graph.link_nodes(pid, "insight", i9.id, "decision", d3.id, "supports")

# Decisions → Strategy
Graph.link_nodes(pid, "decision", d3.id, "strategy", st2.id, "lineage")
Graph.link_nodes(pid, "decision", d4.id, "strategy", st2.id, "lineage")
Graph.link_nodes(pid, "decision", d5.id, "strategy", st2.id, "lineage")

# Decisions → Requirements
Graph.link_nodes(pid, "decision", d4.id, "requirement", r4.id, "supports")
Graph.link_nodes(pid, "decision", d5.id, "requirement", r5.id, "supports")
Graph.link_nodes(pid, "decision", d7.id, "requirement", r6.id, "supports")
Graph.link_nodes(pid, "decision", d3.id, "requirement", r7.id, "supports")

# Requirements → Architecture
Graph.link_nodes(pid, "requirement", r4.id, "architecture_node", a5.id, "lineage")
Graph.link_nodes(pid, "requirement", r5.id, "architecture_node", a4.id, "lineage")
Graph.link_nodes(pid, "requirement", r6.id, "architecture_node", a6.id, "lineage")
Graph.link_nodes(pid, "requirement", r7.id, "architecture_node", a7.id, "lineage")
Graph.link_nodes(pid, "requirement", r7.id, "architecture_node", a8.id, "lineage")

# Requirements → Design
Graph.link_nodes(pid, "requirement", r4.id, "design_node", dn3.id, "lineage")
Graph.link_nodes(pid, "requirement", r5.id, "design_node", dn4.id, "lineage")
Graph.link_nodes(pid, "requirement", r7.id, "design_node", dn5.id, "lineage")
Graph.link_nodes(pid, "requirement", r8.id, "design_node", dn6.id, "lineage")

# Requirements → Tasks
Graph.link_nodes(pid, "requirement", r5.id, "task", t6.id, "lineage")
Graph.link_nodes(pid, "requirement", r5.id, "task", t7.id, "lineage")
Graph.link_nodes(pid, "requirement", r4.id, "task", t8.id, "lineage")
Graph.link_nodes(pid, "requirement", r7.id, "task", t9.id, "lineage")
Graph.link_nodes(pid, "requirement", r7.id, "task", t10.id, "lineage")
Graph.link_nodes(pid, "requirement", r6.id, "task", t11.id, "lineage")
Graph.link_nodes(pid, "requirement", r8.id, "task", t12.id, "lineage")
Graph.link_nodes(pid, "requirement", r8.id, "task", t13.id, "lineage")
Graph.link_nodes(pid, "requirement", r4.id, "task", t14.id, "lineage")
Graph.link_nodes(pid, "requirement", r4.id, "task", t17.id, "lineage")

# Architecture → Tasks
Graph.link_nodes(pid, "architecture_node", a4.id, "task", t6.id, "supports")
Graph.link_nodes(pid, "architecture_node", a5.id, "task", t8.id, "supports")
Graph.link_nodes(pid, "architecture_node", a6.id, "task", t11.id, "supports")
Graph.link_nodes(pid, "architecture_node", a7.id, "task", t9.id, "supports")

# Design → Tasks
Graph.link_nodes(pid, "design_node", dn4.id, "task", t7.id, "supports")
Graph.link_nodes(pid, "design_node", dn3.id, "task", t8.id, "supports")
Graph.link_nodes(pid, "design_node", dn5.id, "task", t10.id, "supports")
Graph.link_nodes(pid, "design_node", dn6.id, "task", t13.id, "supports")

# Constraints → nodes they constrain
Graph.link_nodes(pid, "constraint", cn4.id, "requirement", r5.id, "constrains")
Graph.link_nodes(pid, "constraint", cn4.id, "design_node", dn4.id, "constrains")
Graph.link_nodes(pid, "constraint", cn5.id, "architecture_node", a7.id, "constrains")
Graph.link_nodes(pid, "constraint", cn5.id, "design_node", dn5.id, "constrains")

# Cross-connections
Graph.link_nodes(pid, "learning", l2.id, "decision", d4.id, "supports")
Graph.link_nodes(pid, "learning", l3.id, "task", t11.id, "supports")
Graph.link_nodes(pid, "learning", l4.id, "strategy", st2.id, "supports")
Graph.link_nodes(pid, "task", t16.id, "task", t11.id, "enables")
Graph.link_nodes(pid, "task", t8.id, "task", t17.id, "enables")

IO.puts("  + 50+ graph edges")

# ═══════════════════════════════════════════════
# FLAGS — graph health items
# ═══════════════════════════════════════════════

Graph.flag_node(pid, "requirement", r8.id, "needs_review", "Draft requirement — not yet validated with evidence", "coherence")
Graph.flag_node(pid, "insight", i11.id, "needs_review", "Draft insight — needs additional evidence sources", "coherence")
Graph.flag_node(pid, "task", t14.id, "orphaned", "No upstream requirement linked — why does this task exist?", "coherence")
Graph.flag_node(pid, "task", t15.id, "stale", "Completed 3 weeks ago — consider archiving", "coherence")

IO.puts("  + 4 graph flags")

# ═══════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════

counts = Product.project_counts(pid)
IO.puts("")
IO.puts("✅ Velo project enriched!")
IO.puts("   Sources: #{counts.sources}, Insights: #{counts.insights}, Decisions: #{counts.decisions}")
IO.puts("   Strategies: #{counts.strategies}, Requirements: #{counts.requirements}")
IO.puts("   Architecture: #{counts.architecture_nodes}, Design: #{counts.design_nodes}")
IO.puts("   Tasks: #{counts.tasks}, Learnings: #{counts.learnings}")
IO.puts("   Open flags: #{counts.flags}")
IO.puts("")
IO.puts("   Graph should now have 60+ nodes with 50+ edges")
IO.puts("   Stream should have items in all 3 sections")
IO.puts("   Board should have tasks across all columns")
