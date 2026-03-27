defmodule HydraX.Simulation.Report.ReportAgentTest do
  use ExUnit.Case, async: true

  alias HydraX.Simulation.Report.{ReportAgent, Analyzer}

  defp sample_tick_data do
    [
      %{
        tick_number: 0,
        duration_us: 50_000,
        event_count: 3,
        action_count: 5,
        tier_counts: %{routine: 3, emotional: 1, complex: 1, negotiation: 0},
        llm_calls: 1,
        notable_events: [
          %{type: :market_crash, stakes: 0.9, is_crisis?: true, description: "Market crash"},
          %{type: :competitor_move, stakes: 0.6, description: "Competitor launched product"}
        ]
      },
      %{
        tick_number: 1,
        duration_us: 45_000,
        event_count: 2,
        action_count: 5,
        tier_counts: %{routine: 4, emotional: 0, complex: 0, negotiation: 1},
        llm_calls: 1,
        notable_events: [
          %{type: :partnership_offer, stakes: 0.5, description: "Partnership proposed"}
        ]
      }
    ]
  end

  defp sample_agent_profiles do
    [
      %{name: "CFO", role: "Chief Financial Officer"},
      %{name: "CEO", role: "Chief Executive Officer"},
      %{name: "Competitor", role: "Competitor CEO"}
    ]
  end

  describe "generate/2" do
    test "generates a report with mock LLM" do
      mock_llm = fn _request ->
        {:ok, %{content: "# Simulation Report\n\nThe simulation revealed key dynamics..."}}
      end

      {:ok, report} =
        ReportAgent.generate("test_sim",
          tick_data: sample_tick_data(),
          agent_profiles: sample_agent_profiles(),
          llm_fn: mock_llm
        )

      assert report.sim_id == "test_sim"
      assert String.contains?(report.content, "Simulation Report")
      assert report.statistical_summary.total_ticks == 2
      assert report.statistical_summary.total_actions == 10
      assert report.generated_at != nil
    end

    test "handles LLM error gracefully" do
      error_llm = fn _request -> {:error, :provider_unavailable} end

      result =
        ReportAgent.generate("test_sim",
          tick_data: sample_tick_data(),
          agent_profiles: sample_agent_profiles(),
          llm_fn: error_llm
        )

      assert {:error, {:report_generation_failed, :provider_unavailable}} = result
    end
  end

  describe "Analyzer.analyze/3" do
    test "computes statistical summary" do
      summary = Analyzer.analyze("test_sim", sample_tick_data(), sample_agent_profiles())

      assert summary.total_ticks == 2
      assert summary.total_actions == 10
      assert summary.total_llm_calls == 2
      assert summary.agent_count == 3
      assert summary.tier_distribution.routine == 7
      assert summary.tier_distribution.complex == 1
      assert summary.tier_distribution.negotiation == 1
    end

    test "computes tier percentages" do
      summary = Analyzer.analyze("test_sim", sample_tick_data(), sample_agent_profiles())

      assert summary.tier_percentages.routine > 0

      total =
        summary.tier_percentages.routine + summary.tier_percentages.emotional +
          summary.tier_percentages.complex + summary.tier_percentages.negotiation

      assert_in_delta total, 100.0, 0.5
    end

    test "handles empty data" do
      summary = Analyzer.analyze("test_sim", [], [])

      assert summary.total_ticks == 0
      assert summary.total_actions == 0
      assert summary.agent_count == 0
    end
  end
end
