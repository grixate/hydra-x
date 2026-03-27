defmodule HydraX.Simulation.Report.Templates do
  @moduledoc """
  Report prompt templates for post-simulation synthesis.
  """

  @doc """
  Build the system prompt for report generation.
  """
  def system_prompt do
    """
    You are a strategic analysis expert. You are generating a post-simulation
    report for a business strategy simulation. Your report should:

    1. Summarize the key dynamics that emerged during the simulation
    2. Identify the most impactful events and turning points
    3. Analyze agent behavior patterns and group dynamics
    4. Highlight surprising or counter-intuitive outcomes
    5. Provide strategic insights and recommendations

    Write in a professional, concise style suitable for executive review.
    Use markdown formatting with clear section headers.
    """
  end

  @doc """
  Build the user prompt with simulation data for report generation.
  """
  def report_prompt(statistical_summary, agent_profiles, key_events) do
    """
    ## Simulation Data

    ### Overview
    - Total ticks: #{statistical_summary.total_ticks}
    - Total agents: #{statistical_summary.agent_count}
    - Total actions taken: #{statistical_summary.total_actions}
    - Simulation duration: #{statistical_summary.total_duration_ms}ms
    - Estimated cost: $#{statistical_summary.cost_estimate_cents / 100}

    ### Decision Tier Distribution
    #{format_tier_distribution(statistical_summary.tier_percentages)}

    ### Agent Profiles
    #{format_agents(agent_profiles)}

    ### Key Events
    #{format_events(key_events)}

    ### LLM Usage
    - Total LLM calls: #{statistical_summary.total_llm_calls}
    - Complex (cheap LLM) decisions: #{Map.get(statistical_summary.tier_distribution, :complex, 0)}
    - Negotiation (frontier LLM) decisions: #{Map.get(statistical_summary.tier_distribution, :negotiation, 0)}

    ---

    Generate a comprehensive strategy simulation report based on this data.
    Focus on emergent dynamics, key turning points, and actionable insights.
    """
  end

  defp format_tier_distribution(percentages) do
    """
    - Routine (rules engine): #{percentages.routine}%
    - Emotional (rules engine): #{percentages.emotional}%
    - Complex (cheap LLM): #{percentages.complex}%
    - Negotiation (frontier LLM): #{percentages.negotiation}%
    """
  end

  defp format_agents(profiles) do
    profiles
    |> Enum.take(20)
    |> Enum.map_join("\n", fn p ->
      name = Map.get(p, :name, "Unknown")
      role = Map.get(p, :role, "Participant")
      "- **#{name}** (#{role})"
    end)
  end

  defp format_events(events) do
    events
    |> Enum.take(10)
    |> Enum.map_join("\n", fn e ->
      type = Map.get(e, :type, :unknown)
      stakes = Map.get(e, :stakes, 0)
      desc = Map.get(e, :description, "")
      "- [#{type}] Stakes: #{stakes} — #{desc}"
    end)
  end
end
