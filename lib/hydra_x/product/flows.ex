defmodule HydraX.Product.Flows do
  @moduledoc """
  Flow derivation + lifecycle. Spec §6 of the task-data-model.

  A Flow groups related AgentTasks linked via Mentions into a coordination
  chain. Flow status is event-driven: recomputed whenever a constituent task
  changes state.
  """

  import Ecto.Query

  alias HydraX.Repo
  alias HydraX.Product.AgentTask
  alias HydraX.Product.Flow
  alias HydraX.Product.Mention
  alias HydraX.Product.PubSub, as: ProductPubSub

  @stale_threshold_hours 24

  ## Queries

  def list_active(project_id) do
    project_id = to_int(project_id)

    Flow
    |> where([f], f.project_id == ^project_id and f.status in ["ongoing", "stalled"])
    |> order_by([f], desc: f.updated_at)
    |> Repo.all()
  end

  def get!(id), do: Repo.get!(Flow, id)

  ## Derivation

  @doc """
  Called when a mention links two agent tasks across agents. Creates a new
  flow if neither task is in one yet, or extends an existing flow.
  """
  def register_mention(%Mention{}, nil, _target_task), do: :skip
  def register_mention(%Mention{}, _source, nil), do: :skip

  def register_mention(%Mention{} = _mention, %AgentTask{} = source, %AgentTask{} = target) do
    if source.agent_id == target.agent_id do
      :skip
    else
      flow = resolve_or_create_flow(source, target)
      attach_to_flow(flow, [source, target])
      update_membership(flow)
    end
  end

  defp resolve_or_create_flow(%AgentTask{} = source, %AgentTask{} = target) do
    case lookup_flow_for([source.id, target.id]) do
      nil ->
        name = derived_name(source)

        {:ok, flow} =
          %Flow{}
          |> Flow.changeset(%{
            project_id: source.project_id,
            name: name,
            originating_task_id: source.id,
            status: "ongoing",
            task_ids: [],
            participating_agent_ids: []
          })
          |> Repo.insert()

        ProductPubSub.broadcast_project_event(flow.project_id, "flow.created", %{flow: flow})
        flow

      flow ->
        flow
    end
  end

  defp lookup_flow_for(task_ids) do
    Flow
    |> where([f], fragment("? && ?", f.task_ids, ^task_ids))
    |> limit(1)
    |> Repo.one()
  end

  defp attach_to_flow(%Flow{id: flow_id}, tasks) do
    ids = Enum.map(tasks, & &1.id)

    from(t in AgentTask, where: t.id in ^ids)
    |> Repo.update_all(set: [flow_id: flow_id])
  end

  ## Membership / status recomputation

  @doc "Recompute task_ids + participating_agent_ids + status for a flow."
  def update_membership(%Flow{} = flow) do
    tasks =
      AgentTask
      |> where([t], t.flow_id == ^flow.id)
      |> Repo.all()

    task_ids = Enum.map(tasks, & &1.id) |> Enum.sort()
    agent_ids = tasks |> Enum.map(& &1.agent_id) |> Enum.uniq() |> Enum.sort()
    status = derive_status(tasks)

    changes = %{
      task_ids: task_ids,
      participating_agent_ids: agent_ids,
      status: status
    }

    changes =
      if status == "complete" and is_nil(flow.completed_at) do
        Map.put(changes, :completed_at, DateTime.utc_now())
      else
        changes
      end

    case flow |> Flow.changeset(changes) |> Repo.update() do
      {:ok, updated} ->
        if updated.status != flow.status do
          ProductPubSub.broadcast_project_event(updated.project_id, "flow.updated", %{
            flow: updated
          })
        else
          ProductPubSub.broadcast_project_event(updated.project_id, "flow.membership_updated", %{
            flow: updated
          })
        end

        {:ok, updated}

      err ->
        err
    end
  end

  @doc "Recompute flow status after one of its tasks transitioned. Public hook."
  def on_task_state_change(%AgentTask{flow_id: nil}), do: :skip

  def on_task_state_change(%AgentTask{flow_id: flow_id}) do
    case Repo.get(Flow, flow_id) do
      nil -> :skip
      flow -> update_membership(flow)
    end
  end

  ## Private helpers

  defp derive_status([]), do: "ongoing"

  defp derive_status(tasks) do
    all_terminal = Enum.all?(tasks, &(&1.state in ~w(completed rejected cancelled failed)))
    any_completed = Enum.any?(tasks, &(&1.state == "completed"))
    any_cancelled = Enum.any?(tasks, &(&1.state == "cancelled"))

    cond do
      all_terminal and Enum.all?(tasks, &(&1.state == "completed")) ->
        "complete"

      all_terminal and any_cancelled and not any_completed ->
        "cancelled"

      all_terminal ->
        # Fallback: mix of completed/rejected/failed — treat as complete.
        "complete"

      stalled?(tasks) ->
        "stalled"

      true ->
        "ongoing"
    end
  end

  defp stalled?(tasks) do
    cutoff = DateTime.add(DateTime.utc_now(), -@stale_threshold_hours * 3600, :second)

    Enum.all?(tasks, fn t ->
      t.state not in ~w(completed rejected cancelled failed) and
        DateTime.compare(t.last_state_change_at || t.inserted_at, cutoff) == :lt
    end)
  end

  defp derived_name(%AgentTask{title: title}) do
    title |> to_string() |> String.slice(0, 80)
  end

  defp to_int(v) when is_integer(v), do: v
  defp to_int(v) when is_binary(v), do: String.to_integer(v)
end
