defmodule Mix.Tasks.HydraX.Stream.Seed do
  @moduledoc """
  Seed a project with ~100 synthetic Stream entries distributed across the
  last 30 days, per `stream-visual-design-spec.md` §7. Populates all three
  tabs (activity / needs_you / blockers) using real `StreamEntry` records
  so the design can be evaluated at realistic volume.

  Usage:

      mix hydra_x.stream.seed PROJECT_ID [--count N] [--keep]

  Options:
    --count N   Total entries to create (default 100)
    --keep      Do not clear existing stream_entries for the project

  Dev-only: the task refuses to run in :prod.
  """

  use Mix.Task

  import Ecto.Query

  alias HydraX.Product.StreamEntry
  alias HydraX.Repo

  @shortdoc "Seed ~100 Stream entries for design evaluation"

  @context_types ~w(node source session flow task)

  # Sentence-form title + optional summary pools per activity kind.
  @activity_templates [
    {"researcher", "Extracted 8 insights from Q3 user interviews",
     "Themes: pricing sensitivity, onboarding friction, trust signals.", "source"},
    {"researcher", "Pulled 12 quotes from founder interview transcripts",
     "Tagged by topic and added to the Insight index.", "source"},
    {"researcher", "Indexed 47 chunks from the Q3 financial report", nil, "source"},
    {"researcher", "Summarised competitor pricing pages",
     "6 competitors compared across 4 tiers.", "source"},
    {"strategist", "Proposed restructuring the pricing bets into 3 themes",
     "Enterprise / self-serve / platform.", "node"},
    {"strategist", "Drafted a vision statement for the Q3 push", nil, "node"},
    {"strategist", "Consolidated 9 bets into 3 themes", "You accepted the proposal.", "node"},
    {"architect", "Mapped the auth subsystem dependencies",
     "14 nodes, 22 edges — now visible in Graph.", "node"},
    {"architect", "Generated a spec for the user model decision", nil, "node"},
    {"architect", "Drafted provider integration plan",
     "Covers retries, rate limits, and failure modes.", "node"},
    {"designer", "Drafted Command Center mocks", "Three variants in Figma, ready for review.",
     "node"},
    {"designer", "Refined the empty state copy across Stream", nil, nil},
    {"memory_agent", "Indexed 60 new chunks from recently added sources", nil, "source"},
    {"memory_agent", "Rebuilt embeddings for Library sources", "Triggered after schema change.",
     "source"},
    {"coherence", "Found a contradiction between Pricing bet and Upgrade requirement",
     "Clash: free tier vs. required payment on upgrade.", "node"},
    {"coherence", "Flagged a stale insight against recent interviews", nil, "node"},
    {"continuous_research", "New competitor pricing change detected",
     "Acme bumped their Pro tier from $29 to $39.", "source"},
    {"continuous_research", "Changelog update from a tracked competitor", nil, "source"},
    {nil, "You accepted Strategist's proposal to restructure pricing bets", nil, "node"},
    {nil, "You added 3 sources to Library", nil, "source"},
    {nil, "You created a new bet under Enterprise", nil, "node"},
    {nil, "You dismissed a Coherence proposal", nil, "node"},
    {"researcher", "Task failed while scraping competitor pricing",
     "Upstream returned 503 after 3 retries.", "task"},
    {"architect", "Task completed: mapped the billing flow", nil, "flow"}
  ]

  @needs_you_templates [
    {"coherence", "Found 2 contradictions in your strategic bets", "Review to merge or reject.",
     "node"},
    {"researcher", "Proposes 8 new insight nodes from Q3 interviews",
     "Each insight links back to source quotes.", "source"},
    {"strategist", "Proposes consolidating 9 bets into 3 themes",
     "Restructure — accept to apply across the board.", "node"},
    {"architect", "Waiting on decision: pricing-floor constraint",
     "Needed to unblock the user-model spec.", "node"},
    {"designer", "Proposes a new Stream layout variant", nil, "node"},
    {"memory_agent", "Waiting on your choice of source priority", nil, "source"},
    {"coherence", "Flagged a stale decision against new evidence",
     "Review within 48h or it will auto-dismiss.", "node"}
  ]

  @blocker_templates [
    {"researcher", "Cannot access source PDF — file no longer available",
     "Replace the source or cancel the task.", "source"},
    {"architect", "Task failed: unable to generate spec — missing key constraint",
     "Architect needs the pricing-floor decision before retrying.", "node"},
    {"strategist", "Stalled waiting on input for 3 days", nil, "node"},
    {"coherence", "High-severity contradiction open since last week",
     "Pricing bet ↔ Upgrade requirement.", "node"},
    {"researcher", "Rate-limited by upstream provider", "Retry window opens in ~2h.", "task"},
    {"memory_agent", "Index job failed: embeddings provider unreachable", nil, "source"}
  ]

  @impl Mix.Task
  def run(argv) do
    if Mix.env() == :prod do
      Mix.raise("hydra_x.stream.seed is dev-only and refuses to run in :prod")
    end

    {opts, args} =
      OptionParser.parse!(argv, strict: [count: :integer, keep: :boolean], aliases: [c: :count])

    project_id =
      case args do
        [pid] -> String.to_integer(pid)
        _ -> Mix.raise("Usage: mix hydra_x.stream.seed PROJECT_ID [--count N] [--keep]")
      end

    total = Keyword.get(opts, :count, 100)
    keep? = Keyword.get(opts, :keep, false)

    Mix.Task.run("app.start")

    unless keep? do
      Mix.shell().info("Clearing existing stream_entries for project #{project_id}...")
      Repo.delete_all(from e in StreamEntry, where: e.project_id == ^project_id)
    end

    now = DateTime.utc_now()
    :rand.seed(:exsss, {project_id, total, 42})

    # 70% activity / 15% needs_you / 15% blockers.
    activity_n = max(round(total * 0.70), 1)
    needs_you_n = max(round(total * 0.15), 1)
    blockers_n = max(total - activity_n - needs_you_n, 1)

    rows =
      build_rows("activity", activity_n, @activity_templates, project_id, now, span_days: 30) ++
        build_rows("needs_you", needs_you_n, @needs_you_templates, project_id, now,
          span_days: 5,
          min_age_hours: 4
        ) ++
        build_rows("blockers", blockers_n, @blocker_templates, project_id, now,
          span_days: 21,
          min_age_hours: 12
        )

    {inserted, _} = Repo.insert_all(StreamEntry, rows)

    Mix.shell().info(
      "Seeded #{inserted} stream entries for project #{project_id} " <>
        "(activity=#{activity_n}, needs_you=#{needs_you_n}, blockers=#{blockers_n})"
    )
  end

  defp build_rows(tab, n, templates, project_id, now, opts) do
    span_days = Keyword.get(opts, :span_days, 30)
    min_age_hours = Keyword.get(opts, :min_age_hours, 0)

    for _ <- 1..n do
      {agent, title, summary, ctx_type} = Enum.random(templates)
      # Skew density toward recent (quadratic decay from now).
      age_seconds = recent_weighted_age(span_days, min_age_hours)
      inserted_at = DateTime.add(now, -age_seconds, :second)

      %{
        project_id: project_id,
        tab: tab,
        source_agent_id: agent,
        title: title,
        summary: summary,
        context_type: ctx_type || Enum.random(@context_types),
        context_id: :rand.uniform(999),
        read_at: nil,
        actioned_at: nil,
        source_task_id: nil,
        inserted_at: inserted_at
      }
    end
  end

  # Quadratic skew: more items closer to now. `t` in [0,1], age = t^2 * max.
  defp recent_weighted_age(span_days, min_age_hours) do
    t = :rand.uniform()
    max_age = span_days * 24 * 3600
    min_age = min_age_hours * 3600
    min_age + round(t * t * (max_age - min_age))
  end
end
