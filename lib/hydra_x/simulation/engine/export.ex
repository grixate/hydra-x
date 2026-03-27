defmodule HydraX.Simulation.Engine.Export do
  @moduledoc """
  Export simulation data to JSON and Markdown formats.
  """

  alias HydraX.Simulation.Engine.Replay
  alias HydraX.Simulation.Report.Analyzer

  @doc """
  Export full simulation data as a JSON-encodable map.
  """
  @spec to_json(integer()) :: map()
  def to_json(simulation_id) do
    simulation = HydraX.Repo.get!(HydraX.Simulation.Schema.Simulation, simulation_id)
    timeline = Replay.build_timeline(simulation_id)

    agent_profiles = load_agent_profiles(simulation_id)
    reports = load_reports(simulation_id)

    tick_data =
      Enum.map(timeline, fn t ->
        Map.put(t, :action_count, 0)
        |> Map.put(:notable_events, t[:events] || [])
      end)

    statistical_summary = Analyzer.analyze(to_string(simulation_id), tick_data, agent_profiles)

    %{
      simulation: %{
        id: simulation.id,
        name: simulation.name,
        status: simulation.status,
        config: simulation.config,
        total_ticks: simulation.total_ticks,
        total_llm_calls: simulation.total_llm_calls,
        total_tokens_used: simulation.total_tokens_used,
        total_cost_cents: simulation.total_cost_cents,
        started_at: simulation.started_at,
        completed_at: simulation.completed_at
      },
      statistical_summary: statistical_summary,
      agent_profiles: agent_profiles,
      timeline: timeline,
      reports:
        Enum.map(reports, fn r ->
          %{content: r.content, generated_at: r.generated_at}
        end)
    }
  end

  @doc """
  Export simulation data as a Markdown string.
  """
  @spec to_markdown(integer()) :: String.t()
  def to_markdown(simulation_id) do
    data = to_json(simulation_id)
    sim = data.simulation
    stats = data.statistical_summary

    sections = [
      "# Simulation Export: #{sim.name}",
      "",
      "## Overview",
      "- **Status**: #{sim.status}",
      "- **Total Ticks**: #{sim.total_ticks}",
      "- **Total LLM Calls**: #{sim.total_llm_calls}",
      "- **Total Cost**: $#{(sim.total_cost_cents || 0) / 100}",
      "- **Started**: #{sim.started_at || "N/A"}",
      "- **Completed**: #{sim.completed_at || "N/A"}",
      "",
      "## Tier Distribution",
      tier_distribution_md(stats),
      "",
      "## Agent Profiles",
      agents_md(data.agent_profiles),
      "",
      "## Timeline",
      timeline_md(data.timeline),
      "",
      "## Reports",
      reports_md(data.reports)
    ]

    Enum.join(sections, "\n")
  end

  @doc """
  Write export to a file.
  """
  @spec write_file(integer(), String.t(), :json | :markdown) :: :ok | {:error, term()}
  def write_file(simulation_id, path, format \\ :json) do
    content =
      case format do
        :json -> Jason.encode!(to_json(simulation_id), pretty: true)
        :markdown -> to_markdown(simulation_id)
      end

    File.write(path, content)
  end

  # --- Private ---

  defp load_agent_profiles(simulation_id) do
    import Ecto.Query

    HydraX.Repo.all(
      from p in HydraX.Simulation.Schema.SimAgentProfile,
        where: p.simulation_id == ^simulation_id
    )
    |> Enum.map(fn p ->
      persona = p.persona || %{}
      %{name: persona["name"] || p.agent_key, role: persona["role"] || "Agent"}
    end)
  end

  defp load_reports(simulation_id) do
    import Ecto.Query

    HydraX.Repo.all(
      from r in HydraX.Simulation.Schema.SimReport,
        where: r.simulation_id == ^simulation_id,
        order_by: [desc: r.generated_at]
    )
  end

  defp tier_distribution_md(stats) do
    dist = stats[:tier_distribution] || %{}
    pct = stats[:tier_percentages] || %{}

    """
    | Tier | Count | Percentage |
    |------|-------|------------|
    | Routine | #{dist[:routine] || 0} | #{pct[:routine] || 0}% |
    | Emotional | #{dist[:emotional] || 0} | #{pct[:emotional] || 0}% |
    | Complex (LLM) | #{dist[:complex] || 0} | #{pct[:complex] || 0}% |
    | Negotiation (LLM) | #{dist[:negotiation] || 0} | #{pct[:negotiation] || 0}% |
    """
  end

  defp agents_md(profiles) do
    profiles
    |> Enum.map(fn p -> "- **#{p.name}** — #{p.role}" end)
    |> Enum.join("\n")
    |> case do
      "" -> "_No agent profiles recorded._"
      md -> md
    end
  end

  defp timeline_md(timeline) do
    timeline
    |> Enum.take(20)
    |> Enum.map(fn t ->
      event_count = length(t[:events] || [])

      "- **Tick #{t.tick_number}**: #{event_count} events, #{t.llm_calls} LLM calls, #{t.duration_us}us"
    end)
    |> Enum.join("\n")
    |> case do
      "" -> "_No ticks recorded._"
      md -> md
    end
  end

  defp reports_md(reports) do
    reports
    |> Enum.map(fn r -> "### Report (#{r.generated_at})\n\n#{r.content}" end)
    |> Enum.join("\n\n---\n\n")
    |> case do
      "" -> "_No reports generated._"
      md -> md
    end
  end
end
