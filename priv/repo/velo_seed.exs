# Velo seed — fresh, dense, single-project dev fixture.
# Run with:  mix run priv/repo/velo_seed.exs
#
# Wipes existing projects, then creates one "Velo" project and
# seeds ~120 nodes across all types (sources, insights, decisions,
# requirements, architecture, design, tasks, learnings, strategies,
# constraints, topics, authors, publications, excerpts) with a rich
# edge structure so the graph reads as a real product workspace.

alias HydraX.Product
alias HydraX.Product.Graph
alias HydraX.Graph.Nodes
alias HydraX.Graph.Relationships
alias HydraX.Repo
import Ecto.Query

IO.puts("🧹 Wiping existing projects…")

for p <- Product.list_projects() do
  case Product.delete_project(p) do
    {:ok, _} -> IO.puts("  - deleted #{p.name}")
    err -> IO.puts("  ! could not delete #{p.name}: #{inspect(err)}")
  end
end

# Drop project-scoped agent profiles too so re-runs don't collide on slug.
# Default agents (is_default=true) are preserved.
{deleted_agents, _} =
  Repo.delete_all(
    from(a in HydraX.Runtime.AgentProfile,
      where: like(a.slug, "project-%") and a.is_default == false
    )
  )

if deleted_agents > 0 do
  IO.puts("  - deleted #{deleted_agents} project agent profiles")
end

# Make sure the runtime default agent exists for project provisioning.
HydraX.Runtime.ensure_default_agent!()

IO.puts("🌱 Creating Velo project…")

{:ok, project} =
  Product.create_project(%{
    "name" => "Velo",
    "description" => "A bike-sharing platform for urban commuters",
    "trust_level" => "standard"
  })

pid = project.id
IO.puts("  Created project: #{project.name} (id: #{pid})")

# ════════════════════════════════════════════════════════════════════
# Helpers
# ════════════════════════════════════════════════════════════════════

defmodule VeloSeed do
  alias HydraX.Product
  alias HydraX.Product.Graph
  alias HydraX.Graph.Nodes
  alias HydraX.Graph.Relationships

  def src(pid, title, content) do
    {:ok, s} = Product.create_source(pid, %{"title" => title, "content" => content})
    s = Product.get_source!(s.id)
    chunk = List.first(s.source_chunks || [])
    {s, chunk && chunk.id}
  end

  def insight(pid, title, body, chunks \\ [], status \\ "accepted") do
    chunks = Enum.reject(chunks, &is_nil/1)
    {:ok, i} =
      Product.create_insight(pid, %{
        "title" => title,
        "body" => body,
        "status" => status,
        "evidence_chunk_ids" => chunks
      })
    i
  end

  def decision(pid, title, body, alts \\ [], status \\ "active") do
    {:ok, d} =
      Product.create_decision(pid, %{
        "title" => title,
        "body" => body,
        "status" => status,
        "decided_by" => "human",
        "decided_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "alternatives_considered" => alts
      })
    d
  end

  def requirement(pid, title, body, insight_ids \\ [], status \\ "accepted") do
    {:ok, r} =
      Product.create_requirement(pid, %{
        "title" => title,
        "body" => body,
        "status" => status,
        "insight_ids" => insight_ids
      })
    r
  end

  def arch(pid, title, body, node_type) do
    {:ok, a} =
      Product.create_architecture_node(pid, %{
        "title" => title,
        "body" => body,
        "node_type" => node_type,
        "status" => "active"
      })
    a
  end

  def design(pid, title, body, node_type) do
    {:ok, d} =
      Product.create_design_node(pid, %{
        "title" => title,
        "body" => body,
        "node_type" => node_type,
        "status" => "active"
      })
    d
  end

  def task(pid, title, body, status, priority, assignee \\ nil) do
    {:ok, t} =
      Product.create_task(pid, %{
        "title" => title,
        "body" => body,
        "status" => status,
        "priority" => priority,
        "assignee" => assignee
      })
    t
  end

  def learning(pid, title, body, type) do
    {:ok, l} =
      Product.create_learning(pid, %{
        "title" => title,
        "body" => body,
        "learning_type" => type,
        "status" => "active"
      })
    l
  end

  def strategy(pid, title, body) do
    {:ok, s} =
      Product.create_strategy(pid, %{"title" => title, "body" => body, "status" => "active"})
    s
  end

  def constraint(pid, title, body, scope, enforcement) do
    {:ok, c} =
      Product.create_constraint(pid, %{
        "title" => title,
        "body" => body,
        "scope" => scope,
        "enforcement" => enforcement
      })
    c
  end

  def topic(pid, title, description, granularity) do
    {:ok, t} =
      Nodes.create_node(pid, %{
        type_key: "topic",
        title: title,
        status: "active",
        attributes: %{
          "granularity" => granularity,
          "description" => description,
          "aliases" => []
        }
      })
    t
  end

  def author(pid, display_name, disambiguator \\ "") do
    {:ok, a} =
      Nodes.create_node(pid, %{
        type_key: "author",
        title: display_name,
        status: "active",
        attributes: %{
          "display_name" => display_name,
          "disambiguator" => disambiguator,
          "external_identifiers" => %{}
        }
      })
    a
  end

  def publication(pid, name, kind) do
    {:ok, p} =
      Nodes.create_node(pid, %{
        type_key: "publication",
        title: name,
        status: "active",
        attributes: %{"name" => name, "kind" => kind}
      })
    p
  end

  def excerpt(pid, source, passage, page \\ nil) do
    attrs = %{
      "source_id" => source.id,
      "passage_text" => passage,
      "position_anchor" => if(page, do: %{"page" => page}, else: %{}),
      "extracted_by" => "user"
    }

    {:ok, ex} =
      Nodes.create_node(pid, %{
        type_key: "excerpt",
        title: short_title(passage),
        body: passage,
        status: "active",
        attributes: attrs
      })

    {:ok, _} = Relationships.create_relationship(source, ex, "has_excerpt")
    ex
  end

  defp short_title(text) do
    text |> String.split() |> Enum.take(8) |> Enum.join(" ") |> String.slice(0, 80)
  end

  def link(pid, from_node, to_node, kind) do
    Graph.link_nodes(pid, from_node.type_key, from_node.id, to_node.type_key, to_node.id, kind)
  end

  def is_about(_pid, source_or_excerpt, topic) do
    {:ok, _} = Relationships.create_relationship(source_or_excerpt, topic, "is_about")
  end

  def authored_by(_pid, source, author) do
    {:ok, _} = Relationships.create_relationship(source, author, "authored_by")
  end

  def published_in(_pid, source, publication) do
    {:ok, _} = Relationships.create_relationship(source, publication, "published_in")
  end

  def cites(_pid, source_a, source_b) do
    {:ok, _} = Relationships.create_relationship(source_a, source_b, "cites")
  end
