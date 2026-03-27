defmodule HydraX.Simulation.Report.ReportAgent do
  @moduledoc """
  Post-simulation report synthesis using frontier LLM.

  Gathers simulation data, runs statistical analysis, and generates
  a comprehensive strategy report via a single frontier LLM call.
  """

  alias HydraX.Simulation.Report.{Analyzer, Templates}

  @doc """
  Generate a simulation report.

  Options:
  - :llm_fn - custom LLM function for testing
  - :tick_data - pre-collected tick data (skips loading from DB)
  - :agent_profiles - pre-collected agent profiles
  """
  @spec generate(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def generate(sim_id, opts \\ []) do
    tick_data = Keyword.get(opts, :tick_data, [])
    agent_profiles = Keyword.get(opts, :agent_profiles, [])
    llm_fn = Keyword.get(opts, :llm_fn)

    # 1. Run statistical analysis
    statistical_summary = Analyzer.analyze(sim_id, tick_data, agent_profiles)

    # 2. Extract key events
    key_events = statistical_summary.key_events

    # 3. Build report prompt
    messages = [
      %{role: "system", content: Templates.system_prompt()},
      %{
        role: "user",
        content: Templates.report_prompt(statistical_summary, agent_profiles, key_events)
      }
    ]

    request = %{
      messages: messages,
      process_type: "simulation_report",
      max_tokens: 4000
    }

    # 4. Generate report via LLM
    result =
      if llm_fn do
        llm_fn.(request)
      else
        HydraX.LLM.Router.complete(request)
      end

    case result do
      {:ok, response} ->
        content = response[:content] || response["content"] || ""

        report = %{
          sim_id: sim_id,
          content: content,
          statistical_summary: statistical_summary,
          generated_at: DateTime.utc_now()
        }

        {:ok, report}

      {:error, reason} ->
        {:error, {:report_generation_failed, reason}}
    end
  end
end
