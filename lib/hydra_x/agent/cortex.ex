defmodule HydraX.Agent.Cortex do
  @moduledoc false
  use GenServer

  alias HydraX.Config
  alias HydraX.Runtime

  def start_link(opts) do
    agent_id = Keyword.fetch!(opts, :agent_id)
    GenServer.start_link(__MODULE__, opts, name: via_name(agent_id))
  end

  def via_name(agent_id), do: HydraX.ProcessRegistry.via({:cortex, agent_id})

  def current_bulletin(agent_id) do
    GenServer.call(via_name(agent_id), :current_bulletin)
  catch
    :exit, _ -> nil
  end

  def refresh(agent_id), do: GenServer.cast(via_name(agent_id), :refresh)

  @impl true
  def init(opts) do
    agent = Runtime.get_agent!(Keyword.fetch!(opts, :agent_id))
    state = %{agent: agent, bulletin: get_in(agent.runtime_state, ["bulletin"])}
    schedule_refresh()
    {:ok, state}
  end

  @impl true
  def handle_call(:current_bulletin, _from, state), do: {:reply, state.bulletin, state}

  @impl true
  def handle_cast(:refresh, state), do: {:noreply, refresh_state(state)}

  @impl true
  def handle_info(:refresh, state) do
    schedule_refresh()
    {:noreply, refresh_state(state)}
  end

  defp refresh_state(%{agent: agent} = state) do
    refreshed = Runtime.refresh_agent_bulletin!(agent.id)
    %{state | agent: refreshed.agent, bulletin: refreshed.content}
  end

  defp schedule_refresh do
    Process.send_after(self(), :refresh, Config.cortex_interval_ms())
  end
end