end

# ════════════════════════════════════════════════════════════════════
# SOURCES (12)
# ════════════════════════════════════════════════════════════════════

IO.puts("📚 Sources…")

{s1, c1} =
  VeloSeed.src(pid, "User Interview Batch 1 — Commuters",
    "Sarah commutes daily by Velo in Portland. She says: 'I never know if a bike will be available at my usual station.' She checks the app before leaving home but availability changes by the time she walks over. She wants real-time notifications when bikes become available at her preferred station. She's on the monthly plan but got charged extra for an over-30-minute ride which she didn't realise would happen.")

{s2, c2} =
  VeloSeed.src(pid, "Support Ticket Analysis — Q1 2026",
    "342 tickets categorised. 26% billing confusion (overage on monthly plans). 20% bike availability complaints during morning rush. 13% Android 14 crashes on map view. 11% dock malfunctions. 9% want bike-friendly route suggestions.")

{s3, c3} =
  VeloSeed.src(pid, "Competitor Analysis — Lime, Citibike, Bolt",
    "Lime charges $1 unlock + $0.39/min. Citibike: $205/yr unlimited 45-min classic rides. Bolt has freemium with limited daily rides. Citibike's Manhattan station density is 3x competitors. Bolt's pricing is the most transparent.")

{s4, c4} =
  VeloSeed.src(pid, "User Research — Power Users (10+ rides/week)",
    "8 power users interviewed. They plan routes around station density, not shortest path. They have mental maps of which stations are reliably stocked at which times. Weather is the only deterrent. They want a commuter mode that pre-plans routes and alerts them about station issues. All 8 use the monthly plan.")

{s5, c5} =
  VeloSeed.src(pid, "Analytics Report — Ride Patterns Q1 2026",
    "Peak usage: 7:30-9:00 AM and 5:00-6:30 PM weekdays. Weekend usage 40% of weekday volume but rides 2.3x longer. 12 station depletion events/day concentrated at 15 transit hub stations. 23% of rides end at unintended stations because target was full. Monthly subscribers are 8% of users but 47% of total rides.")

{s6, c6} =
  VeloSeed.src(pid, "User Feedback — App Store Reviews (200 sample)",
    "200 recent reviews, 3.2 avg rating. Top complaints: app slow to load map (31), bike was broken but I still got charged (28), can never find a bike (24), don't understand the pricing (19), wish I could report broken bikes more easily (15).")

{s7, c7} =
  VeloSeed.src(pid, "Field Study — Station Operations",
    "Observed 5 high-volume stations across 14 days. Maintenance lag averages 4.2 hours from 'broken bike' report to a tech arriving. Rebalancing trucks reach a depleted station within 22 minutes during peak hours but take >2 hours during shoulder periods. Operators say the routing software is conservative; they often override it.")

{s8, c8} =
  VeloSeed.src(pid, "Pricing Sensitivity Survey",
    "Survey of 412 users. 38% would tolerate a $5/mo price increase if reliability improved. 19% would cancel. 43% are price-insensitive in either direction. Only 12% understand the current pricing structure on first try.")

{s9, c9} =
  VeloSeed.src(pid, "Internal Note — Engineering Capacity",
    "Engineering team of 7. Two are on the recovery side (rebalancing pipeline, broken-bike reports). Three on consumer apps. Two on platform/infra. Capacity for next quarter is constrained by an ongoing migration off the legacy ride-billing service.")

