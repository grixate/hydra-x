defmodule HydraX.Product.StreamEntries do
  @moduledoc """
  Context for `HydraX.Product.StreamEntry`. Generates entries from terminal
  `AgentTask` transitions (Command Center spec §8) and reads them back for the
  bell dropdown / Stream union.
  """

  import Ecto.Query

  alias HydraX.Repo
  alias HydraX.Product.AgentTask
  alias HydraX.Product.StreamEntry
  alias HydraX.Product.PubSub, as: ProductPubSub

  ## Queries

  def list_for_project(project_id, opts \\ []) do
    project_id = to_int(project_id)

    StreamEntry
    |> where([e], e.project_id == ^project_id)
    |> apply_tab(opts[:tab])
    |> apply_unread(opts[:unread])
    |> order_by([e], desc: e.inserted_at)
    |> limit(^(opts[:limit] || 100))
    |> Repo.all()
  end

  def unread_counts(project_id) do
    project_id = to_int(project_id)

    StreamEntry
    |> where([e], e.project_id == ^project_id and is_nil(e.read_at))
    |> group_by([e], e.tab)
    |> select([e], {e.tab, count(e.id)})
    |> Repo.all()
    |> Map.new()
  end

  def mark_read(project_id, ids) when is_list(ids) do
    project_id = to_int(project_id)
    ids = Enum.map(ids, &to_int/1)
    now = DateTime.utc_now()

    StreamEntry
    |> where([e], e.project_id == ^project_id and e.id in ^ids and is_nil(e.read_at))
    |> Repo.update_all(set: [read_at: now])
  end

  @doc """
  Mark a StreamEntry as actioned — removes it from Needs You / Blockers
  derived lists (see spec §5 "Ignore for now" / "Resolve manually").
  Idempotent; a second call is a no-op.
  """
  def mark_actioned(project_id, id) do
    project_id = to_int(project_id)
    id = to_int(id)
    now = DateTime.utc_now()

    {count, _} =
      StreamEntry
      |> where([e], e.project_id == ^project_id and e.id == ^id and is_nil(e.actioned_at))
      |> Repo.update_all(set: [actioned_at: now])

    if count > 0 do
      ProductPubSub.broadcast_project_event(project_id, "stream_entry.actioned", %{
        stream_entry_id: id
      })
    end

    {:ok, count}
  end

  @doc """
  B3.7 — delete stream entries older than `older_than_days` (default 365).
  Called periodically so the Activity tab stays bounded. Returns the
  number of rows removed.
  """
  def archive_stale(older_than_days \\ 365) do
    cutoff = DateTime.add(DateTime.utc_now(), -older_than_days * 24 * 3600, :second)

    {count, _} =
      StreamEntry
      |> where([e], e.inserted_at < ^cutoff)
      |> Repo.delete_all()

    count
  end

  ## Emission — called from AgentTasks on terminal transitions

  @doc """
  Emit a StreamEntry for a task transition. `prev_state` is the state before
  the transition; `task` is the current (post-transition) record.
  """
  def emit_for_transition(%AgentTask{} = task, prev_state) do
    case entry_attrs_for(task, prev_state) do
      nil ->
        :skip

      attrs ->
        case Repo.insert(StreamEntry.changeset(%StreamEntry{}, attrs)) do
          {:ok, entry} ->
            ProductPubSub.broadcast_project_event(task.project_id, "stream_entry.created", %{
              stream_entry: entry
            })

            {:ok, entry}

          {:error, _} = err ->
            err
        end
    end
  end

  def emit_for_stall(%AgentTask{} = task, stall_type)
      when stall_type in [:blocked, :waiting_for_input] do
    tab =
      case stall_type do
        :blocked -> "blockers"
        :waiting_for_input -> "needs_you"
      end

    title = stall_title(task, stall_type)

    attrs = %{
      project_id: task.project_id,
      tab: tab,
      source_task_id: task.id,
      source_agent_id: task.agent_id,
      title: title,
      summary: task.state_reason || task.description,
      context_type: normalize_context_type(task.context_type),
      context_id: task.context_id
    }

    # Avoid duplicate stall entries for the current stall period.
    # An entry from a PRIOR stall (before the task's last state change)
    # should not suppress a new one — that would miss re-entries into
    # blocked/waiting after the user resolved the original.
    last_change = task.last_state_change_at || task.inserted_at

    existing =
      StreamEntry
      |> where(
        [e],
        e.source_task_id == ^task.id and e.tab == ^tab and is_nil(e.actioned_at) and
          e.inserted_at >= ^last_change
      )
      |> limit(1)
      |> Repo.one()

    if existing do
      :skip
    else
      case Repo.insert(StreamEntry.changeset(%StreamEntry{}, attrs)) do
        {:ok, entry} ->
          ProductPubSub.broadcast_project_event(task.project_id, "stream_entry.created", %{
            stream_entry: entry
          })

          {:ok, entry}

        err ->
          err
      end
    end
  end

  ## Private

  defp entry_attrs_for(%AgentTask{state: "completed"} = task, prev) do
    summary =
      if prev == "proposing",
        do: "#{pretty_agent(task.agent_id)} proposal was accepted",
        else: "#{pretty_agent(task.agent_id)} completed: #{task.title}"

    %{
      project_id: task.project_id,
      tab: "activity",
      source_task_id: task.id,
      source_agent_id: task.agent_id,
      title: task.title,
      summary: summary,
      context_type: normalize_context_type(task.context_type),
      context_id: task.context_id
    }
  end

  defp entry_attrs_for(%AgentTask{state: "rejected"} = task, _prev) do
    %{
      project_id: task.project_id,
      tab: "activity",
      source_task_id: task.id,
      source_agent_id: task.agent_id,
      title: task.title,
      summary: "#{pretty_agent(task.agent_id)} proposal was rejected",
      context_type: normalize_context_type(task.context_type),
      context_id: task.context_id
    }
  end

  defp entry_attrs_for(%AgentTask{state: "failed"} = task, _prev) do
    %{
      project_id: task.project_id,
      tab: "blockers",
      source_task_id: task.id,
      source_agent_id: task.agent_id,
      title: task.title,
      summary: task.state_reason || "Task failed",
      context_type: normalize_context_type(task.context_type),
      context_id: task.context_id
    }
  end

  # cancelled → silent (per spec §8 table)
  defp entry_attrs_for(_task, _prev), do: nil

  defp stall_title(%AgentTask{} = task, :blocked),
    do: "#{pretty_agent(task.agent_id)} blocked on: #{task.title}"

  defp stall_title(%AgentTask{} = task, :waiting_for_input),
    do: "#{pretty_agent(task.agent_id)} needs your input on: #{task.title}"

  defp pretty_agent(id) do
    id |> String.replace("_", " ") |> String.capitalize()
  end

  # AgentTask context types don't 1:1 match StreamEntry types — translate.
  defp normalize_context_type(nil), do: nil
  defp normalize_context_type("board_session"), do: "session"
  defp normalize_context_type("library_source"), do: "source"
  defp normalize_context_type(other), do: other

  defp apply_tab(query, nil), do: query
  defp apply_tab(query, tab) when is_binary(tab), do: where(query, [e], e.tab == ^tab)

  defp apply_unread(query, true), do: where(query, [e], is_nil(e.read_at))
  defp apply_unread(query, _), do: query

  defp to_int(v) when is_integer(v), do: v
  defp to_int(v) when is_binary(v), do: String.to_integer(v)
end
