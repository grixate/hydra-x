defmodule HydraX.Product.Propagation do
  @moduledoc """
  Reactive GenServer that, when a node changes, traces the dependency graph
  and creates flags on affected downstream nodes. Batches notifications to
  avoid cascading storms from bulk operations.
  """

  use GenServer

  alias HydraX.Product.Graph
  alias HydraX.Product.PubSub, as: ProductPubSub

  @batch_interval_ms 500
  @max_per_tick 20

  # -------------------------------------------------------------------
  # Public API
  # -------------------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def notify_change(project_id, node_type, node_id, change_type) do
    GenServer.cast(__MODULE__, {:notify, project_id, to_string(node_type), node_id, change_type})
  end

  # -------------------------------------------------------------------
  # GenServer callbacks
  # -------------------------------------------------------------------

  @impl true
  def init(_opts) do
    {:ok, %{queue: [], timer: nil}}
  end

  @impl true
  def handle_cast({:notify, project_id, node_type, node_id, change_type}, state) do
    entry = %{
      project_id: project_id,
      node_type: node_type,
      node_id: node_id,
      change_type: change_type
    }

    state = %{state | queue: [entry | state.queue]}
    state = ensure_timer(state)

    {:noreply, state}
  end

  @impl true
  def handle_info(:process_batch, state) do
    {batch, remaining} =
      state.queue
      |> Enum.reverse()
      |> Enum.uniq_by(fn e -> {e.project_id, e.node_type, e.node_id} end)
      |> Enum.split(@max_per_tick)

    process_batch(batch)

    state = %{state | queue: remaining, timer: nil}
    state = if remaining != [], do: ensure_timer(state), else: state

    {:noreply, state}
  end

  # -------------------------------------------------------------------
  # Internal
  # -------------------------------------------------------------------

  defp ensure_timer(%{timer: nil} = state) do
    timer = Process.send_after(self(), :process_batch, @batch_interval_ms)
    %{state | timer: timer}
  end

  defp ensure_timer(state), do: state

  defp process_batch(entries) do
    Enum.each(entries, fn entry ->
      %{affected: affected} = Graph.impact_of_change(entry.project_id, entry.node_type, entry.node_id)

      Enum.each(affected, fn {affected_type, affected_id, _edge_kind} ->
        reason =
          "Upstream #{entry.node_type}##{entry.node_id} was #{entry.change_type}"

        case Graph.flag_node(entry.project_id, affected_type, affected_id, "needs_review", reason, "propagation") do
          {:ok, flag} ->
            ProductPubSub.broadcast_project_event(
              entry.project_id,
              "graph.flag.created",
              flag
            )

          {:error, _} ->
            :ok
        end
      end)

      ProductPubSub.broadcast_project_event(
        entry.project_id,
        "graph.propagation.completed",
        %{
          source_node_type: entry.node_type,
          source_node_id: entry.node_id,
          change_type: entry.change_type,
          affected_count: length(affected)
        }
      )
    end)
  end
end