{s10, c10} =
  VeloSeed.src(pid, "Mobility Trends 2026 — McKinsey Excerpt",
    "Micromobility usage grew 34% YoY in major US metros. Subscription models outperform pay-per-ride 2:1 on retention. Apps that offer route planning and predictive availability score 28% higher on user satisfaction scales.")

{s11, c11} =
  VeloSeed.src(pid, "Operations Memo — Late-Night Riders",
    "10pm-2am usage doubled YoY. 60% of late-night rides are cluster-departures from entertainment districts. Bike availability degrades to <5% capacity at the 4 most-popular drop-off stations between 11pm and 1am.")

{s12, c12} =
  VeloSeed.src(pid, "Climate Impact Audit",
    "Velo riders displaced an estimated 2.1M car-trips in 2025 across the network, equivalent to ~430 metric tons of CO2 avoided. Power users are responsible for 47% of avoided trips while being only 8% of riders.")

sources = [s1, s2, s3, s4, s5, s6, s7, s8, s9, s10, s11, s12]
chunks = [c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12]
IO.puts("  + #{length(sources)} sources")

# ════════════════════════════════════════════════════════════════════
# AUTHORS, PUBLICATIONS (Library structural)
# ════════════════════════════════════════════════════════════════════

IO.puts("👤 Authors + publications…")

a1 = VeloSeed.author(pid, "Maria Chen", "Velo Research Lead")
a2 = VeloSeed.author(pid, "Devon Park", "Engineering")
a3 = VeloSeed.author(pid, "Aisha Rahman", "Operations")
a4 = VeloSeed.author(pid, "McKinsey & Company", "")
a5 = VeloSeed.author(pid, "Lin Wong", "Product Analytics")
a6 = VeloSeed.author(pid, "External Consultant — Helmholtz Lab", "Mobility Studies")

p1 = VeloSeed.publication(pid, "Velo Internal Research", "report")
p2 = VeloSeed.publication(pid, "McKinsey Quarterly", "magazine")
p3 = VeloSeed.publication(pid, "Velo Operations Bulletin", "report")
p4 = VeloSeed.publication(pid, "App Store Review Aggregator", "other")

VeloSeed.authored_by(pid, s1, a1)
VeloSeed.authored_by(pid, s2, a3)
VeloSeed.authored_by(pid, s3, a5)
VeloSeed.authored_by(pid, s4, a1)
VeloSeed.authored_by(pid, s5, a5)
VeloSeed.authored_by(pid, s6, a3)
VeloSeed.authored_by(pid, s7, a3)
VeloSeed.authored_by(pid, s8, a5)
VeloSeed.authored_by(pid, s9, a2)
VeloSeed.authored_by(pid, s10, a4)
VeloSeed.authored_by(pid, s11, a3)
VeloSeed.authored_by(pid, s12, a6)

VeloSeed.published_in(pid, s1, p1)
VeloSeed.published_in(pid, s2, p3)
VeloSeed.published_in(pid, s4, p1)
VeloSeed.published_in(pid, s5, p1)
VeloSeed.published_in(pid, s6, p4)
VeloSeed.published_in(pid, s7, p3)
VeloSeed.published_in(pid, s10, p2)
VeloSeed.published_in(pid, s11, p3)

VeloSeed.cites(pid, s10, s5)
VeloSeed.cites(pid, s8, s5)
VeloSeed.cites(pid, s12, s5)

IO.puts("  + 6 authors, 4 publications, 12 authored-by, 8 published-in, 3 cites")

# ════════════════════════════════════════════════════════════════════
# TOPICS (12)
# ════════════════════════════════════════════════════════════════════

IO.puts("🏷  Topics…")

t_avail = VeloSeed.topic(pid, "Bike availability", "Whether a bike is reachable when a user wants one.", "coarse")
t_pricing = VeloSeed.topic(pid, "Pricing & billing", "How users perceive and are charged for Velo usage.", "coarse")
t_reliability = VeloSeed.topic(pid, "System reliability", "End-to-end dependability of Velo as transport.", "coarse")
t_powerusers = VeloSeed.topic(pid, "Power users", "10+ rides/week, treat Velo as primary transport.", "medium")
t_brokenbikes = VeloSeed.topic(pid, "Broken bikes", "Reporting and refund flow for damaged bikes.", "medium")
t_stations = VeloSeed.topic(pid, "Station network", "Physical density, depletion, rebalancing.", "medium")
t_routes = VeloSeed.topic(pid, "Route planning", "Bike-friendly routing and turn-by-turn guidance.", "medium")
t_competitors = VeloSeed.topic(pid, "Competitive landscape", "Lime, Citibike, Bolt and adjacent micromobility.", "medium")
t_climate = VeloSeed.topic(pid, "Climate impact", "CO2 displaced, carbon attribution.", "fine")
t_latenight = VeloSeed.topic(pid, "Late-night usage", "Patterns in 10pm-2am rides and rebalancing.", "fine")
t_app = VeloSeed.topic(pid, "App performance", "Load times, crashes, map rendering.", "fine")
t_subs = VeloSeed.topic(pid, "Subscription model", "Monthly plan economics and retention.", "fine")

