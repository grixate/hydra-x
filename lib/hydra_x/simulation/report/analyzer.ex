defmodule HydraX.Simulation.Report.Analyzer do
  @moduledoc """
  Statistical analysis of simulation data.

  Computes tier distribution, cost breakdown, key event identification,
  and agent behavior summaries from tick and event data.
  """

  @doc """
  Analyze a simulation's data and return a statistical summary.
  """
  @spec analyze(String.t(), [map()], [map()]) :: map()
  def analyze(sim_id, tick_data_list, agent_profiles) do
    %{
      sim_id: sim_id,
      total_ticks: length(tick_data_list),
      total_actions: total_actions(tick_data_list),
      tier_distribution: aggregate_tiers(tick_data_list),
      tier_percentages: tier_percentages(tick_data_list),
      total_llm_calls: total_llm_calls(tick_data_list),
      total_duration_ms: total_duration(tick_data_list),
      avg_tick_duration_ms: avg_tick_duration(tick_data_list),
      agent_count: length(agent_profiles),
      key_events: extract_key_events(tick_data_list),
      cost_estimate_cents: estimate_cost(tick_data_list)
    }
  end

  defp total_actions(ticks) do
    Enum.sum(Enum.map(ticks, fn t -> Map.get(t, :action_count, 0) end))
  end

  defp aggregate_tiers(ticks) do
    Enum.reduce(ticks, %{routine: 0, emotional: 0, complex: 0, negotiation: 0}, fn tick, acc ->
      tier_counts = Map.get(tick, :tier_counts, %{})
      Map.merge(acc, tier_counts, fn _k, v1, v2 -> v1 + v2 end)
    end)
  end

  defp tier_percentages(ticks) do
    totals = aggregate_tiers(ticks)
    grand_total = totals.routine + totals.emotional + totals.complex + totals.negotiation

    if grand_total > 0 do
      %{
        routine: Float.round(totals.routine / grand_total * 100, 1),
        emotional: Float.round(totals.emotional / grand_total * 100, 1),
        complex: Float.round(totals.complex / grand_total * 100, 1),
        negotiation: Float.round(totals.negotiation / grand_total * 100, 1)
      }
    else
      %{routine: 0.0, emotional: 0.0, complex: 0.0, negotiation: 0.0}
    end
  end

  defp total_llm_calls(ticks) do
    Enum.sum(Enum.map(ticks, fn t -> Map.get(t, :llm_calls, 0) end))
  end

  defp total_duration(ticks) do
    us = Enum.sum(Enum.map(ticks, fn t -> Map.get(t, :duration_us, 0) end))
    div(us, 1_000)
  end

  defp avg_tick_duration(ticks) do
    case length(ticks) do
      0 -> 0
      n -> div(total_duration(ticks), n)
    end
  end

  defp extract_key_events(ticks) do
    ticks
    |> Enum.flat_map(fn t -> Map.get(t, :notable_events, []) end)
    |> Enum.filter(fn e -> Map.get(e, :stakes, 0) > 0.7 or Map.get(e, :is_crisis?, false) end)
    |> Enum.take(10)
  end

  defp estimate_cost(ticks) do
    totals = aggregate_tiers(ticks)
    # Rough cost model: cheap ~$0.14/M tokens, ~100 tokens per call
    # frontier ~$3/M tokens, ~200 tokens per call
    cheap_cost = totals.complex * 100 * 0.14 / 1_000_000
    frontier_cost = totals.negotiation * 200 * 3.0 / 1_000_000
    Float.round((cheap_cost + frontier_cost) * 100, 2)
  end
end
