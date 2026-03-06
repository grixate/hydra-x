defmodule HydraX.Agent.Compactor do
  @moduledoc false
  use GenServer

  alias HydraX.Config
  alias HydraX.Runtime

  def start_link(opts) do
    conversation_id = Keyword.fetch!(opts, :conversation_id)
    GenServer.start_link(__MODULE__, opts, name: via_name(conversation_id))
  end

  def via_name(conversation_id), do: HydraX.ProcessRegistry.via({:compactor, conversation_id})

  def ensure_started(agent_id, conversation_id) do
    case Registry.lookup(HydraX.ProcessRegistry, {:compactor, conversation_id}) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        DynamicSupervisor.start_child(
          HydraX.Agent.compactor_supervisor(agent_id),
          {__MODULE__, agent_id: agent_id, conversation_id: conversation_id}
        )
    end
  end

  def review(agent_id, conversation_id) do
    {:ok, _pid} = ensure_started(agent_id, conversation_id)
    GenServer.cast(via_name(conversation_id), :review)
  end

  def current_summary(conversation_id) do
    case Runtime.get_checkpoint(conversation_id, "compactor") do
      nil -> nil
      checkpoint -> checkpoint.state["summary"]
    end
  end

  @impl true
  def init(opts), do: {:ok, %{agent_id: opts[:agent_id], conversation_id: opts[:conversation_id]}}

  @impl true
  def handle_cast(:review, state) do
    turns = Runtime.list_turns(state.conversation_id)
    thresholds = Config.compaction_thresholds()
    level = level_for(length(turns), thresholds)

    if level do
      summary =
        turns
        |> Enum.reject(&(&1.kind == "summary"))
        |> Enum.take(max(length(turns) - 3, 0))
        |> Enum.map_join("\n", fn turn -> "#{turn.role}: #{turn.content}" end)
        |> String.slice(0, 800)

      Runtime.upsert_checkpoint(state.conversation_id, "compactor", %{
        "level" => level,
        "summary" => summary,
        "updated_at" => DateTime.utc_now()
      })
    end

    {:noreply, state}
  end

  defp level_for(count, thresholds) when count >= thresholds.hard, do: "hard"
  defp level_for(count, thresholds) when count >= thresholds.medium, do: "medium"
  defp level_for(count, thresholds) when count >= thresholds.soft, do: "soft"
  defp level_for(_, _), do: nil
end
