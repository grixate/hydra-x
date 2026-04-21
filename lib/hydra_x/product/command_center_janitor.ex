defmodule HydraX.Product.CommandCenterJanitor do
  @moduledoc """
  Background maintenance for Command Center:

    * Stale detection — flag tasks stuck in `waiting_for_input` or `blocked`
      for more than 24h by emitting a stall StreamEntry.
    * Proposal expiry — auto-reject proposing tasks whose `proposal_payload`
      has an `expires_at` in the past.

  Runs independently of `HydraX.Scheduler` so one surface doesn't block the
  other.
  """

  use GenServer

  import Ecto.Query

  alias HydraX.Repo
  alias HydraX.Product.AgentTask
  alias HydraX.Product.AgentTasks
  alias HydraX.Product.StreamEntries

  @default_interval_ms 15 * 60 * 1000
  @stale_threshold_hours 24
  @nudge_threshold_hours 48

  ## API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Run all janitor passes synchronously. Primarily for tests."
  def run_once do
    GenServer.call(__MODULE__, :run_once, 30_000)
  end

  ## GenServer

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval_ms, @default_interval_ms)
    # Run once on boot to clear any pending backlog, then schedule.
    Process.send_after(self(), :tick, 5_000)
    {:ok, %{interval_ms: interval}}
  end

  @impl true
  def handle_info(:tick, state) do
    _ = safe_run()
    Process.send_after(self(), :tick, state.interval_ms)
    {:noreply, state}
  end

  @impl true
  def handle_call(:run_once, _from, state) do
    result = safe_run()
    {:reply, result, state}
  end

  ## Passes

  defp safe_run do
    try do
      stall_count = detect_stalls()
      expired_count = expire_proposals()
      stale_contradictions = stale_contradictions()
      archived_entries = StreamEntries.archive_stale()
      warmed_why = warm_proposal_why()
      nudged = nudge_memory_on_blockers()

      {:ok,
       %{
         stalls: stall_count,
         expired: expired_count,
         stale_contradictions: stale_contradictions,
         archived_entries: archived_entries,
         warmed_why: warmed_why,
         nudged_blockers: nudged
       }}
    rescue
      err -> {:error, err}
    end
  end

  # B3.5 — memory-agent proactively nudges the user in chat about tasks
  # that have been blocked/waiting for longer than the nudge threshold.
  # A nudge is recorded on the task's metadata (via state_reason fallback)
  # to avoid re-nudging on every tick.
  defp nudge_memory_on_blockers do
    cutoff = DateTime.add(DateTime.utc_now(), -@nudge_threshold_hours * 3600, :second)

    AgentTask
    |> where(
      [t],
      t.state in ["blocked", "waiting_for_input"] and t.last_state_change_at <= ^cutoff
    )
    |> limit(5)
    |> Repo.all()
    |> Enum.reduce(0, fn task, acc ->
      # Projects without a memory_agent assigned (e.g. Cycle 1 bare-bones
      # projects) can't host a nudge thread — skip quietly.
      project = Repo.get(HydraX.Product.Project, task.project_id)

      if project && project.memory_agent_id do
        case nudge_one(task) do
          :ok -> acc + 1
          _ -> acc
        end
      else
        acc
      end
    end)
  end

  defp nudge_one(%AgentTask{} = task) do
    if already_nudged_for_this_stall?(task) do
      :skip
    else
      case HydraX.Product.AgentBridge.ensure_project_conversation(task.project_id, "memory_agent", %{
             "channel" => "memory_nudges",
             "external_ref" => "memory_nudges",
             "title" => "Nudges",
             "metadata" => %{"kind" => "memory_nudges"}
           }) do
        {:ok, conversation} ->
          content =
            "You have a #{task.state |> String.replace("_", " ")} task from the #{task.agent_id}: " <>
              "\"#{task.title}\" — #{@nudge_threshold_hours}h+ without movement. Want me to help unblock?"

          case %HydraX.Product.ProductMessage{}
               |> HydraX.Product.ProductMessage.changeset(%{
                 "product_conversation_id" => conversation.id,
                 "role" => "system",
                 "content" => content,
                 "metadata" => %{
                   "kind" => "memory_nudge",
                   "task_id" => task.id,
                   "target_agent" => task.agent_id
                 }
               })
               |> Repo.insert() do
            {:ok, message} ->
              HydraX.Product.PubSub.broadcast_project_event(
                task.project_id,
                "chat.message_inserted",
                %{conversation_id: conversation.id, message: message}
              )

              :ok

            _ ->
              :skip
          end

        _ ->
          :skip
      end
    end
  rescue
    _ -> :skip
  end

  # A nudge is tracked by the presence of a `memory_nudge` system-role
  # message in the memory_agent conversation tagged with this task's id
  # AND inserted after the task's last state change. Re-entry into a
  # stalled state clears the dedupe, so repeated stalls do nudge again.
  defp already_nudged_for_this_stall?(%AgentTask{} = task) do
    last_change = task.last_state_change_at || task.inserted_at

    task_id_int = task.id

    query =
      from m in HydraX.Product.ProductMessage,
        join: c in HydraX.Product.ProductConversation,
        on: c.id == m.product_conversation_id,
        where:
          c.project_id == ^task.project_id and
            m.role == "system" and
            m.inserted_at >= ^last_change and
            fragment("(?->>'kind') = ?", m.metadata, "memory_nudge") and
            fragment("(?->>'task_id')::int = ?", m.metadata, ^task_id_int),
        limit: 1

    Repo.exists?(query)
  end

  # B2.7 — pre-warm the Why cache for every open proposal that points at
  # a graph node. The first render on a fresh node is otherwise blocked
  # on an LLM prose call; once warmed the panel opens from cache.
  defp warm_proposal_why do
    AgentTask
    |> where([t], t.state == "proposing" and not is_nil(t.context_type) and not is_nil(t.context_id))
    |> limit(20)
    |> Repo.all()
    |> Enum.reduce(0, fn task, acc ->
      case HydraX.Product.WhyProse.build(task.project_id, task.context_type, task.context_id) do
        {:ok, _} -> acc + 1
        _ -> acc
      end
    end)
  end

  @contradiction_stale_days 30

  defp stale_contradictions do
    cutoff = DateTime.add(DateTime.utc_now(), -@contradiction_stale_days * 86_400, :second)

    HydraX.Coherence.Contradiction
    |> where([c], c.status in ["open", "under_review"] and c.last_confirmed_at <= ^cutoff)
    |> Repo.all()
    |> Enum.reduce(0, fn contradiction, acc ->
      case HydraX.Coherence.mark_stale(contradiction) do
        {:ok, _} -> acc + 1
        _ -> acc
      end
    end)
  end

  defp detect_stalls do
    cutoff = DateTime.add(DateTime.utc_now(), -@stale_threshold_hours * 3600, :second)

    stalled =
      AgentTask
      |> where(
        [t],
        t.state in ["waiting_for_input", "blocked"] and
          t.last_state_change_at <= ^cutoff
      )
      |> Repo.all()

    Enum.reduce(stalled, 0, fn task, acc ->
      stall_type =
        case task.state do
          "blocked" -> :blocked
          "waiting_for_input" -> :waiting_for_input
        end

      case StreamEntries.emit_for_stall(task, stall_type) do
        {:ok, _} -> acc + 1
        _ -> acc
      end
    end)
  end

  defp expire_proposals do
    now = DateTime.utc_now()

    AgentTask
    |> where([t], t.state == "proposing" and not is_nil(t.proposal_payload))
    |> Repo.all()
    |> Enum.reduce(0, fn task, acc ->
      case expires_at(task) do
        %DateTime{} = ts ->
          if DateTime.compare(ts, now) == :lt do
            case AgentTasks.transition(task, "rejected",
                   reason: "expired without review"
                 ) do
              {:ok, _} -> acc + 1
              _ -> acc
            end
          else
            acc
          end

        _ ->
          acc
      end
    end)
  end

  defp expires_at(%AgentTask{proposal_payload: payload}) when is_map(payload) do
    case payload["expires_at"] do
      nil ->
        nil

      value when is_binary(value) ->
        case DateTime.from_iso8601(value) do
          {:ok, dt, _} -> dt
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp expires_at(_), do: nil
end