topics = [
  t_avail, t_pricing, t_reliability, t_powerusers, t_brokenbikes,
  t_stations, t_routes, t_competitors, t_climate, t_latenight, t_app, t_subs
]

# Source ↔ topic edges (sources are about topics)
VeloSeed.is_about(pid, s1, t_avail)
VeloSeed.is_about(pid, s1, t_pricing)
VeloSeed.is_about(pid, s2, t_pricing)
VeloSeed.is_about(pid, s2, t_app)
VeloSeed.is_about(pid, s2, t_brokenbikes)
VeloSeed.is_about(pid, s2, t_routes)
VeloSeed.is_about(pid, s3, t_competitors)
VeloSeed.is_about(pid, s3, t_pricing)
VeloSeed.is_about(pid, s3, t_stations)
VeloSeed.is_about(pid, s4, t_powerusers)
VeloSeed.is_about(pid, s4, t_reliability)
VeloSeed.is_about(pid, s4, t_subs)
VeloSeed.is_about(pid, s5, t_avail)
VeloSeed.is_about(pid, s5, t_stations)
VeloSeed.is_about(pid, s5, t_subs)
VeloSeed.is_about(pid, s6, t_app)
VeloSeed.is_about(pid, s6, t_brokenbikes)
VeloSeed.is_about(pid, s6, t_pricing)
VeloSeed.is_about(pid, s7, t_stations)
VeloSeed.is_about(pid, s7, t_brokenbikes)
VeloSeed.is_about(pid, s8, t_pricing)
VeloSeed.is_about(pid, s8, t_subs)
VeloSeed.is_about(pid, s10, t_competitors)
VeloSeed.is_about(pid, s10, t_subs)
VeloSeed.is_about(pid, s11, t_latenight)
VeloSeed.is_about(pid, s11, t_stations)
VeloSeed.is_about(pid, s12, t_climate)
VeloSeed.is_about(pid, s12, t_powerusers)

IO.puts("  + #{length(topics)} topics, 28 is_about edges")

# ════════════════════════════════════════════════════════════════════
# EXCERPTS (6)
# ════════════════════════════════════════════════════════════════════

IO.puts("📑 Excerpts…")

e1 = VeloSeed.excerpt(pid, s1,
  "I never know if a bike will be available at my usual station in the morning. I've been late to work three times this month because of it.", 1)
e2 = VeloSeed.excerpt(pid, s4,
  "Power users plan routes around station density, not shortest path. Weather is the only deterrent.", 2)
e3 = VeloSeed.excerpt(pid, s5,
  "23% of rides end at unintended stations because the target was full. Monthly subscribers are 8% of users but 47% of total rides.", nil)
e4 = VeloSeed.excerpt(pid, s10,
  "Apps that offer route planning and predictive availability score 28% higher on user satisfaction scales.", 14)
e5 = VeloSeed.excerpt(pid, s12,
  "Power users are responsible for 47% of avoided trips while being only 8% of riders.", 3)
e6 = VeloSeed.excerpt(pid, s7,
  "Maintenance lag averages 4.2 hours from 'broken bike' report to a technician arriving on-site.", nil)

VeloSeed.is_about(pid, e1, t_avail)
VeloSeed.is_about(pid, e2, t_powerusers)
VeloSeed.is_about(pid, e3, t_subs)
VeloSeed.is_about(pid, e4, t_routes)
VeloSeed.is_about(pid, e5, t_climate)
VeloSeed.is_about(pid, e6, t_brokenbikes)

excerpts = [e1, e2, e3, e4, e5, e6]
IO.puts("  + #{length(excerpts)} excerpts")

# ════════════════════════════════════════════════════════════════════
# INSIGHTS (15)
# ════════════════════════════════════════════════════════════════════

IO.puts("💡 Insights…")

i1 = VeloSeed.insight(pid, "Bike availability anxiety drives morning frustration",
  "Commuters experience anxiety about bike availability during morning rush hours. The gap between checking the app at home and arriving at the station creates a reliability problem.", [c1, c5])

i2 = VeloSeed.insight(pid, "Billing transparency is the #1 support driver",
  "26% of all support tickets are billing confusion. Users don't anticipate overage charges on the monthly plan.", [c2, c8])

i3 = VeloSeed.insight(pid, "Power users treat the service as primary transport",
  "Users riding 10+ times/week consider the bike their primary mode of transportation. They plan routes around station availability, not distance. Reliability is a daily-routine concern.", [c4])

i4 = VeloSeed.insight(pid, "Station density at transit hubs is the critical bottleneck",
  "12 station depletion events/day concentrated at 15 transit hub stations. 23% of rides end at unintended stations.", [c5])

i5 = VeloSeed.insight(pid, "Broken-bike charges erode trust faster than any other issue",
  "28 of 200 reviews mention being charged for broken bikes. The user did nothing wrong but was punished.", [c6])

i6 = VeloSeed.insight(pid, "Subscription density carries the network",
  "8% of users (subscribers) drive 47% of rides. The economic backbone is concentrated and price-sensitive.", [c5, c8])

