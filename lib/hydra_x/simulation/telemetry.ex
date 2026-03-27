defmodule HydraX.Simulation.Telemetry do
  @moduledoc """
  Telemetry event definitions for the simulation engine.

  All events are emitted under the `[:hydra_x, :simulation, ...]` prefix.

  ## Events

  - `[:hydra_x, :simulation, :tick]` — emitted every tick
    - measurements: `%{duration_us, llm_calls, tokens_used}`
    - metadata: `%{sim_id, tick, tiers: %{routine, emotional, complex, negotiation}}`

  - `[:hydra_x, :simulation, :llm_call]` — emitted per LLM call
    - measurements: `%{duration_us, tokens_in, tokens_out}`
    - metadata: `%{sim_id, agent_id, tier, provider, model}`

  - `[:hydra_x, :simulation, :lifecycle]` — emitted on lifecycle events
    - measurements: `%{}`
    - metadata: `%{sim_id, event: :started | :paused | :resumed | :completed | :failed}`

  - `[:hydra_x, :simulation, :budget_threshold]` — emitted on budget threshold
    - measurements: `%{used_cents, limit_cents, percentage}`
    - metadata: `%{sim_id, threshold: :soft | :medium | :hard, action: :downgrade | :halt}`
  """

  @doc "Emit a tick completion event."
  def tick_complete(sim_id, tick_number, measurements, tier_counts) do
    :telemetry.execute(
      [:hydra_x, :simulation, :tick],
      measurements,
      %{sim_id: sim_id, tick: tick_number, tiers: tier_counts}
    )
  end

  @doc "Emit an LLM call event."
  def llm_call(sim_id, agent_id, tier, measurements) do
    :telemetry.execute(
      [:hydra_x, :simulation, :llm_call],
      measurements,
      %{sim_id: sim_id, agent_id: agent_id, tier: tier}
    )
  end

  @doc "Emit a lifecycle event."
  def lifecycle(sim_id, event) do
    :telemetry.execute(
      [:hydra_x, :simulation, :lifecycle],
      %{},
      %{sim_id: sim_id, event: event}
    )
  end

  @doc "Emit a budget threshold event."
  def budget_threshold(sim_id, threshold, action, measurements) do
    :telemetry.execute(
      [:hydra_x, :simulation, :budget_threshold],
      measurements,
      %{sim_id: sim_id, threshold: threshold, action: action}
    )
  end
end
