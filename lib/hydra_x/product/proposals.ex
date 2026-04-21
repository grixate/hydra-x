defmodule HydraX.Product.Proposals do
  @moduledoc """
  Helpers for working with the `proposing` state of `HydraX.Product.AgentTask`.

  A proposal is just a task in state `proposing` with a populated
  `proposal_payload`. This module adds the per-item review workflow (accept /
  reject / defer / edit) on top.

  Per-item review decisions are persisted on `proposal_payload` under the key
  `"item_decisions"` — see Command Center spec §4.
  """

  import Ecto.Query

  require Logger

  alias HydraX.Repo
  alias HydraX.Product.AgentTask
  alias HydraX.Product.AgentTasks
  alias HydraX.Product.TaskEvent

  @decisions ~w(accepted rejected deferred edited)

  @doc "List proposals (tasks in `proposing` state) for a project."
  def list_proposals(project_id, opts \\ []) do
    project_id = to_int(project_id)

    AgentTask
    |> where([t], t.project_id == ^project_id and t.state == "proposing")
    |> apply_agent(opts[:agent_id])
    |> order_by([t], desc: t.last_state_change_at, desc: t.id)
    |> limit(^(opts[:limit] || 50))
    |> Repo.all()
  end

  @doc """
  Record per-item decisions on a proposing task. `decisions` is a list of maps
  shaped like `%{"item_index" => n, "decision" => d, "edits" => map}`.
  Merges with any prior decisions (later decisions win).
  """
  def record_item_decisions(%AgentTask{state: "proposing"} = task, decisions)
      when is_list(decisions) do
    # Normalise keys so callers can pass string- or atom-keyed maps
    # interchangeably; downstream comparisons all use strings.
    decisions = Enum.map(decisions, &stringify_keys/1)

    with :ok <- validate_decisions(decisions) do
      payload = task.proposal_payload || %{}
      prior = payload["item_decisions"] || []
      merged = merge_decisions(prior, decisions)

      task
      |> AgentTask.changeset(%{"proposal_payload" => Map.put(payload, "item_decisions", merged)})
      |> Repo.update()
    end
  end

  def record_item_decisions(%AgentTask{}, _), do: {:error, :not_proposing}

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp stringify_keys(other), do: other

  @doc """
  Apply the current per-item decisions: transition task to `completed` (any
  accepted) or `rejected` (all rejected). Deferred items spawn a new child
  task referencing `parent_task_id`.
  """
  def apply_decisions(task, opts \\ [])

  def apply_decisions(%AgentTask{state: "proposing"} = task, opts) do
    payload = task.proposal_payload || %{}
    items = payload["items"] || []
    decisions = payload["item_decisions"] || []

    counts = count_decisions(decisions)

    cond do
      counts.accepted > 0 ->
        with {:ok, updated} <-
               AgentTasks.transition(task, "completed",
                 reason: "applied",
                 actor: opts[:actor]
               ) do
          log_review_event(updated, counts)
          maybe_spawn_deferred(updated, items, decisions)
          {:ok, updated}
        end

      counts.rejected > 0 and counts.accepted == 0 and counts.deferred == 0 ->
        with {:ok, updated} <-
               AgentTasks.transition(task, "rejected",
                 reason: "all items rejected",
                 actor: opts[:actor]
               ) do
          log_review_event(updated, counts)
          {:ok, updated}
        end

      true ->
        {:error, :no_decisions}
    end
  end

  def apply_decisions(%AgentTask{}, _), do: {:error, :not_proposing}

  @doc "Dismiss a proposal outright (rejected with reason 'dismissed')."
  def dismiss(task, opts \\ [])

  def dismiss(%AgentTask{state: "proposing"} = task, opts) do
    AgentTasks.transition(task, "rejected",
      reason: opts[:reason] || "dismissed without review",
      actor: opts[:actor]
    )
  end

  def dismiss(%AgentTask{}, _), do: {:error, :not_proposing}

  ## Private

  defp validate_decisions(decisions) do
    Enum.reduce_while(decisions, :ok, fn decision, :ok ->
      cond do
        not is_map(decision) ->
          {:halt, {:error, {:invalid_decision, decision}}}

        not is_integer(decision["item_index"] || decision[:item_index]) ->
          {:halt, {:error, :missing_item_index}}

        (decision["decision"] || decision[:decision]) not in @decisions ->
          {:halt, {:error, :invalid_decision_value}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  defp merge_decisions(prior, new) do
    prior_by_index =
      Map.new(prior, fn d ->
        idx = d["item_index"] || d[:item_index]
        {idx, d}
      end)

    updated =
      Enum.reduce(new, prior_by_index, fn d, acc ->
        idx = d["item_index"] || d[:item_index]

        normalized = %{
          "item_index" => idx,
          "decision" => d["decision"] || d[:decision],
          "edits" => d["edits"] || d[:edits]
        }

        Map.put(acc, idx, normalized)
      end)

    updated
    |> Map.values()
    |> Enum.sort_by(& &1["item_index"])
  end

  defp count_decisions(decisions) do
    Enum.reduce(decisions, %{accepted: 0, rejected: 0, deferred: 0, edited: 0}, fn d, acc ->
      key = decision_atom(d["decision"] || d[:decision])
      if key, do: Map.update!(acc, key, &(&1 + 1)), else: acc
    end)
  end

  defp decision_atom("accepted"), do: :accepted
  defp decision_atom("rejected"), do: :rejected
  defp decision_atom("deferred"), do: :deferred
  defp decision_atom("edited"), do: :edited
  defp decision_atom(_), do: nil

  defp log_review_event(%AgentTask{} = task, counts) do
    %TaskEvent{}
    |> TaskEvent.changeset(%{
      task_id: task.id,
      project_id: task.project_id,
      event_type: "proposal_partially_reviewed",
      payload: %{
        "accepted_count" => counts.accepted,
        "rejected_count" => counts.rejected,
        "deferred_count" => counts.deferred
      },
      actor_type: "user",
      actor_id: nil
    })
    |> Repo.insert()
  end

  defp maybe_spawn_deferred(%AgentTask{} = parent, items, decisions) do
    deferred_indices =
      decisions
      |> Enum.filter(fn d -> (d["decision"] || d[:decision]) == "deferred" end)
      |> Enum.map(fn d -> d["item_index"] || d[:item_index] end)

    if deferred_indices == [] do
      :ok
    else
      deferred_items =
        items
        |> Enum.with_index()
        |> Enum.filter(fn {_item, idx} -> idx in deferred_indices end)
        |> Enum.map(fn {item, _} -> item end)

      original_payload = parent.proposal_payload || %{}

      new_payload =
        original_payload
        |> Map.put("items", deferred_items)
        |> Map.delete("item_decisions")

      case AgentTasks.create_task(%{
             project_id: parent.project_id,
             agent_id: parent.agent_id,
             title: "Deferred items from: #{parent.title}",
             description: parent.description,
             state: "proposing",
             priority: parent.priority,
             parent_task_id: parent.id,
             assigned_by: "system",
             proposal_payload: new_payload
           }) do
        {:ok, child} ->
          {:ok, child}

        {:error, changeset} ->
          Logger.warning(
            "[Proposals] failed to spawn deferred task for parent=#{parent.id}: " <>
              inspect(changeset.errors)
          )

          # Surface the failure on the parent's audit trail so it's not invisible.
          %TaskEvent{}
          |> TaskEvent.changeset(%{
            task_id: parent.id,
            project_id: parent.project_id,
            event_type: "failed",
            payload: %{
              "context" => "deferred_spawn",
              "errors" => inspect(changeset.errors),
              "retryable" => true
            },
            actor_type: "system",
            actor_id: nil
          })
          |> Repo.insert()

          {:error, changeset}
      end
    end
  end

  defp apply_agent(query, nil), do: query
  defp apply_agent(query, agent_id), do: where(query, [t], t.agent_id == ^agent_id)

  defp to_int(v) when is_integer(v), do: v
  defp to_int(v) when is_binary(v), do: String.to_integer(v)
end