i7 = VeloSeed.insight(pid, "Operators routinely override rebalancing routing",
  "Field study: rebalancing trucks reach depleted stations in 22min during peak but >2h off-peak. Operators override the routing software when they know better.", [c7])

i8 = VeloSeed.insight(pid, "Late-night usage is a saturation pattern",
  "10pm-2am usage doubled YoY; cluster departures from entertainment districts deplete 4 popular drop-offs to <5% by 11pm.", [c11])

i9 = VeloSeed.insight(pid, "Climate impact is concentrated in power users",
  "Power users displace 47% of avoided car-trips while being 8% of users. Climate ROI per user is non-uniform.", [c12])

i10 = VeloSeed.insight(pid, "App performance regression is OS-specific",
  "Android 14 reproducibly crashes on map view (45 tickets). The fix is bounded; impact is broad.", [c2])

i11 = VeloSeed.insight(pid, "Pricing communication, not pricing, is the real problem",
  "Only 12% understand pricing on first try. 43% are price-insensitive — they'll pay anything reasonable if they understand it.", [c8], "draft")

i12 = VeloSeed.insight(pid, "Predictive availability would beat real-time on satisfaction",
  "Industry data: apps with predictive availability score 28% higher satisfaction. Velo today only shows present-tense availability.", [c10])

i13 = VeloSeed.insight(pid, "Network reliability and station rebalancing are coupled",
  "Power users' reliability concerns map directly to station depletion which maps to rebalancing operations. Treat them as one system, not two.", [c4, c5, c7])

i14 = VeloSeed.insight(pid, "Engineering capacity is the binding constraint, not ideas",
  "7 engineers; 2 on rebalancing, 3 on consumer apps, 2 on platform — and a billing migration is in flight. Most product ideas can't ship in Q2.", [c9])

i15 = VeloSeed.insight(pid, "Subscription pricing has elastic headroom",
  "38% of users would tolerate a $5/mo increase if reliability improved. Subscription pricing is not at the ceiling.", [c8])

insights = [i1, i2, i3, i4, i5, i6, i7, i8, i9, i10, i11, i12, i13, i14, i15]
IO.puts("  + #{length(insights)} insights")

# ════════════════════════════════════════════════════════════════════
# DECISIONS (8)
# ════════════════════════════════════════════════════════════════════

IO.puts("🎯 Decisions…")

d1 = VeloSeed.decision(pid, "Build predictive availability into the app",
  "Replace present-tense availability with predictions based on usage curves and rebalancing operations.",
  ["keep present-tense only", "third-party data feed"])

d2 = VeloSeed.decision(pid, "Auto-refund within 5 minutes of broken-bike report",
  "Trust users by default; auto-refund any ride flagged within 5 minutes of dock with photo evidence.",
  ["case-by-case manual refund", "no automatic refund"])

d3 = VeloSeed.decision(pid, "Reframe pricing UI around outcomes, not minutes",
  "Show users 'how many rides this month' and 'projected month total' rather than the underlying minute math.",
  ["leave pricing UI alone", "lower price visibility"])

d4 = VeloSeed.decision(pid, "Invest in transit-hub station expansion",
  "Add 8 stations near identified depletion hot-spots over Q2-Q3. Defer outer-ring expansion.", [])

d5 = VeloSeed.decision(pid, "Ship a Commuter Mode for power users",
  "Offer pre-planned routes, station-issue alerts, and stat tracking. Targeted at the 8% who drive 47% of rides.",
  ["leave power users on default UX"])

d6 = VeloSeed.decision(pid, "Hold pricing flat through Q3 2026",
  "We have headroom but won't use it until reliability improves. Earn the increase first.",
  ["raise $5/mo Q2", "lower pricing to compete with Lime"])

d7 = VeloSeed.decision(pid, "Late-night station rebalancing program",
  "Add 1 truck shift between 10pm and 2am targeting the 4 saturating stations.", [])

d8 = VeloSeed.decision(pid, "Pause non-critical UX work during billing migration",
  "Engineering capacity goes to billing migration + reliability fixes through end of Q2. New surface area frozen.", ["partial freeze"])

decisions = [d1, d2, d3, d4, d5, d6, d7, d8]
IO.puts("  + #{length(decisions)} decisions")

# ════════════════════════════════════════════════════════════════════
# REQUIREMENTS (12)
# ════════════════════════════════════════════════════════════════════

IO.puts("✅ Requirements…")

r1 = VeloSeed.requirement(pid, "App predicts station availability 15min ahead",
  "The app must show a predicted-availability number for any station within 15 minutes of the user's current location.", [i1.id, i12.id])

r2 = VeloSeed.requirement(pid, "Broken-bike report → instant refund within session",
  "User reports broken bike; refund issued automatically within 1 minute of report submission.", [i5.id])

r3 = VeloSeed.requirement(pid, "Pricing screen shows monthly trajectory",
  "Show 'X rides this month, projected Y by end of month' and total cost in dollars.", [i2.id, i11.id])

r4 = VeloSeed.requirement(pid, "Commuter Mode toggle in app",
  "A 'Commuter Mode' setting enables route pre-planning, station alerts, and a stats panel.", [i3.id, i6.id])

