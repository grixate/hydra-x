defmodule HydraX.Product.AgentTasks do
  @moduledoc """
  Context for `HydraX.Product.AgentTask`. Owns the state machine, query
  helpers for Command Center zones, and broadcast of `agent_task.*` events on
  `project:<id>`.
  """

  import Ecto.Query

  alias HydraX.Repo
  alias HydraX.Product.AgentTask
  alias HydraX.Product.PubSub, as: ProductPubSub
  alias HydraX.Product.StreamEntries
  alias HydraX.Product.TaskEvent

  # Flows alias is resolved lazily to avoid a module-compile cycle
  # between AgentTasks → Flows → (uses AgentTask).

  @transitions %{
    "pending" => ~w(running cancelled),
    "running" => ~w(waiting_for_input blocked paused proposing completed failed cancelled),
    "waiting_for_input" => ~w(running cancelled),
    "blocked" => ~w(running cancelled),
    "paused" => ~w(running cancelled),
    "proposing" => ~w(completed rejected running cancelled)
  }

  @spec allowed_transitions(String.t()) :: [String.t()]
  def allowed_transitions(state), do: Map.get(@transitions, state, [])

  @spec can_transition?(String.t(), String.t()) :: boolean()
  def can_transition?(from, to), do: to in allowed_transitions(from)

  @spec terminal?(String.t()) :: boolean()
  def terminal?(state), do: state in AgentTask.terminal_states()

  ## Queries

  @doc """
  List agent tasks for a project, with optional filters.

  Supported filters:
    * `:state` — single state or list of states
    * `:agent_id` — single agent_id
    * `:search` — substring match on title/description
    * `:exclude_terminal` — drop completed/rejected/cancelled/failed
    * `:limit` — defaults to 200
  """
  def list_tasks(project_id, opts \\ []) do
    project_id = to_int(project_id)

    AgentTask
    |> where([t], t.project_id == ^project_id)
    |> apply_state_filter(opts[:state])
    |> apply_agent_filter(opts[:agent_id])
    |> apply_search(opts[:search])
    |> apply_exclude_terminal(opts[:exclude_terminal])
    |> order_by([t], desc: t.last_state_change_at, desc: t.id)
    |> limit(^(opts[:limit] || 200))
    |> Repo.all()
  end

  def get_task!(project_id, id) do
    project_id = to_int(project_id)

    AgentTask
    |> where([t], t.project_id == ^project_id and t.id == ^to_int(id))
    |> Repo.one!()
  end

  @doc """
  Derived Zone 1 strip: one entry per agent_id with the agent's current
  aggregate state + a short activity summary.
  """
  def agent_strip(project_id, agent_ids) when is_list(agent_ids) do
    project_id = to_int(project_id)

    tasks =
      AgentTask
      |> where([t], t.project_id == ^project_id and t.agent_id in ^agent_ids)
      |> where([t], t.state not in ^AgentTask.terminal_states())
      |> Repo.all()

    by_agent = Enum.group_by(tasks, & &1.agent_id)

    Enum.map(agent_ids, fn agent_id ->
      agent_tasks = Map.get(by_agent, agent_id, [])

      %{
        agent_id: agent_id,
        state: derive_agent_state(agent_tasks),
        active_count: length(agent_tasks),
        summary: summary_for(agent_tasks)
      }
    end)
  end

  defp derive_agent_state([]), do: "idle"

  defp derive_agent_state(tasks) do
    cond do
      Enum.any?(tasks, &(&1.state == "blocked")) -> "blocked"
      Enum.any?(tasks, &(&1.state == "waiting_for_input")) -> "waiting_for_input"
      Enum.any?(tasks, &(&1.state == "proposing")) -> "proposing"
      Enum.any?(tasks, &(&1.state == "running")) -> "working"
      Enum.any?(tasks, &(&1.state == "paused")) -> "paused"
      true -> "idle"
    end
  end

  defp summary_for([]), do: nil
  defp summary_for([task | _]), do: task.title

  ## Mutations

  def create_task(attrs) do
    now = DateTime.utc_now()

    attrs =
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.put_new("last_state_change_at", now)

    attrs =
      if attrs["state"] == "running" do
        Map.put_new(attrs, "started_at", now)
      else
        attrs
      end

    %AgentTask{}
    |> AgentTask.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, task} ->
        log_event(task, "created", %{}, actor_for(task))
        broadcast(task, "agent_task.created")
        {:ok, task}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Transition a task to `new_state`. Writes a `state_changed` TaskEvent and
  broadcasts `agent_task.state_changed`. Sets timestamps on terminal/started.
  """
  def transition(%AgentTask{} = task, new_state, opts \\ []) do
    cond do
      task.state == new_state ->
        {:ok, task}

      not can_transition?(task.state, new_state) ->
        {:error, :invalid_transition}

      true ->
        now = DateTime.utc_now()
        reason = opts[:reason]

        attrs =
          %{
            "state" => new_state,
            "state_reason" => reason,
            "last_state_change_at" => now
          }
          |> maybe_put_started(new_state, task, now)
          |> maybe_put_completed(new_state, now)
          |> maybe_clear_deferred(new_state)

        try do
          task
          |> AgentTask.transition_changeset(attrs)
          |> Repo.update()
          |> case do
            {:ok, updated} ->
              log_event(
                updated,
                "state_changed",
                %{"from" => task.state, "to" => new_state, "reason" => reason},
                opts[:actor] || actor_for(updated)
              )

              broadcast(updated, "agent_task.state_changed", %{
                from: task.state,
                to: new_state
              })

              maybe_emit_stream_entry(updated, task.state)
              maybe_update_flow(updated)
              maybe_emit_mention_follow_up(updated, task.state)

              # Terminal transitions clear the progress-throttle bucket so
              # a future re-run (via parent_task_id or retry) starts clean.
              if terminal?(new_state),
                do: HydraX.Product.ProgressThrottle.reset(updated.id)

              {:ok, updated}

            err ->
              err
          end
        rescue
          Ecto.StaleEntryError -> {:error, :stale}
        end
    end
  end

  def pause(%AgentTask{} = task, opts \\ []),
    do: transition(task, "paused", opts)

  def cancel(%AgentTask{} = task, opts \\ []),
    do: transition(task, "cancelled", opts)

  def resume(%AgentTask{} = task, opts \\ []),
    do: transition(task, "running", opts)

  @doc """
  Record a redirect (user-provided refinement). Does not change state —
  appends a `redirected` TaskEvent and broadcasts.
  """
  def redirect(%AgentTask{} = task, refinement, opts \\ []) do
    actor = opts[:actor] || actor_for(task)

    case log_event(task, "redirected", %{"refinement" => refinement}, actor) do
      {:ok, _event} ->
        broadcast(task, "agent_task.redirected", %{refinement: refinement})
        {:ok, task}

      err ->
        err
    end
  end

  @doc """
  Snooze a task — set `deferred_until = now + hours`. The task stays in
  its current state; StreamTabs filters it out of the Needs You /
  Blockers visible lists until the defer window expires.

  Pass `:clear` as the second argument to remove a pending defer.
  """
  def defer(%AgentTask{} = task, hours) when is_integer(hours) and hours > 0 do
    until = DateTime.add(DateTime.utc_now(), hours * 3600, :second)

    task
    |> AgentTask.changeset(%{"deferred_until" => until})
    |> Repo.update()
    |> case do
      {:ok, updated} ->
        broadcast(updated, "agent_task.deferred", %{deferred_until: until})
        {:ok, updated}

      err ->
        err
    end
  end

  def defer(%AgentTask{} = task, :clear) do
    task
    |> AgentTask.changeset(%{"deferred_until" => nil})
    |> Repo.update()
  end

  def update_progress(%AgentTask{} = task, current, total, label \\ nil) do
    attrs = %{
      "progress_current" => current,
      "progress_total" => total,
      "progress_label" => label
    }

    task
    |> AgentTask.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated} ->
        # Stream A4.1 — throttle broadcast to ~5/s per task; DB row
        # always persists so a later fetch returns the freshest value.
        if HydraX.Product.ProgressThrottle.check(updated.id) == :allow do
          broadcast(updated, "agent_task.progress", %{
            current: current,
            total: total,
            label: label
          })
        end

        {:ok, updated}

      err ->
        err
    end
  end

  ## Events

  defp log_event(%AgentTask{} = task, event_type, payload, actor) do
    %TaskEvent{}
    |> TaskEvent.changeset(%{
      task_id: task.id,
      project_id: task.project_id,
      event_type: event_type,
      payload: payload,
      actor_type: actor.type,
      actor_id: actor.id
    })
    |> Repo.insert()
  end

  defp actor_for(%AgentTask{assigned_by: "user", assigned_by_user_id: user_id})
       when not is_nil(user_id),
       do: %{type: "user", id: to_string(user_id)}

  defp actor_for(%AgentTask{assigned_by: "agent", assigned_by_agent_id: agent_id})
       when not is_nil(agent_id),
       do: %{type: "agent", id: agent_id}

  defp actor_for(%AgentTask{}), do: %{type: "system", id: nil}

  defp broadcast(%AgentTask{} = task, event, extra \\ %{}) do
    ProductPubSub.broadcast_project_event(task.project_id, event, Map.put(extra, :task, task))
  end

  defp maybe_emit_stream_entry(%AgentTask{state: state} = task, prev_state) do
    if terminal?(state) do
      StreamEntries.emit_for_transition(task, prev_state)
    else
      :ok
    end
  end

  defp maybe_update_flow(%AgentTask{flow_id: nil}), do: :ok

  defp maybe_update_flow(%AgentTask{} = task) do
    # Isolate the flow-recomputation side effect: a failure here should
    # not block the main transition-state broadcast. The janitor's next
    # pass + event-driven updates will re-converge flow status.
    try do
      HydraX.Product.Flows.on_task_state_change(task)
    rescue
      err ->
        require Logger
        Logger.warning("[AgentTasks] flow update failed for task=#{task.id}: #{inspect(err)}")
    end

    :ok
  end

  # When a task spawned by a chat @-mention reaches `completed`, emit a
  # follow-up system message into the source conversation so the user can
  # jump to the target agent's thread and see the reply.
  defp maybe_emit_mention_follow_up(%AgentTask{state: "completed"} = task, _prev) do
    try do
      HydraX.Product.Mentions.emit_task_completion_followup(task)
    rescue
      _ -> :ok
    end
  end

  defp maybe_emit_mention_follow_up(_, _), do: :ok

  ## Helpers

  defp apply_state_filter(query, nil), do: query

  defp apply_state_filter(query, state) when is_binary(state),
    do: where(query, [t], t.state == ^state)

  defp apply_state_filter(query, states) when is_list(states),
    do: where(query, [t], t.state in ^states)

  defp apply_agent_filter(query, nil), do: query
  defp apply_agent_filter(query, ""), do: query

  defp apply_agent_filter(query, agent_id),
    do: where(query, [t], t.agent_id == ^agent_id)

  defp apply_search(query, nil), do: query
  defp apply_search(query, ""), do: query

  defp apply_search(query, term) do
    like = "%#{term}%"
    where(query, [t], ilike(t.title, ^like) or ilike(t.description, ^like))
  end

  defp apply_exclude_terminal(query, true),
    do: where(query, [t], t.state not in ^AgentTask.terminal_states())

  defp apply_exclude_terminal(query, _), do: query

  defp maybe_put_started(attrs, "running", %AgentTask{started_at: nil}, now),
    do: Map.put(attrs, "started_at", now)

  defp maybe_put_started(attrs, _, _, _), do: attrs

  defp maybe_put_completed(attrs, new_state, now) do
    if new_state in AgentTask.terminal_states() do
      Map.put(attrs, "completed_at", now)
    else
      attrs
    end
  end

  # Terminal transitions clear any active defer — otherwise a "completed"
  # task with a future `deferred_until` stays hidden from every tab.
  defp maybe_clear_deferred(attrs, new_state) do
    if new_state in AgentTask.terminal_states(),
      do: Map.put(attrs, "deferred_until", nil),
      else: attrs
  end

  defp to_int(v) when is_integer(v), do: v
  defp to_int(v) when is_binary(v), do: String.to_integer(v)
end