r5 = VeloSeed.requirement(pid, "Station alert push notifications",
  "Subscribers get push notifications when a tracked station drops below 2 bikes.", [i1.id, i3.id])

r6 = VeloSeed.requirement(pid, "Android 14 map crash fix",
  "Reproducible crash on map view must be resolved before next release.", [i10.id])

r7 = VeloSeed.requirement(pid, "8 new stations near transit hubs",
  "Survey, permit, and install 8 new stations at depletion hot-spots within Q2-Q3.", [i4.id])

r8 = VeloSeed.requirement(pid, "Late-night rebalancing truck shift",
  "Add operational shift covering 10pm-2am targeting saturating stations.", [i8.id])

r9 = VeloSeed.requirement(pid, "Operator-overridable routing UI",
  "Field operators can override the rebalancing routing software with one tap.", [i7.id])

r10 = VeloSeed.requirement(pid, "CO2-saved counter in user profile",
  "Show kilograms of CO2 the user has displaced (drives Climate Impact storytelling).", [i9.id])

r11 = VeloSeed.requirement(pid, "Map load p95 < 1.5s",
  "Map view must load in under 1.5 seconds at the 95th percentile.", [i10.id])

r12 = VeloSeed.requirement(pid, "Subscriber price stays flat through Q3 2026",
  "No subscription price increase until reliability KPIs are met.", [i15.id])

requirements = [r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12]
IO.puts("  + #{length(requirements)} requirements")

# ════════════════════════════════════════════════════════════════════
# ARCHITECTURE (8)
# ════════════════════════════════════════════════════════════════════

IO.puts("🏗  Architecture…")

ar1 = VeloSeed.arch(pid, "Availability prediction service", "ML service consuming usage curves + rebalancing data. Forecasts station bike count 15-30min ahead.", "system_design")
ar2 = VeloSeed.arch(pid, "Broken-bike refund pipeline", "Sync between dock-event stream, trip log, and billing. Issues refund without operator review when criteria match.", "system_design")
ar3 = VeloSeed.arch(pid, "Push notification service", "Subscriber-facing service feeding tracked-station alerts. Backed by station event stream.", "system_design")
ar4 = VeloSeed.arch(pid, "Rebalancing routing API", "Operator-facing API with override endpoint. Routes consume real-time station counts + historical patterns.", "api_contract")
ar5 = VeloSeed.arch(pid, "User profile metrics aggregator", "Materialised view computing per-user CO2 saved, ride totals, distance over time.", "data_model")
ar6 = VeloSeed.arch(pid, "Map service caching layer", "CDN cache for map tiles + station overlays. Targeted at p95 latency.", "infra_choice")
ar7 = VeloSeed.arch(pid, "Trip event stream (Kafka topic)", "Source-of-truth event stream consumed by billing, analytics, refund pipeline.", "system_design")
ar8 = VeloSeed.arch(pid, "Station depletion detector", "Stream consumer flagging stations dropping below configurable thresholds; emits alerts.", "system_design")

architectures = [ar1, ar2, ar3, ar4, ar5, ar6, ar7, ar8]
IO.puts("  + #{length(architectures)} architecture nodes")

# ════════════════════════════════════════════════════════════════════
# DESIGN (8)
# ════════════════════════════════════════════════════════════════════

IO.puts("🎨 Design…")

de1 = VeloSeed.design(pid, "Predicted-availability map pin", "Map pin shows predicted bike count with a confidence band; not a single number.", "wireframe")
de2 = VeloSeed.design(pid, "Refund confirmation UX", "Inline 'we've refunded you' card after broken-bike report. No modals.", "interaction_pattern")
de3 = VeloSeed.design(pid, "Pricing trajectory module", "Profile page card: 'this month so far' + 'projected month total' with sparkline.", "component_spec")
de4 = VeloSeed.design(pid, "Commuter Mode toggle", "Settings page toggle + onboarding tour the first time the mode is enabled.", "user_flow")
de5 = VeloSeed.design(pid, "Tracked-station list", "List view of stations the user is watching; one-swipe to remove.", "wireframe")
de6 = VeloSeed.design(pid, "Operator routing override panel", "Single-screen route-vs-override comparison. One-tap switch.", "interaction_pattern")
de7 = VeloSeed.design(pid, "CO2 counter on user profile", "Hero metric on profile page; weekly delta below.", "component_spec")
de8 = VeloSeed.design(pid, "Map empty-state", "When a region has no nearby stations, surface a 'find nearest station' affordance.", "wireframe")

designs = [de1, de2, de3, de4, de5, de6, de7, de8]
IO.puts("  + #{length(designs)} design nodes")

# ════════════════════════════════════════════════════════════════════
# TASKS (18)
# ════════════════════════════════════════════════════════════════════

IO.puts("📋 Tasks…")

tasks = [
  VeloSeed.task(pid, "Spec the prediction model accuracy targets", "Define MAE thresholds per station class.", "ready", "high"),
  VeloSeed.task(pid, "Wire dock-event stream to refund pipeline", "End-to-end test with 10 broken-bike scenarios.", "in_progress", "critical", "Devon Park"),
  VeloSeed.task(pid, "Build pricing trajectory React component", "Sparkline + forecast line + month-to-date totals.", "ready", "medium"),
  VeloSeed.task(pid, "Implement Commuter Mode settings toggle", "Settings page toggle + persisted user pref.", "backlog", "medium"),
  VeloSeed.task(pid, "Push notification service POC", "Test with 100 subscribers in staging.", "ready", "high"),
  VeloSeed.task(pid, "Diagnose Android 14 map crash", "Repro on Pixel 8; identify root cause.", "in_progress", "critical", "Lin Wong"),
  VeloSeed.task(pid, "Survey 4 transit-hub station candidate sites", "Coordinate with city permits team.", "backlog", "high"),
  VeloSeed.task(pid, "Define late-night truck shift hand-off SOP", "Operations doc covering 10pm-2am.", "ready", "medium", "Aisha Rahman"),
  VeloSeed.task(pid, "Build operator routing override endpoint", "POST /rebalancing/override with audit log.", "backlog", "medium"),
  VeloSeed.task(pid, "CO2 counter analytics: per-user aggregation", "Materialised view + cron refresh.", "backlog", "low"),
  VeloSeed.task(pid, "Map p95 latency profiling", "Identify which network calls dominate.", "in_progress", "high"),
  VeloSeed.task(pid, "Pricing trajectory copywriting", "Get marketing review on terminology.", "backlog", "low"),
  VeloSeed.task(pid, "Commuter Mode onboarding tour", "First-run animation + 3 tooltip steps.", "backlog", "low"),
  VeloSeed.task(pid, "Refund-pipeline end-to-end test suite", "Cover the 10 known refund scenarios.", "ready", "high"),
  VeloSeed.task(pid, "Tracked-station list UI", "List + swipe-to-remove.", "backlog", "medium"),
  VeloSeed.task(pid, "Map tile CDN configuration", "Set cache TTLs + per-zoom-level rules.", "ready", "medium"),
  VeloSeed.task(pid, "Update support runbook for auto-refund", "Train support on the new flow.", "ready", "medium", "Aisha Rahman"),
  VeloSeed.task(pid, "Late-night truck routing — pilot", "Run pilot for 2 weeks at the 4 saturating stations.", "backlog", "high")
]

IO.puts("  + #{length(tasks)} tasks")

# ════════════════════════════════════════════════════════════════════
# LEARNINGS, STRATEGIES, CONSTRAINTS
# ════════════════════════════════════════════════════════════════════

IO.puts("📚 Learnings, strategies, constraints…")

l1 = VeloSeed.learning(pid, "Refund-by-default outperformed case-by-case", "Pilot week of auto-refund saw 43% fewer trust-eroding tickets and zero refund abuse.", "experiment_result")
l2 = VeloSeed.learning(pid, "Power users self-organise around station mental maps", "Repeated across interviews: power users build private mental models of station behaviour.", "retrospective")
l3 = VeloSeed.learning(pid, "Pricing complaints fell 18% with simpler trajectory copy", "A/B from a previous quarter: simpler pricing copy materially reduced complaints.", "experiment_result")
l4 = VeloSeed.learning(pid, "Permitting cycle for new stations is 9-13 weeks", "Range from prior expansion. Plan around this.", "post_mortem")
l5 = VeloSeed.learning(pid, "Late-night usage rebalancing must be human-led", "Automated routing fails on cluster-departure patterns. Truck shift outperformed algorithm.", "experiment_result")

st1 = VeloSeed.strategy(pid, "Earn the price increase before you take it",
  "We have headroom on subscriber pricing but customers correctly tie price to reliability. We make the network unmistakably more reliable, then revisit pricing.")
st2 = VeloSeed.strategy(pid, "Concentrate engineering on the rebalancing/billing axis",
  "These two systems generate >70% of user-facing problems. While the billing migration is in flight, we deprioritise everything else.")
st3 = VeloSeed.strategy(pid, "Power users are the climate-impact lever",
  "8% of users → 47% of avoided trips. Designing for them disproportionately advances the climate story.")

ct1 = VeloSeed.constraint(pid, "Billing migration freeze", "No surface-area changes to ride-billing while the migration is in flight.", "technical", "strict")
ct2 = VeloSeed.constraint(pid, "Pricing flat through Q3 2026", "No subscription price increases until reliability KPIs are met.", "business", "strict")
ct3 = VeloSeed.constraint(pid, "City station permits", "New stations require a 9-13 week permitting cycle from city.", "process", "advisory")
ct4 = VeloSeed.constraint(pid, "Refund abuse rate < 0.5%", "Auto-refund stays on as long as abuse rate stays under 0.5% monthly.", "business", "strict")

learnings = [l1, l2, l3, l4, l5]
strategies = [st1, st2, st3]
constraints = [ct1, ct2, ct3, ct4]
IO.puts("  + #{length(learnings)} learnings, #{length(strategies)} strategies, #{length(constraints)} constraints")

# ════════════════════════════════════════════════════════════════════
# EDGES — lineage / supports / contradicts / depends
# ════════════════════════════════════════════════════════════════════

IO.puts("🔗 Wiring graph edges…")

# Source → insight lineage
for {src, ins} <- [
      {s1, i1}, {s5, i1},
      {s2, i2}, {s8, i2},
      {s4, i3},
      {s5, i4},
      {s6, i5},
      {s5, i6}, {s8, i6},
      {s7, i7},
      {s11, i8},
      {s12, i9},
      {s2, i10},
      {s8, i11},
      {s10, i12},
      {s4, i13}, {s5, i13}, {s7, i13},
      {s9, i14},
      {s8, i15}
    ] do
  VeloSeed.link(pid, src, ins, "lineage")
end

# Insight → decision lineage / supports
for {ins, dec} <- [
      {i1, d1}, {i12, d1},
      {i5, d2},
      {i2, d3}, {i11, d3},
      {i4, d4},
      {i3, d5}, {i6, d5},
      {i15, d6}, {i14, d6},
      {i8, d7},
      {i14, d8}
    ] do
  VeloSeed.link(pid, ins, dec, "lineage")
end

# Decision → requirement lineage
for {dec, req} <- [
      {d1, r1}, {d1, r5},
      {d2, r2},
      {d3, r3},
      {d5, r4}, {d5, r5},
      {d4, r7},
      {d7, r8},
      {d6, r12}
    ] do
  VeloSeed.link(pid, dec, req, "lineage")
end

# Requirement → architecture
for {req, ar} <- [
      {r1, ar1},
      {r2, ar2},
      {r5, ar3},
      {r9, ar4},
      {r10, ar5},
      {r11, ar6},
      {r2, ar7},
      {r1, ar8}
    ] do
  VeloSeed.link(pid, req, ar, "lineage")
end

# Requirement → design
for {req, de} <- [
      {r1, de1},
      {r2, de2},
      {r3, de3},
      {r4, de4},
      {r5, de5},
      {r9, de6},
      {r10, de7},
      {r11, de8}
    ] do
  VeloSeed.link(pid, req, de, "lineage")
end

# Requirement → task
for {req, t} <- [
      {r1, Enum.at(tasks, 0)},
      {r2, Enum.at(tasks, 1)},
      {r3, Enum.at(tasks, 2)},
      {r4, Enum.at(tasks, 3)},
      {r5, Enum.at(tasks, 4)},
      {r6, Enum.at(tasks, 5)},
      {r7, Enum.at(tasks, 6)},
      {r8, Enum.at(tasks, 7)},
      {r9, Enum.at(tasks, 8)},
      {r10, Enum.at(tasks, 9)},
      {r11, Enum.at(tasks, 10)},
      {r3, Enum.at(tasks, 11)},
      {r4, Enum.at(tasks, 12)},
      {r2, Enum.at(tasks, 13)},
      {r5, Enum.at(tasks, 14)},
      {r11, Enum.at(tasks, 15)},
      {r2, Enum.at(tasks, 16)},
      {r8, Enum.at(tasks, 17)}
    ] do
  VeloSeed.link(pid, req, t, "lineage")
end

# Constraint → things it constrains
VeloSeed.link(pid, ct1, ar2, "constrains")
VeloSeed.link(pid, ct1, ar7, "constrains")
VeloSeed.link(pid, ct2, d6, "supports")
VeloSeed.link(pid, ct3, r7, "constrains")
VeloSeed.link(pid, ct4, d2, "constrains")

# Strategy → decision (it shapes)
VeloSeed.link(pid, st1, d6, "supports")
VeloSeed.link(pid, st2, d8, "supports")
VeloSeed.link(pid, st3, d5, "supports")

# Learning → decision (validates / informs)
VeloSeed.link(pid, l1, d2, "supports")
VeloSeed.link(pid, l3, d3, "supports")
VeloSeed.link(pid, l5, d7, "supports")

# A contradiction (i6 says subscriber base is concentrated/fragile; i15 says elastic headroom)
VeloSeed.link(pid, i6, i15, "contradicts")

# Task → task dependencies
VeloSeed.link(pid, Enum.at(tasks, 0), Enum.at(tasks, 1), "dependency")
VeloSeed.link(pid, Enum.at(tasks, 13), Enum.at(tasks, 1), "dependency")
VeloSeed.link(pid, Enum.at(tasks, 16), Enum.at(tasks, 1), "dependency")

IO.puts("  + lineage / supports / constrains / contradicts / dependency edges wired")

# ════════════════════════════════════════════════════════════════════
# COUNTS
# ════════════════════════════════════════════════════════════════════

node_count =
  Repo.aggregate(
    from(n in HydraX.Graph.Node, where: n.project_id == ^pid),
    :count,
    :id
  )

edge_count =
  Repo.aggregate(
    from(r in HydraX.Graph.NodeRelationship, where: r.project_id == ^pid),
    :count,
    :id
  )

IO.puts("")
IO.puts("✅ Velo seeded.")
IO.puts("   Project:  id=#{pid} name=#{project.name}")
IO.puts("   Nodes:    #{node_count}")
IO.puts("   Edges:    #{edge_count}")
