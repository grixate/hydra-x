defmodule HydraX.Runtime.WorkItems do
  @moduledoc """
  Persisted autonomy work graph and minimal orchestration loop.
  """

  import Ecto.Query

  alias HydraX.Budget
  alias HydraX.Config
  alias HydraX.LLM.Router
  alias HydraX.Memory
  alias HydraX.Memory.Entry
  alias HydraX.Repo
  alias HydraX.Workspace

  alias HydraX.Runtime.{
    AgentProfile,
    Agents,
    ApprovalRecord,
    Artifact,
    Autonomy,
    Coordination,
    Helpers,
    ScheduledJob,
    WorkItem
  }

  @claim_ttl_seconds 180
  @terminal_work_item_statuses ~w(completed failed canceled)

  def list_work_items(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    status = Keyword.get(opts, :status)
    statuses = Keyword.get(opts, :statuses)
    kind = Keyword.get(opts, :kind)
    assigned_role = Keyword.get(opts, :assigned_role)
    agent_id = Keyword.get(opts, :agent_id) || Keyword.get(opts, :assigned_agent_id)
    parent_work_item_id = Keyword.get(opts, :parent_work_item_id)
    preload? = Keyword.get(opts, :preload, true)

    query =
      if preload? do
        preload(WorkItem, [
          :assigned_agent,
          :delegated_by_agent,
          :artifacts,
          :approval_records,
          :child_work_items
        ])
      else
        WorkItem
      end

    query
    |> maybe_filter_work_item_status(status)
    |> maybe_filter_work_item_statuses(statuses)
    |> maybe_filter_work_item_kind(kind)
    |> maybe_filter_work_item_role(assigned_role)
    |> maybe_filter_work_item_agent(agent_id)
    |> maybe_filter_work_item_parent(parent_work_item_id)
    |> order_by([work_item], desc: work_item.priority, asc: work_item.inserted_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  def get_work_item!(id) do
    WorkItem
    |> Repo.get!(id)
    |> Repo.preload([
      :assigned_agent,
      :delegated_by_agent,
      :artifacts,
      :approval_records,
      :child_work_items
    ])
  end

  def change_work_item(work_item \\ %WorkItem{}, attrs \\ %{}) do
    WorkItem.changeset(work_item, normalize_work_item_attrs(attrs, work_item))
  end

  def save_work_item(attrs) when is_map(attrs), do: save_work_item(%WorkItem{}, attrs)

  def save_work_item(%WorkItem{} = work_item, attrs) do
    work_item
    |> WorkItem.changeset(normalize_work_item_attrs(attrs, work_item))
    |> Repo.insert_or_update()
  end

  def list_artifacts(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    work_item_id = Keyword.get(opts, :work_item_id)
    type = Keyword.get(opts, :type)

    Artifact
    |> preload([:work_item])
    |> maybe_filter_artifact_work_item(work_item_id)
    |> maybe_filter_artifact_type(type)
    |> order_by([artifact], desc: artifact.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def get_artifact!(id) do
    Artifact
    |> Repo.get!(id)
    |> Repo.preload([:work_item])
  end

  def work_item_artifacts(work_item_id) when is_integer(work_item_id) do
    list_artifacts(work_item_id: work_item_id, limit: 100)
  end

  def promoted_work_item_memories(%WorkItem{} = work_item) do
    work_item
    |> promoted_memory_ids()
    |> promoted_memories_by_ids()
  end

  def promoted_work_item_memories(work_item_id) when is_integer(work_item_id) do
    work_item_id
    |> get_work_item!()
    |> promoted_work_item_memories()
  end

  def delegation_batch_snapshot(work_item_or_id)

  def delegation_batch_snapshot(work_item_id) when is_integer(work_item_id) do
    work_item_id
    |> get_work_item!()
    |> delegation_batch_snapshot()
  end

  def delegation_batch_snapshot(%WorkItem{} = work_item) do
    work_item
    |> build_delegation_batch_snapshot(delegation_batch_children(work_item))
    |> case do
      %{"expected_count" => expected_count} = snapshot when expected_count > 1 ->
        snapshot

      _ ->
        nil
    end
  end

  def delegation_batch_snapshot(work_item) when is_map(work_item) do
    work_item
    |> build_delegation_batch_snapshot(delegation_batch_children(work_item))
    |> case do
      %{"expected_count" => expected_count} = snapshot when expected_count > 1 ->
        snapshot

      _ ->
        nil
    end
  end

  def create_artifact(attrs) when is_map(attrs) do
    normalized = Helpers.normalize_string_keys(attrs)
    work_item_id = normalized["work_item_id"]
    artifact_type = normalized["type"] || "note"

    normalized =
      normalized
      |> Map.put_new("version", next_artifact_version(work_item_id, artifact_type))
      |> Map.put_new("payload", %{})
      |> Map.put_new("provenance", %{})
      |> Map.put_new("metadata", %{})

    %Artifact{}
    |> Artifact.changeset(normalized)
    |> Repo.insert()
  end

  def list_approval_records(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    subject_type = Keyword.get(opts, :subject_type)
    subject_id = Keyword.get(opts, :subject_id)
    work_item_id = Keyword.get(opts, :work_item_id)
    reviewer_agent_id = Keyword.get(opts, :reviewer_agent_id)
    decision = Keyword.get(opts, :decision)

    ApprovalRecord
    |> preload([:work_item, :reviewer_agent])
    |> maybe_filter_approval_subject(subject_type, subject_id)
    |> maybe_filter_approval_work_item(work_item_id)
    |> maybe_filter_approval_reviewer(reviewer_agent_id)
    |> maybe_filter_approval_decision(decision)
    |> order_by([record], desc: record.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def approval_records_for_subject(subject_type, subject_id)
      when is_binary(subject_type) and is_integer(subject_id) do
    list_approval_records(subject_type: subject_type, subject_id: subject_id, limit: 100)
  end

  def artifact_approval_records(artifact_id) when is_integer(artifact_id) do
    approval_records_for_subject("artifact", artifact_id)
  end

  def create_approval_record(attrs) when is_map(attrs) do
    attrs
    |> Helpers.normalize_string_keys()
    |> Map.put_new("metadata", %{})
    |> then(fn normalized ->
      %ApprovalRecord{}
      |> ApprovalRecord.changeset(normalized)
      |> Repo.insert()
    end)
  end

  def approve_work_item!(id, attrs \\ %{}) when is_integer(id) do
    work_item = get_work_item!(id)
    attrs = Helpers.normalize_string_keys(attrs)
    requested_action = attrs["requested_action"] || "promote_work_item"

    unless approval_action_allowed?(work_item, requested_action) do
      raise ArgumentError,
            "approval action #{requested_action} is not allowed for work item ##{work_item.id} at stage #{work_item.approval_stage}"
    end

    {:ok, record} =
      create_approval_record(%{
        "subject_type" => "work_item",
        "subject_id" => work_item.id,
        "requested_action" => requested_action,
        "decision" => "approved",
        "rationale" => attrs["rationale"] || "Approved for promotion.",
        "promoted_at" => attrs["promoted_at"] || DateTime.utc_now(),
        "reviewer_agent_id" => attrs["reviewer_agent_id"],
        "work_item_id" => attrs["work_item_id"],
        "metadata" => attrs["metadata"] || %{}
      })

    {:ok, updated} =
      save_work_item(work_item, %{
        "approval_stage" => next_approval_stage(work_item, requested_action),
        "result_refs" =>
          approval_result_refs(work_item, record, requested_action, attrs["metadata"] || %{}),
        "runtime_state" =>
          append_history(work_item.runtime_state, "approved", %{
            "approved_at" => DateTime.utc_now(),
            "approval_record_id" => record.id,
            "requested_action" => requested_action
          })
      })

    promote_artifacts!(updated, requested_action, record, attrs["metadata"] || %{})
    updated = maybe_promote_artifact_derived_work_item(updated, requested_action)
    updated = maybe_complete_publish_review_work_item(updated, requested_action, record)

    {updated, record}
  end

  def reject_work_item!(id, attrs \\ %{}) when is_integer(id) do
    work_item = get_work_item!(id)
    attrs = Helpers.normalize_string_keys(attrs)
    requested_action = attrs["requested_action"] || "promote_work_item"

    {:ok, record} =
      create_approval_record(%{
        "subject_type" => "work_item",
        "subject_id" => work_item.id,
        "requested_action" => requested_action,
        "decision" => "rejected",
        "rationale" => attrs["rationale"] || "Rejected during promotion review.",
        "promoted_at" => attrs["promoted_at"],
        "reviewer_agent_id" => attrs["reviewer_agent_id"],
        "work_item_id" => attrs["work_item_id"],
        "metadata" => attrs["metadata"] || %{}
      })

    {:ok, updated} =
      save_work_item(work_item, %{
        "status" => "failed",
        "approval_stage" => rejection_stage(work_item),
        "result_refs" =>
          rejection_result_refs(work_item, record, requested_action, attrs["metadata"] || %{}),
        "runtime_state" =>
          append_history(work_item.runtime_state, "rejected", %{
            "rejected_at" => DateTime.utc_now(),
            "approval_record_id" => record.id,
            "requested_action" => requested_action
          })
      })

    reject_artifacts!(updated, requested_action, record, attrs["metadata"] || %{})
    updated = maybe_reject_publish_review_work_item(updated, requested_action, record)

    {updated, record}
  end

  def approve_artifact!(id, attrs \\ %{}) when is_integer(id) do
    artifact = get_artifact!(id)
    attrs = Helpers.normalize_string_keys(attrs)
    requested_action = attrs["requested_action"] || "promote_artifact"
    rationale = attrs["rationale"] || "Approved artifact for promotion."

    {updated, record} =
      record_artifact_decision!(
        artifact,
        requested_action,
        "approved",
        rationale,
        attrs["metadata"] || %{},
        attrs["reviewer_agent_id"],
        attrs["work_item_id"]
      )

    maybe_promote_artifact_derived_artifact(updated, requested_action)

    {updated, record}
  end

  def reject_artifact!(id, attrs \\ %{}) when is_integer(id) do
    artifact = get_artifact!(id)
    attrs = Helpers.normalize_string_keys(attrs)
    requested_action = attrs["requested_action"] || "promote_artifact"
    rationale = attrs["rationale"] || "Rejected artifact during promotion review."

    record_artifact_decision!(
      artifact,
      requested_action,
      "rejected",
      rationale,
      attrs["metadata"] || %{},
      attrs["reviewer_agent_id"],
      attrs["work_item_id"]
    )
  end

  def cancel_work_item!(id) do
    work_item = get_work_item!(id)
    {:ok, updated} = save_work_item(work_item, %{"status" => "canceled"})
    updated
  end

  def claim_work_item(%WorkItem{} = work_item, opts \\ []) do
    metadata = Map.new(Keyword.get(opts, :metadata, %{}))
    agent = Keyword.get(opts, :agent)

    with {:ok, _lease} <-
           Coordination.claim_lease(lease_name(work_item.id),
             ttl_seconds: Keyword.get(opts, :ttl_seconds, @claim_ttl_seconds),
             metadata:
               Map.merge(metadata, %{
                 "work_item_id" => work_item.id,
                 "assigned_role" => work_item.assigned_role
               })
           ) do
      ownership = claimed_work_item_ownership(work_item.id, "claimed")
      {assigned_agent_id, work_item_metadata} = claimed_work_item_assignment(work_item, agent)

      claim_attrs =
        %{
          "status" => "claimed",
          "metadata" => put_work_item_ownership(work_item_metadata, ownership),
          "runtime_state" =>
            append_history(work_item.runtime_state, "claimed", %{
              "claimed_at" => DateTime.utc_now(),
              "lease_name" => lease_name(work_item.id),
              "lease_owner" => ownership["owner"]
            })
        }
        |> maybe_put_claimed_agent_id(assigned_agent_id)

      save_work_item(work_item, claim_attrs)
    end
  end

  def list_owned_resumable_work_items(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    owner = Coordination.status().owner

    WorkItem
    |> where([work_item], work_item.status in ["claimed", "running", "blocked", "replayed"])
    |> order_by([work_item], desc: work_item.priority, asc: work_item.inserted_at)
    |> limit(^max(limit * 3, limit))
    |> Repo.all()
    |> Enum.filter(&owned_resumable_work_item?(&1, owner))
    |> Enum.take(limit)
    |> Enum.map(&get_work_item!(&1.id))
  end

  def resume_owned_work_items(opts \\ []) do
    owner = Coordination.status().owner
    limit = Keyword.get(opts, :limit, 50)

    summary =
      list_owned_resumable_work_items(limit: limit)
      |> Enum.reduce(resume_work_item_summary(owner), fn work_item, acc ->
        case replay_claim_work_item(work_item) do
          {:ok, claimed} ->
            case replay_agent_for_work_item(claimed) do
              {:ok, replay_work_item, %AgentProfile{} = replay_agent} ->
                case run_autonomy_cycle(
                       replay_agent.id,
                       Keyword.put(opts, :work_item_id, replay_work_item.id)
                     ) do
                  {:ok, summary} ->
                    accumulate_resumed_work_item(acc, replay_work_item, summary)

                  {:error, reason} ->
                    accumulate_resume_work_item_error(acc, replay_work_item, reason)
                end

              {:error, :missing_agent} ->
                accumulate_skipped_work_item(acc, claimed, "missing_agent")
            end

          {:error, {:taken, lease}} ->
            _ = note_remote_work_item_ownership(work_item, lease, "claimed_remote")
            accumulate_skipped_work_item(acc, work_item, "lease_owned_elsewhere")

          {:error, reason} ->
            accumulate_resume_work_item_error(acc, work_item, reason)
        end
      end)

    _ = HydraX.Runtime.Jobs.record_scheduler_pass(:work_item_replays, summary)
    summary
  end

  def cleanup_stale_work_item_claims(opts \\ []) do
    owner = Coordination.status().owner
    limit = Keyword.get(opts, :limit, 50)

    summary =
      list_stale_claimed_work_items(limit: limit)
      |> Enum.reduce(stale_claim_cleanup_summary(owner), fn work_item, acc ->
        refreshed = get_work_item!(work_item.id)

        cond do
          stale_work_item_ownership?(refreshed) ->
            case expire_stale_work_item_ownership(refreshed) do
              {:ok, expired_work_item} ->
                accumulate_stale_claim_cleanup(acc, expired_work_item)

              {:error, reason} ->
                accumulate_stale_claim_cleanup_error(acc, refreshed, reason)
            end

          work_item_ownership_active?(refreshed) ->
            accumulate_stale_claim_cleanup_skip(acc, refreshed, "lease_restored")

          true ->
            accumulate_stale_claim_cleanup_skip(acc, refreshed, "already_cleared")
        end
      end)

    _ = HydraX.Runtime.Jobs.record_scheduler_pass(:stale_work_item_claims, summary)
    summary
  end

  def recover_orphaned_work_assignments(opts \\ []) do
    owner = Coordination.status().owner
    limit = Keyword.get(opts, :limit, 50)

    summary =
      list_orphaned_work_assignments(limit: limit)
      |> Enum.reduce(reassignment_summary(owner), fn work_item, acc ->
        case recover_claim_work_item(work_item) do
          {:ok, claimed} ->
            case reassign_orphaned_work_item(claimed) do
              {:ok, recovered_work_item, %AgentProfile{} = recovered_agent} ->
                pressure = worker_pressure_entry(recovered_agent.id) || %{}
                capacity_posture = pressure[:capacity_posture] || pressure["capacity_posture"]

                if recover_work_item_immediately?(pressure) do
                  case run_autonomy_cycle(
                         recovered_agent.id,
                         Keyword.put(opts, :work_item_id, recovered_work_item.id)
                       ) do
                    {:ok, result} ->
                      accumulate_reassigned_work_item(
                        acc,
                        recovered_work_item,
                        Map.put(result, :capacity_posture, capacity_posture),
                        "reassigned_executed"
                      )

                    {:error, reason} ->
                      accumulate_reassignment_error(acc, recovered_work_item, reason)
                  end
                else
                  case queue_recovered_work_item(recovered_work_item, claimed) do
                    {:ok, queued_work_item} ->
                      accumulate_reassigned_work_item(
                        acc,
                        queued_work_item,
                        %{
                          status: queued_work_item.status,
                          action: "reassigned_queued",
                          capacity_posture: capacity_posture,
                          queue_reason: "worker_saturated"
                        },
                        "reassigned_queued"
                      )

                    {:error, reason} ->
                      accumulate_reassignment_error(acc, recovered_work_item, reason)
                  end
                end

              {:error, :missing_agent} ->
                accumulate_reassignment_skip(acc, claimed, "missing_agent")

              {:error, reason} ->
                accumulate_reassignment_error(acc, claimed, reason)
            end

          {:error, {:taken, lease}} ->
            _ = note_remote_work_item_ownership(work_item, lease, "claimed_remote")
            accumulate_reassignment_skip(acc, work_item, "lease_owned_elsewhere")

          {:error, reason} ->
            accumulate_reassignment_error(acc, work_item, reason)
        end
      end)

    _ = HydraX.Runtime.Jobs.record_scheduler_pass(:assignment_recoveries, summary)
    summary
  end

  def process_role_queued_work(opts \\ []) do
    owner = Coordination.status().owner
    limit = Keyword.get(opts, :limit, 50)

    summary =
      drain_role_queued_work(
        Keyword.put(opts, :scheduler_pass, "role_queue_dispatch"),
        role_queue_dispatch_summary(owner),
        limit,
        0
      )

    _ = HydraX.Runtime.Jobs.record_scheduler_pass(:role_queue_dispatches, summary)
    summary
  end

  def run_autonomy_cycle(agent_id, opts \\ []) when is_integer(agent_id) do
    agent = Agents.get_agent!(agent_id)

    if agent.status != "active" do
      {:ok, %{agent: agent, status: "skipped", processed_count: 0, reason: "agent_inactive"}}
    else
      with {:idle, nil} <- maybe_resume_specific_work_item(agent, opts),
           {:idle, nil} <- maybe_expand_blocked_delegation_batch(agent, opts),
           {:idle, nil} <- maybe_finalize_blocked_parent(agent, opts),
           {:idle, nil} <- maybe_run_next_work_item(agent, opts) do
        {:ok, %{agent: agent, status: "idle", processed_count: 0, artifacts: []}}
      else
        {:processed, summary} -> {:ok, Map.put(summary, :agent, agent)}
      end
    end
  end

  def autonomy_status do
    all_work_items = list_work_items(limit: 500, preload: false)

    counts =
      WorkItem
      |> group_by([work_item], work_item.status)
      |> select([work_item], {work_item.status, count(work_item.id)})
      |> Repo.all()
      |> Map.new()

    now = DateTime.utc_now()

    overdue_count =
      Repo.one(
        from work_item in WorkItem,
          where:
            not is_nil(work_item.deadline_at) and work_item.deadline_at < ^now and
              work_item.status not in ["completed", "canceled"],
          select: count(work_item.id)
      )

    pending_review_count =
      Repo.one(
        from work_item in WorkItem,
          where:
            work_item.review_required == true and
              work_item.approval_stage not in ["operator_approved", "merge_ready"],
          select: count(work_item.id)
      )

    pending_operator_approval_count =
      Repo.one(
        from work_item in WorkItem,
          where:
            work_item.kind in ["engineering", "extension"] and work_item.status == "completed" and
              work_item.approval_stage == "validated",
          select: count(work_item.id)
      )

    pending_extension_enablement_count =
      Repo.one(
        from work_item in WorkItem,
          where:
            work_item.kind == "extension" and work_item.status == "completed" and
              work_item.approval_stage in ["validated", "operator_approved"],
          select: count(work_item.id)
      )

    approval_decisions =
      ApprovalRecord
      |> group_by([record], record.decision)
      |> select([record], {record.decision, count(record.id)})
      |> Repo.all()
      |> Map.new()

    active_autonomy_job_count =
      Repo.one(
        from job in ScheduledJob,
          where: job.kind == "autonomy" and job.enabled == true,
          select: count(job.id)
      )

    autonomy_agents =
      Agents.list_agents()
      |> Enum.filter(&(Map.get(capability_profile(&1), "max_autonomy_level") != "observe"))

    unsafe_request_count =
      Enum.count(
        all_work_items,
        &(not is_nil(get_in(&1.result_refs || %{}, ["policy_failure", "type"])))
      )

    budget_blocked_count =
      Enum.count(all_work_items, &budget_policy_failure?(&1.result_refs || %{}))

    auto_assigned_count =
      Enum.count(all_work_items, &assignment_resolved?(&1))

    capability_fallback_count =
      Enum.count(all_work_items, &(assignment_strategy(&1) == "capability_fallback"))

    role_only_open_count =
      Enum.count(all_work_items, &role_only_assignment?(&1))

    active_claimed_count =
      Enum.count(all_work_items, &work_item_ownership_active?/1)

    stale_claimed_count =
      Enum.count(all_work_items, &stale_work_item_ownership?/1)

    remote_claimed_count =
      Enum.count(all_work_items, &work_item_remotely_owned?/1)

    orphaned_assignment_count =
      Enum.count(all_work_items, &orphaned_work_assignment?/1)

    role_queue_backlog =
      build_role_queue_backlog(all_work_items, autonomy_agents)

    deferred_role_queue_count =
      Enum.reduce(role_queue_backlog, 0, fn entry, acc ->
        acc + (entry.deferred_count || 0)
      end)

    worker_pressure =
      build_worker_pressure(all_work_items, autonomy_agents, role_queue_backlog)

    delegation_supervision =
      build_delegation_supervision(all_work_items, autonomy_agents, worker_pressure)

    capability_drifts =
      autonomy_agents
      |> Enum.map(fn agent ->
        drift = Autonomy.capability_drift(agent.role, capability_profile(agent))

        if drift == %{} do
          nil
        else
          %{
            agent_id: agent.id,
            agent_name: agent.name,
            role: agent.role,
            drift: drift
          }
        end
      end)
      |> Enum.reject(&is_nil/1)

    %{
      counts: counts,
      overdue_count: overdue_count,
      pending_review_count: pending_review_count,
      pending_operator_approval_count: pending_operator_approval_count,
      pending_extension_enablement_count: pending_extension_enablement_count,
      approval_decisions: approval_decisions,
      active_autonomy_job_count: active_autonomy_job_count,
      unsafe_request_count: unsafe_request_count,
      budget_blocked_count: budget_blocked_count,
      auto_assigned_count: auto_assigned_count,
      capability_fallback_count: capability_fallback_count,
      role_only_open_count: role_only_open_count,
      active_claimed_count: active_claimed_count,
      stale_claimed_count: stale_claimed_count,
      remote_claimed_count: remote_claimed_count,
      orphaned_assignment_count: orphaned_assignment_count,
      deferred_role_queue_count: deferred_role_queue_count,
      autonomy_agent_count: length(autonomy_agents),
      active_roles: autonomy_agents |> Enum.map(& &1.role) |> Enum.frequencies(),
      role_queue_backlog: role_queue_backlog,
      worker_pressure: worker_pressure,
      delegation_supervision: delegation_supervision,
      capability_drifts: capability_drifts,
      recent_work_items: list_work_items(limit: 6, preload: true),
      recent_approvals: list_approval_records(limit: 6)
    }
  end

  def capability_profile(%AgentProfile{} = agent) do
    Autonomy.ensure_capability_profile(agent.role, agent.capability_profile || %{})
  end

  defp assignment_resolved?(%WorkItem{} = work_item) do
    is_map(get_in(work_item.metadata || %{}, ["assignment_resolution"]))
  end

  defp assignment_strategy(%WorkItem{} = work_item) do
    get_in(work_item.metadata || %{}, ["assignment_resolution", "strategy"])
  end

  defp role_only_assignment?(%WorkItem{} = work_item) do
    work_item.status not in @terminal_work_item_statuses and is_nil(work_item.assigned_agent_id)
  end

  defp work_item_ownership_active?(%WorkItem{} = work_item) do
    ownership = get_in(work_item.metadata || %{}, ["ownership"]) || %{}

    ownership["active"] == true and not stale_or_missing_work_item_lease?(work_item)
  end

  defp stale_work_item_ownership?(%WorkItem{} = work_item) do
    ownership = get_in(work_item.metadata || %{}, ["ownership"]) || %{}

    ownership["active"] == true and stale_or_missing_work_item_lease?(work_item)
  end

  defp work_item_remotely_owned?(%WorkItem{} = work_item) do
    ownership = get_in(work_item.metadata || %{}, ["ownership"]) || %{}

    ownership["active"] == true and ownership["owner"] not in [nil, Coordination.status().owner] and
      not stale_or_missing_work_item_lease?(work_item)
  end

  defp build_role_queue_backlog(all_work_items, autonomy_agents) do
    worker_counts =
      autonomy_agents
      |> Enum.map(& &1.role)
      |> Enum.reject(&is_nil/1)
      |> Enum.frequencies()

    claimed_counts =
      all_work_items
      |> Enum.filter(&work_item_ownership_active?/1)
      |> Enum.map(& &1.assigned_role)
      |> Enum.reject(&is_nil/1)
      |> Enum.frequencies()

    stale_claimed_counts =
      all_work_items
      |> Enum.filter(&stale_work_item_ownership?/1)
      |> Enum.map(& &1.assigned_role)
      |> Enum.reject(&is_nil/1)
      |> Enum.frequencies()

    queued_by_role =
      all_work_items
      |> Enum.filter(&role_queue_candidate?/1)
      |> Enum.group_by(& &1.assigned_role)

    deferred_by_role =
      all_work_items
      |> Enum.filter(fn work_item ->
        metadata = work_item.metadata || %{}

        work_item.status in ["planned", "replayed"] and
          is_nil(work_item.assigned_agent_id) and
          metadata["assignment_mode"] == "role_claim" and
          role_queue_dispatch_deferred?(work_item)
      end)
      |> Enum.group_by(& &1.assigned_role)

    Map.keys(queued_by_role)
    |> Kernel.++(Map.keys(deferred_by_role))
    |> Enum.uniq()
    |> Enum.map(fn role ->
      queued_items = Map.get(queued_by_role, role, [])
      deferred_items = Map.get(deferred_by_role, role, [])
      items = queued_items ++ deferred_items

      %{
        role: role,
        queued_count: length(queued_items),
        deferred_count: length(deferred_items),
        worker_count: Map.get(worker_counts, role, 0),
        active_claimed_count: Map.get(claimed_counts, role, 0),
        stale_claimed_count: Map.get(stale_claimed_counts, role, 0),
        highest_priority:
          items
          |> Enum.map(&(&1.priority || 0))
          |> Enum.max(fn -> 0 end)
      }
    end)
    |> Enum.sort_by(fn entry -> {-entry.queued_count, entry.role || ""} end)
  end

  defp build_worker_pressure(all_work_items, autonomy_agents, role_queue_backlog) do
    role_queue_counts = Map.new(role_queue_backlog, &{&1.role, &1.queued_count})

    autonomy_agents
    |> Enum.map(fn agent ->
      assigned_items =
        Enum.filter(all_work_items, fn work_item ->
          work_item.assigned_agent_id == agent.id and
            work_item.status not in @terminal_work_item_statuses
        end)

      assigned_open_count = length(assigned_items)
      active_claimed_count = Enum.count(assigned_items, &work_item_ownership_active?/1)
      stale_claimed_count = Enum.count(assigned_items, &stale_work_item_ownership?/1)
      blocked_count = Enum.count(assigned_items, &(&1.status == "blocked"))
      failed_count = Enum.count(assigned_items, &(&1.status == "failed"))
      shared_role_queue_count = Map.get(role_queue_counts, agent.role, 0)

      %{
        agent_id: agent.id,
        agent_name: agent.name,
        role: agent.role,
        assigned_open_count: assigned_open_count,
        active_claimed_count: active_claimed_count,
        stale_claimed_count: stale_claimed_count,
        blocked_count: blocked_count,
        failed_count: failed_count,
        shared_role_queue_count: shared_role_queue_count,
        capacity_posture:
          worker_capacity_posture(
            assigned_open_count,
            active_claimed_count,
            shared_role_queue_count
          )
      }
    end)
    |> Enum.sort_by(fn entry ->
      {worker_capacity_rank(entry.capacity_posture), -(entry.shared_role_queue_count || 0),
       -(entry.assigned_open_count || 0), entry.agent_name || ""}
    end)
  end

  defp build_delegation_supervision(all_work_items, autonomy_agents, worker_pressure) do
    agents_by_id = Map.new(autonomy_agents, &{&1.id, &1})
    role_capacity = delegation_role_capacity_from_worker_pressure(worker_pressure)

    all_work_items
    |> Enum.filter(fn work_item ->
      work_item.status == "blocked" and work_item.execution_mode == "delegate"
    end)
    |> Enum.map(fn work_item ->
      {work_item, delegation_batch_snapshot(work_item)}
    end)
    |> Enum.reject(fn {_work_item, snapshot} -> snapshot in [nil, %{}] end)
    |> Enum.group_by(fn {work_item, _snapshot} ->
      {work_item.assigned_agent_id, work_item.assigned_role}
    end)
    |> Enum.map(fn {{agent_id, role}, entries} ->
      agent = Map.get(agents_by_id, agent_id)
      snapshots = Enum.map(entries, fn {_work_item, snapshot} -> snapshot end)
      constrained_roles = aggregate_constrained_pending_roles(snapshots, role_capacity)

      %{
        agent_id: agent_id,
        agent_name: agent && agent.name,
        role: role || (agent && agent.role),
        active_batches: length(entries),
        pending_children: Enum.reduce(snapshots, 0, &((&1["pending_count"] || 0) + &2)),
        active_children: Enum.reduce(snapshots, 0, &((&1["active_count"] || 0) + &2)),
        terminal_children: Enum.reduce(snapshots, 0, &((&1["terminal_count"] || 0) + &2)),
        constrained_roles: constrained_roles,
        highest_priority:
          entries
          |> Enum.map(fn {work_item, _snapshot} -> work_item.priority || 0 end)
          |> Enum.max(fn -> 0 end)
      }
    end)
    |> Enum.sort_by(fn entry ->
      {-(entry.active_batches || 0), -(entry.pending_children || 0), entry.agent_name || "",
       entry.role || ""}
    end)
  end

  defp delegation_role_capacity_from_worker_pressure(entries) when is_list(entries) do
    entries
    |> Enum.group_by(& &1.role)
    |> Map.new(fn {role, workers} ->
      {role,
       %{
         idle_workers: Enum.count(workers, &(&1.capacity_posture == "idle")),
         available_workers: Enum.count(workers, &(&1.capacity_posture == "available")),
         busy_workers: Enum.count(workers, &(&1.capacity_posture == "busy")),
         saturated_workers: Enum.count(workers, &(&1.capacity_posture == "saturated"))
       }}
    end)
  end

  defp delegation_role_capacity_from_worker_pressure(_entries), do: %{}

  defp aggregate_constrained_pending_roles(snapshots, role_capacity) do
    snapshots
    |> Enum.flat_map(fn snapshot ->
      snapshot
      |> Map.get("pending_roles", %{})
      |> Enum.to_list()
    end)
    |> Enum.reduce(%{}, fn {role, count}, acc ->
      pressure = Map.get(role_capacity, role, %{})

      available_workers =
        (pressure[:idle_workers] || pressure["idle_workers"] || 0) +
          (pressure[:available_workers] || pressure["available_workers"] || 0)

      if count > 0 and available_workers <= 0 do
        Map.update(acc, role, count, &(&1 + count))
      else
        acc
      end
    end)
  end

  defp worker_capacity_posture(assigned_open_count, active_claimed_count, shared_role_queue_count) do
    cond do
      assigned_open_count >= 4 or (active_claimed_count >= 2 and shared_role_queue_count > 0) ->
        "saturated"

      assigned_open_count >= 2 or shared_role_queue_count > 0 ->
        "busy"

      assigned_open_count == 0 and shared_role_queue_count == 0 ->
        "idle"

      true ->
        "available"
    end
  end

  defp worker_capacity_rank("saturated"), do: 0
  defp worker_capacity_rank("busy"), do: 1
  defp worker_capacity_rank("available"), do: 2
  defp worker_capacity_rank("idle"), do: 3
  defp worker_capacity_rank(_posture), do: 4

  defp owned_resumable_work_item?(%WorkItem{} = work_item, owner) do
    ownership = get_in(work_item.metadata || %{}, ["ownership"]) || %{}

    case ownership["owner"] do
      ^owner ->
        ownership["active"] == true

      nil ->
        false

      _other ->
        ownership["active"] == true or stale_or_missing_work_item_lease?(work_item)
    end
  end

  defp stale_or_missing_work_item_lease?(%WorkItem{} = work_item) do
    case Coordination.active_lease(lease_name(work_item.id)) do
      nil -> true
      _lease -> false
    end
  end

  defp maybe_resume_specific_work_item(_agent, opts) when not is_list(opts), do: {:idle, nil}

  defp maybe_resume_specific_work_item(agent, opts) do
    case Keyword.get(opts, :work_item_id) do
      nil ->
        {:idle, nil}

      work_item_id ->
        work_item = get_work_item!(work_item_id)

        cond do
          not work_item_assigned_to_agent?(work_item, agent) ->
            {:idle, nil}

          work_item.status == "blocked" and blocked_parent_ready?(work_item) ->
            finalize_blocked_parent(agent, work_item)

          work_item.status == "planned" ->
            process_specific_work_item(agent, work_item, opts)

          work_item.status in ["claimed", "running", "replayed"] ->
            resume_claimed_work_item(agent, work_item, opts)

          true ->
            {:idle, nil}
        end
    end
  end

  defp maybe_finalize_blocked_parent(agent, _opts) do
    blocked_parent =
      WorkItem
      |> where(
        [work_item],
        work_item.status == "blocked" and
          (work_item.assigned_agent_id == ^agent.id or
             (is_nil(work_item.assigned_agent_id) and work_item.assigned_role == ^agent.role))
      )
      |> order_by([work_item], desc: work_item.priority, asc: work_item.inserted_at)
      |> limit(10)
      |> Repo.all()
      |> Enum.find(&blocked_parent_ready?/1)

    case blocked_parent do
      nil ->
        {:idle, nil}

      %WorkItem{} = work_item ->
        finalize_blocked_parent(agent, work_item)
    end
  end

  defp maybe_expand_blocked_delegation_batch(agent, _opts) do
    expandable_parent =
      WorkItem
      |> where(
        [work_item],
        work_item.status == "blocked" and
          work_item.execution_mode == "delegate" and
          (work_item.assigned_agent_id == ^agent.id or
             (is_nil(work_item.assigned_agent_id) and work_item.assigned_role == ^agent.role))
      )
      |> order_by([work_item], desc: work_item.priority, asc: work_item.inserted_at)
      |> limit(10)
      |> Repo.all()
      |> Enum.find(&delegation_batch_expandable?/1)

    case expandable_parent do
      nil ->
        {:idle, nil}

      %WorkItem{} = work_item ->
        expand_blocked_delegation_batch(agent, work_item)
    end
  end

  defp blocked_parent_ready?(%WorkItem{} = work_item) do
    children =
      list_work_items(
        parent_work_item_id: work_item.id,
        limit: delegated_child_limit(work_item),
        preload: false
      )

    expected_count = delegation_expected_count(work_item)

    children != [] and length(children) >= expected_count and
      Enum.all?(children, &terminal_work_item?/1)
  end

  defp terminal_work_item?(%WorkItem{status: status}), do: status in @terminal_work_item_statuses

  defp maybe_run_next_work_item(agent, opts) do
    case next_work_item_for_agent(agent) do
      nil ->
        {:idle, nil}

      %WorkItem{} = work_item ->
        case claim_work_item(work_item, agent: agent, metadata: %{"phase" => "run"}) do
          {:ok, claimed} ->
            case authorize_work_item(agent, claimed) do
              :ok ->
                process_work_item(agent, claimed, opts)
                |> finalize_claimed_summary(claimed)

              {:error, failure} ->
                block_work_item_for_policy(claimed, failure)
                |> finalize_claimed_summary(claimed)
            end

          {:error, {:taken, lease}} ->
            remote_work_item =
              work_item
              |> note_remote_work_item_ownership(lease, "claimed_remote")
              |> case do
                {:ok, updated} ->
                  case role_queue_dispatch_pass?(opts) do
                    true ->
                      case defer_role_queue_dispatch(updated, "claimed_remote", %{
                             "lease_owner" => lease.owner,
                             "lease_expires_at" => lease.expires_at
                           }) do
                        {:ok, deferred_work_item} -> deferred_work_item
                        _ -> updated
                      end

                    false ->
                      updated
                  end

                _ ->
                  work_item
              end

            if role_queue_dispatch_pass?(opts) do
              {:processed,
               %{
                 status: "skipped",
                 processed_count: 0,
                 action: "claimed_remote",
                 work_item: remote_work_item,
                 lease_owner: lease.owner,
                 lease_expires_at: lease.expires_at,
                 deferred_until:
                   get_in(remote_work_item.metadata || %{}, [
                     "role_queue_dispatch",
                     "deferred_until"
                   ])
               }}
            else
              {:idle, nil}
            end

          {:error, reason} ->
            {:processed,
             %{status: "failed", processed_count: 0, action: "claim_failed", error: reason}}
        end
    end
  end

  defp process_specific_work_item(agent, %WorkItem{} = work_item, opts) do
    case claim_work_item(work_item, agent: agent, metadata: %{"phase" => "run_specific"}) do
      {:ok, claimed} ->
        case authorize_work_item(agent, claimed) do
          :ok ->
            process_work_item(agent, claimed, opts)
            |> finalize_claimed_summary(claimed)

          {:error, failure} ->
            block_work_item_for_policy(claimed, failure)
            |> finalize_claimed_summary(claimed)
        end

      {:error, {:taken, lease}} ->
        note_remote_work_item_ownership(work_item, lease, "claimed_remote")
        {:idle, nil}

      {:error, reason} ->
        {:processed,
         %{status: "failed", processed_count: 0, action: "claim_failed", error: reason}}
    end
  end

  defp finalize_blocked_parent(_agent, %WorkItem{} = work_item) do
    case claim_work_item(work_item, metadata: %{"phase" => "finalize"}) do
      {:ok, claimed} ->
        do_finalize_blocked_parent(claimed)

      {:error, {:taken, lease}} ->
        note_remote_work_item_ownership(work_item, lease, "claimed_remote")
        {:idle, nil}

      {:error, reason} ->
        {:processed,
         %{status: "failed", processed_count: 0, action: "finalize_failed", error: reason}}
    end
  end

  defp expand_blocked_delegation_batch(agent, %WorkItem{} = work_item) do
    case claim_work_item(work_item, metadata: %{"phase" => "expand_delegate_batch"}) do
      {:ok, claimed} ->
        do_expand_blocked_delegation_batch(agent, claimed)

      {:error, {:taken, lease}} ->
        note_remote_work_item_ownership(work_item, lease, "claimed_remote")
        {:idle, nil}

      {:error, reason} ->
        {:processed,
         %{
           status: "failed",
           processed_count: 0,
           action: "delegation_expand_failed",
           error: reason
         }}
    end
  end

  defp do_expand_blocked_delegation_batch(%AgentProfile{} = agent, %WorkItem{} = claimed) do
    snapshot = delegation_batch_snapshot(claimed) || %{}
    available_slots = delegation_batch_available_slots(snapshot)
    pending_items = pending_delegation_batch_items(snapshot)

    if available_slots <= 0 or pending_items == [] do
      {:idle, nil}
    else
      delegated_children =
        claimed
        |> select_delegation_batch_entries_for_dispatch(
          pending_items,
          available_slots,
          Map.get(snapshot, "items", [])
        )
        |> Enum.map(&dispatch_delegated_batch_item(claimed, agent, &1))

      refreshed_parent =
        claimed.id
        |> get_work_item!()
        |> Map.update!(:metadata, fn metadata ->
          metadata || %{}
        end)

      refreshed_children = delegation_batch_children(refreshed_parent)
      batch_snapshot = build_delegation_batch_snapshot(refreshed_parent, refreshed_children)

      {:ok, artifact} =
        create_artifact(%{
          "work_item_id" => claimed.id,
          "type" => "plan",
          "title" => "Delegation batch expansion",
          "summary" =>
            "Expanded delegation batch with #{length(delegated_children)} additional child tasks",
          "body" => delegation_plan_body(refreshed_parent, delegated_children, batch_snapshot),
          "payload" => %{
            "delegated_work_item_ids" => Enum.map(delegated_children, & &1.child.id),
            "delegation_batch" => batch_snapshot,
            "delegated_work_items" =>
              Enum.map(delegated_children, fn entry ->
                %{
                  "id" => entry.child.id,
                  "kind" => entry.child.kind,
                  "goal" => entry.child.goal,
                  "assigned_role" => entry.child.assigned_role,
                  "delegation_context" => entry.delegation_context
                }
              end)
          },
          "provenance" => %{"source" => "autonomy", "phase" => "delegate_expand"},
          "confidence" => 0.74
        })

      {:ok, updated} =
        save_work_item(refreshed_parent, %{
          "status" => "blocked",
          "result_refs" =>
            refreshed_parent.result_refs
            |> append_artifact_ref(artifact.id)
            |> Map.put(
              "child_work_item_ids",
              refreshed_children |> Enum.map(& &1.id) |> Enum.uniq()
            ),
          "metadata" =>
            Map.put(refreshed_parent.metadata || %{}, "delegation_batch", batch_snapshot),
          "runtime_state" =>
            append_history(refreshed_parent.runtime_state, "blocked", %{
              "blocked_at" => DateTime.utc_now(),
              "reason" => "delegated_batch_expanded",
              "child_work_item_ids" => Enum.map(delegated_children, & &1.child.id)
            })
        })

      {:processed,
       %{
         status: "blocked",
         processed_count: 1,
         work_item: updated,
         artifacts: [artifact],
         action: "delegated_batch_expanded",
         delegated_work_items: Enum.map(delegated_children, & &1.child)
       }}
      |> finalize_claimed_summary(claimed)
    end
  end

  defp do_finalize_blocked_parent(%WorkItem{} = claimed) do
    children =
      list_work_items(
        parent_work_item_id: claimed.id,
        statuses: @terminal_work_item_statuses,
        limit: delegated_child_limit(claimed)
      )

    artifact_ids =
      children
      |> Enum.flat_map(fn child ->
        child.result_refs
        |> Map.get("artifact_ids", [])
        |> List.wrap()
      end)

    supporting_memories = finalized_child_findings(children)
    constraint_findings = constrained_child_findings(children)

    inherited_delivery_decisions =
      List.wrap(get_in(claimed.metadata || %{}, ["follow_up_context", "delivery_decisions"]))

    delivery_decisions =
      merge_supporting_findings(
        delivery_decision_findings(supporting_memories) ++ inherited_delivery_decisions
      )

    delivery_decision_snapshot =
      build_delivery_decision_snapshot(
        delivery_decisions,
        inherited_delivery_decisions,
        decision_basis: "planner_synthesis",
        decision_scope: "planner"
      )

    delegation_batch = build_delegation_batch_snapshot(claimed, children)

    {:ok, summary_artifact} =
      create_artifact(%{
        "work_item_id" => claimed.id,
        "type" => "decision_ledger",
        "title" => "Delegation synthesis",
        "summary" => delegation_summary_line(claimed, children, supporting_memories),
        "body" => delegation_summary_body(claimed, children, supporting_memories),
        "payload" => %{
          "decision_type" => "delegation_synthesis",
          "summary_source" => "planner",
          "child_work_item_ids" => Enum.map(children, & &1.id),
          "result_artifact_ids" => artifact_ids,
          "promoted_findings" => supporting_memories,
          "constraint_findings" => constraint_findings,
          "delegation_batch" => delegation_batch,
          "delivery_decisions" => delivery_decisions,
          "delivery_decision_snapshot" => delivery_decision_snapshot
        },
        "provenance" => %{
          "source" => "autonomy",
          "phase" => "finalize"
        },
        "confidence" => 0.72
      })

    {:ok, updated} =
      save_work_item(
        claimed,
        finalize_parent_attrs(
          claimed,
          children,
          summary_artifact,
          artifact_ids,
          supporting_memories,
          constraint_findings
        )
      )

    {:ok, updated, follow_up_work_item} =
      case maybe_enqueue_replan_follow_up(
             updated,
             summary_artifact,
             supporting_memories,
             constraint_findings
           ) do
        {:ok, replan_parent, %WorkItem{} = replan_item} ->
          {:ok, replan_parent, replan_item}

        {:ok, replan_parent, nil} ->
          maybe_enqueue_publish_follow_up(
            replan_parent,
            summary_artifact,
            supporting_memories
          )
      end

    {:processed,
     %{
       status: "completed",
       processed_count: 1,
       work_item: updated,
       artifacts: [summary_artifact],
       action: "finalized_blocked_parent",
       follow_up_work_item: follow_up_work_item
     }}
    |> finalize_claimed_summary(claimed)
  end

  defp resume_claimed_work_item(agent, %WorkItem{} = work_item, opts) do
    {:ok, resumed} =
      save_work_item(work_item, %{
        "metadata" =>
          put_work_item_ownership(
            work_item.metadata,
            claimed_work_item_ownership(work_item.id, "replayed")
          ),
        "runtime_state" =>
          append_history(work_item.runtime_state, "replayed", %{
            "replayed_at" => DateTime.utc_now(),
            "reason" => "owned_work_item_replay",
            "job_id" => Keyword.get(opts, :job_id)
          })
      })

    case authorize_work_item(agent, resumed) do
      :ok ->
        process_work_item(agent, resumed, opts)
        |> finalize_claimed_summary(resumed)

      {:error, failure} ->
        block_work_item_for_policy(resumed, failure)
        |> finalize_claimed_summary(resumed)
    end
  end

  defp work_item_assigned_to_agent?(%WorkItem{} = work_item, %AgentProfile{} = agent) do
    work_item.assigned_agent_id == agent.id or
      (is_nil(work_item.assigned_agent_id) and work_item.assigned_role == agent.role)
  end

  defp work_item_execution_deferred?(%WorkItem{} = work_item) do
    recovery = get_in(work_item.metadata || %{}, ["assignment_recovery"]) || %{}

    case parse_datetime(recovery["deferred_until"]) do
      %DateTime{} = deferred_until ->
        DateTime.compare(deferred_until, DateTime.utc_now()) == :gt

      _ ->
        false
    end
  end

  defp role_queue_dispatch_deferred?(%WorkItem{} = work_item) do
    dispatch = get_in(work_item.metadata || %{}, ["role_queue_dispatch"]) || %{}

    case parse_datetime(dispatch["deferred_until"]) do
      %DateTime{} = deferred_until ->
        DateTime.compare(deferred_until, DateTime.utc_now()) == :gt

      _ ->
        false
    end
  end

  defp replay_claim_work_item(%WorkItem{} = work_item) do
    metadata = %{
      "phase" => "replay",
      "work_item_id" => work_item.id,
      "assigned_role" => work_item.assigned_role
    }

    with {:ok, _lease} <-
           Coordination.claim_lease(lease_name(work_item.id),
             ttl_seconds: @claim_ttl_seconds,
             metadata: metadata
           ) do
      ownership = claimed_work_item_ownership(work_item.id, "replayed")

      save_work_item(work_item, %{
        "metadata" => put_work_item_ownership(work_item.metadata, ownership)
      })
    end
  end

  defp recover_claim_work_item(%WorkItem{} = work_item) do
    metadata = %{
      "phase" => "assignment_recovery",
      "work_item_id" => work_item.id,
      "assigned_role" => work_item.assigned_role,
      "assigned_agent_id" => work_item.assigned_agent_id
    }

    with {:ok, _lease} <-
           Coordination.claim_lease(lease_name(work_item.id),
             ttl_seconds: @claim_ttl_seconds,
             metadata: metadata
           ) do
      ownership = claimed_work_item_ownership(work_item.id, "recovering")

      save_work_item(work_item, %{
        "metadata" => put_work_item_ownership(work_item.metadata, ownership),
        "runtime_state" =>
          append_history(work_item.runtime_state, work_item.status || "planned", %{
            "recovered_at" => DateTime.utc_now(),
            "phase" => "assignment_recovery",
            "lease_name" => lease_name(work_item.id),
            "lease_owner" => ownership["owner"]
          })
      })
    end
  end

  defp replay_agent_for_work_item(%WorkItem{} = work_item) do
    cond do
      is_integer(work_item.assigned_agent_id) ->
        case active_agent_by_id(work_item.assigned_agent_id) do
          %AgentProfile{} = agent ->
            {:ok, work_item, agent}

          nil ->
            replay_reassign_work_item(work_item)
        end

      is_binary(work_item.assigned_role) ->
        case resolve_assigned_agent(role_queue_dispatch_attrs(work_item)) do
          %{agent: %AgentProfile{} = agent} ->
            {:ok, work_item, agent}

          _ ->
            {:error, :missing_agent}
        end

      true ->
        {:error, :missing_agent}
    end
  end

  defp active_agent_by_id(agent_id) when is_integer(agent_id) do
    Agents.list_agents()
    |> Enum.find(&(&1.id == agent_id and &1.status == "active"))
  end

  defp active_agent_by_id(_agent_id), do: nil

  defp replay_reassign_work_item(%WorkItem{} = work_item) do
    case resolve_assigned_agent(role_queue_dispatch_attrs(work_item)) do
      %{agent: %AgentProfile{} = agent, resolution: resolution} ->
        updated_resolution =
          resolution
          |> Map.put("strategy", "replay_reassignment")
          |> Map.put("reassigned_from_agent_id", work_item.assigned_agent_id)
          |> Map.put(
            "reasons",
            ["original assignee unavailable" | List.wrap(resolution["reasons"])]
          )

        {:ok, reassigned} =
          save_work_item(work_item, %{
            "assigned_agent_id" => agent.id,
            "metadata" =>
              put_assignment_resolution_metadata(work_item.metadata, updated_resolution)
          })

        {:ok, reassigned, agent}

      _ ->
        {:error, :missing_agent}
    end
  end

  defp list_orphaned_work_assignments(opts) do
    limit = Keyword.get(opts, :limit, 50)

    WorkItem
    |> where(
      [work_item],
      work_item.status in ["planned", "blocked"] and
        not is_nil(work_item.assigned_agent_id)
    )
    |> order_by([work_item], desc: work_item.priority, asc: work_item.inserted_at)
    |> limit(^max(limit * 3, limit))
    |> Repo.all()
    |> Enum.filter(&orphaned_work_assignment?/1)
    |> Enum.take(limit)
    |> Enum.map(&get_work_item!(&1.id))
  end

  defp list_stale_claimed_work_items(opts) do
    limit = Keyword.get(opts, :limit, 50)
    owner = Coordination.status().owner

    WorkItem
    |> where(
      [work_item],
      work_item.status in ["planned", "claimed", "running", "blocked", "replayed"]
    )
    |> order_by([work_item], desc: work_item.priority, asc: work_item.inserted_at)
    |> limit(^max(limit * 3, limit))
    |> Repo.all()
    |> Enum.filter(
      &(stale_work_item_ownership?(&1) and not locally_replayable_stale_claim?(&1, owner))
    )
    |> Enum.take(limit)
    |> Enum.map(&get_work_item!(&1.id))
  end

  defp locally_replayable_stale_claim?(%WorkItem{} = work_item, owner) do
    ownership = get_in(work_item.metadata || %{}, ["ownership"]) || %{}

    ownership["owner"] == owner and
      work_item.status in ["claimed", "running", "blocked", "replayed"]
  end

  defp orphaned_work_assignment?(%WorkItem{} = work_item) do
    is_integer(work_item.assigned_agent_id) and
      not work_item_ownership_active?(work_item) and
      is_nil(active_agent_by_id(work_item.assigned_agent_id))
  end

  defp reassign_orphaned_work_item(%WorkItem{} = work_item) do
    case resolve_assigned_agent(role_queue_dispatch_attrs(work_item)) do
      %{agent: %AgentProfile{} = agent, resolution: resolution} ->
        updated_resolution =
          resolution
          |> Map.put("strategy", "inactive_reassignment")
          |> Map.put("reassigned_from_agent_id", work_item.assigned_agent_id)
          |> Map.put("recovery_reason", "original assignee unavailable")
          |> Map.update(
            "reasons",
            ["original assignee unavailable"],
            &Enum.uniq(["original assignee unavailable" | List.wrap(&1)])
          )

        save_work_item(work_item, %{
          "assigned_agent_id" => agent.id,
          "metadata" =>
            put_assignment_resolution_metadata(work_item.metadata, updated_resolution),
          "runtime_state" =>
            append_history(work_item.runtime_state, work_item.status || "planned", %{
              "reassigned_at" => DateTime.utc_now(),
              "reason" => "inactive_assignee_recovery",
              "previous_agent_id" => work_item.assigned_agent_id,
              "assigned_agent_id" => agent.id
            })
        })
        |> case do
          {:ok, updated} -> {:ok, updated, agent}
          error -> error
        end

      _ ->
        {:error, :missing_agent}
    end
  end

  defp expire_stale_work_item_ownership(%WorkItem{} = work_item) do
    ownership =
      work_item.metadata
      |> put_work_item_ownership(
        Map.merge(claimed_work_item_ownership(work_item.id, "expired"), %{
          "active" => false,
          "expired_at" => DateTime.utc_now()
        })
      )

    save_work_item(work_item, %{
      "metadata" => ownership,
      "runtime_state" =>
        append_history(work_item.runtime_state, work_item.status || "planned", %{
          "expired_at" => DateTime.utc_now(),
          "reason" => "stale_claim_cleanup",
          "lease_name" => lease_name(work_item.id)
        })
    })
  end

  defp dispatchable_agents(limit) do
    active_agents =
      Agents.list_agents()
      |> Enum.filter(&(&1.status == "active"))
      |> Enum.sort_by(&{&1.role || "", &1.name || "", &1.id})

    priority_by_agent_id =
      role_queue_dispatch_plan(limit)
      |> Enum.with_index()
      |> Map.new()

    Enum.sort_by(active_agents, fn agent ->
      {Map.get(priority_by_agent_id, agent.id, 9_999), agent.role || "", agent.name || "",
       agent.id}
    end)
  end

  defp role_queue_dispatch_plan(limit) do
    role_queue_dispatch_candidates(limit)
    |> Enum.map(fn work_item ->
      work_item
      |> role_queue_dispatch_attrs()
      |> resolve_assigned_agent()
      |> case do
        %{agent: %AgentProfile{id: id}} -> id
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp role_queue_dispatch_candidates(limit) do
    list_work_items(limit: max(limit * 3, limit), preload: false)
    |> Enum.filter(&role_queue_candidate?/1)
    |> Enum.take(limit)
  end

  defp role_queue_candidate?(%WorkItem{} = work_item) do
    metadata = work_item.metadata || %{}

    work_item.status in ["planned", "replayed"] and
      is_nil(work_item.assigned_agent_id) and
      metadata["assignment_mode"] == "role_claim" and
      not role_queue_dispatch_deferred?(work_item)
  end

  defp role_queue_dispatch_attrs(%WorkItem{} = work_item) do
    %{
      "assigned_role" => work_item.assigned_role,
      "kind" => work_item.kind,
      "autonomy_level" => work_item.autonomy_level,
      "required_outputs" => work_item.required_outputs || %{},
      "deliverables" => work_item.deliverables || %{},
      "metadata" => work_item.metadata || %{}
    }
  end

  defp next_role_queued_work_item_for_agent(%AgentProfile{} = agent) do
    WorkItem
    |> where(
      [work_item],
      work_item.status in ["planned", "replayed"] and
        is_nil(work_item.assigned_agent_id) and work_item.assigned_role == ^agent.role
    )
    |> order_by([work_item], desc: work_item.priority, asc: work_item.inserted_at)
    |> limit(10)
    |> Repo.all()
    |> Enum.map(&get_work_item!(&1.id))
    |> Enum.find(&role_queue_candidate?/1)
  end

  defp drain_role_queued_work(_opts, summary, limit, _round)
       when summary.processed_count >= limit,
       do: summary

  defp drain_role_queued_work(_opts, summary, limit, round)
       when round >= max(limit, 1),
       do: summary

  defp drain_role_queued_work(opts, summary, limit, round) do
    agents = dispatchable_agents(limit)

    if agents == [] do
      summary
    else
      {updated_summary, progressed?} =
        Enum.reduce_while(agents, {summary, false}, fn agent, {acc, progressed?} ->
          if acc.processed_count >= limit do
            {:halt, {acc, progressed?}}
          else
            pressure = worker_pressure_entry(agent.id) || %{}

            if pressure[:capacity_posture] == "saturated" do
              case next_role_queued_work_item_for_agent(agent) do
                %WorkItem{} = work_item ->
                  case defer_role_queue_dispatch(work_item, "worker_saturated", %{
                         "capacity_posture" =>
                           pressure[:capacity_posture] || pressure["capacity_posture"]
                       }) do
                    {:ok, deferred_work_item} ->
                      {:cont,
                       {accumulate_role_queue_skip(
                          acc,
                          agent,
                          "worker_saturated",
                          pressure,
                          deferred_work_item
                        ), progressed?}}

                    {:error, _reason} ->
                      {:cont,
                       {accumulate_role_queue_skip(acc, agent, "worker_saturated", pressure),
                        progressed?}}
                  end

                nil ->
                  {:cont, {accumulate_role_queue_skip(acc, agent), progressed?}}
              end
            else
              case run_autonomy_cycle(agent.id, opts) do
                {:ok, %{status: "idle"}} ->
                  {:cont, {accumulate_role_queue_skip(acc, agent), progressed?}}

                {:ok, result} ->
                  {:cont, {accumulate_role_queue_result(acc, agent, result), true}}

                {:error, reason} ->
                  {:cont, {accumulate_role_queue_error(acc, agent, reason), progressed?}}
              end
            end
          end
        end)

      if progressed? do
        drain_role_queued_work(opts, updated_summary, limit, round + 1)
      else
        updated_summary
      end
    end
  end

  defp role_queue_dispatch_summary(owner) do
    %{
      owner: owner,
      processed_count: 0,
      pressure_skipped_count: 0,
      remote_owned_count: 0,
      skipped_count: 0,
      error_count: 0,
      rounds: 0,
      results: []
    }
  end

  defp stale_claim_cleanup_summary(owner) do
    %{
      owner: owner,
      expired_count: 0,
      skipped_count: 0,
      error_count: 0,
      results: []
    }
  end

  defp reassignment_summary(owner) do
    %{
      owner: owner,
      recovered_count: 0,
      executed_count: 0,
      queued_count: 0,
      skipped_count: 0,
      error_count: 0,
      results: []
    }
  end

  defp accumulate_stale_claim_cleanup(acc, %WorkItem{} = work_item) do
    entry = %{
      work_item_id: work_item.id,
      assigned_agent_id: work_item.assigned_agent_id,
      status: work_item.status,
      action: "expired_claim"
    }

    %{
      acc
      | expired_count: acc.expired_count + 1,
        results: [entry | acc.results]
    }
  end

  defp accumulate_stale_claim_cleanup_skip(acc, %WorkItem{} = work_item, reason) do
    entry = %{
      work_item_id: work_item.id,
      assigned_agent_id: work_item.assigned_agent_id,
      status: work_item.status,
      reason: to_string(reason)
    }

    %{
      acc
      | skipped_count: acc.skipped_count + 1,
        results: [entry | acc.results]
    }
  end

  defp accumulate_stale_claim_cleanup_error(acc, %WorkItem{} = work_item, reason) do
    entry = %{
      work_item_id: work_item.id,
      assigned_agent_id: work_item.assigned_agent_id,
      status: "error",
      error: inspect(reason)
    }

    %{
      acc
      | error_count: acc.error_count + 1,
        results: [entry | acc.results]
    }
  end

  defp accumulate_reassigned_work_item(acc, %WorkItem{} = work_item, result, action_override) do
    action = action_override

    entry = %{
      work_item_id: work_item.id,
      assigned_agent_id: work_item.assigned_agent_id,
      status: result.status,
      action: action,
      capacity_posture: result[:capacity_posture] || result["capacity_posture"],
      queue_reason: result[:queue_reason] || result["queue_reason"]
    }

    %{
      acc
      | recovered_count: acc.recovered_count + 1,
        executed_count: acc.executed_count + if(action == "reassigned_executed", do: 1, else: 0),
        queued_count: acc.queued_count + if(action == "reassigned_queued", do: 1, else: 0),
        results: [entry | acc.results]
    }
  end

  defp accumulate_reassignment_skip(acc, %WorkItem{} = work_item, reason) do
    entry = %{
      work_item_id: work_item.id,
      assigned_agent_id: work_item.assigned_agent_id,
      status: "skipped",
      reason: to_string(reason)
    }

    %{
      acc
      | skipped_count: acc.skipped_count + 1,
        results: [entry | acc.results]
    }
  end

  defp accumulate_reassignment_error(acc, %WorkItem{} = work_item, reason) do
    entry = %{
      work_item_id: work_item.id,
      assigned_agent_id: work_item.assigned_agent_id,
      status: "error",
      reason: inspect(reason)
    }

    %{
      acc
      | error_count: acc.error_count + 1,
        results: [entry | acc.results]
    }
  end

  defp recover_work_item_immediately?(pressure) when is_map(pressure) do
    case pressure do
      %{capacity_posture: "saturated"} -> false
      _ -> true
    end
  end

  defp worker_pressure_entry(agent_id) do
    all_work_items = list_work_items(limit: 500, preload: false)

    autonomy_agents =
      Agents.list_agents()
      |> Enum.filter(&(Map.get(capability_profile(&1), "max_autonomy_level") != "observe"))

    role_queue_backlog = build_role_queue_backlog(all_work_items, autonomy_agents)

    all_work_items
    |> build_worker_pressure(autonomy_agents, role_queue_backlog)
    |> Enum.find(&(&1.agent_id == agent_id))
  end

  defp queue_recovered_work_item(%WorkItem{} = work_item, %WorkItem{} = claimed) do
    queued_at = DateTime.utc_now()
    deferred_until = DateTime.add(queued_at, queued_recovery_delay_seconds(), :second)

    with {:ok, queued} <-
           save_work_item(work_item, %{
             "metadata" =>
               Map.put(
                 Helpers.normalize_string_keys(work_item.metadata || %{}),
                 "assignment_recovery",
                 %{
                   "queued_at" => queued_at,
                   "deferred_until" => deferred_until,
                   "queue_reason" => "worker_saturated"
                 }
               ),
             "runtime_state" =>
               append_history(work_item.runtime_state, work_item.status || "planned", %{
                 "queued_at" => queued_at,
                 "phase" => "assignment_recovery",
                 "reason" => "worker_saturated",
                 "deferred_until" => deferred_until
               })
           }),
         {:ok, released} <- release_claimed_work_item(queued, claimed) do
      {:ok, released}
    end
  end

  defp defer_role_queue_dispatch(%WorkItem{} = work_item, reason, attrs) do
    observed_at = DateTime.utc_now()
    attrs = Helpers.normalize_string_keys(attrs)

    deferred_until =
      case parse_datetime(attrs["lease_expires_at"]) do
        %DateTime{} = expires_at when reason == "claimed_remote" ->
          expires_at

        _ ->
          DateTime.add(observed_at, role_queue_dispatch_delay_seconds(), :second)
      end

    metadata =
      work_item.metadata
      |> Helpers.normalize_string_keys()
      |> Map.put(
        "role_queue_dispatch",
        %{
          "observed_at" => observed_at,
          "deferred_until" => deferred_until,
          "reason" => reason,
          "lease_owner" => attrs["lease_owner"],
          "lease_expires_at" =>
            parse_datetime(attrs["lease_expires_at"]) || attrs["lease_expires_at"],
          "capacity_posture" => attrs["capacity_posture"]
        }
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Map.new()
      )

    save_work_item(work_item, %{
      "metadata" => metadata,
      "runtime_state" =>
        append_history(work_item.runtime_state, work_item.status || "planned", %{
          "observed_at" => observed_at,
          "phase" => "role_queue_dispatch",
          "reason" => reason,
          "deferred_until" => deferred_until,
          "lease_owner" => attrs["lease_owner"],
          "lease_expires_at" => attrs["lease_expires_at"],
          "capacity_posture" => attrs["capacity_posture"]
        })
    })
  end

  defp queued_recovery_delay_seconds do
    max(div(Config.scheduler_poll_ms() * 2, 1000), 5)
  end

  defp role_queue_dispatch_delay_seconds do
    max(div(Config.scheduler_poll_ms() * 2, 1000), 5)
  end

  defp accumulate_role_queue_result(acc, %AgentProfile{} = agent, result) do
    work_item = result[:work_item]
    action = result[:action] || "processed"
    processed_increment = role_queue_processed_increment(result)

    entry = %{
      agent_id: agent.id,
      agent_name: agent.name,
      role: agent.role,
      work_item_id: work_item && work_item.id,
      status: result[:status] || "processed",
      action: action,
      lease_owner: result[:lease_owner],
      lease_expires_at: result[:lease_expires_at],
      deferred_until: result[:deferred_until]
    }

    %{
      acc
      | processed_count: acc.processed_count + processed_increment,
        remote_owned_count:
          acc.remote_owned_count + if(action == "claimed_remote", do: 1, else: 0),
        rounds: acc.rounds + 1,
        results: [entry | acc.results]
    }
  end

  defp accumulate_role_queue_skip(
         acc,
         %AgentProfile{} = agent,
         reason \\ "idle",
         pressure \\ %{},
         work_item \\ nil
       ) do
    dispatch = get_in((work_item && work_item.metadata) || %{}, ["role_queue_dispatch"]) || %{}

    %{
      acc
      | skipped_count: acc.skipped_count + 1,
        pressure_skipped_count:
          acc.pressure_skipped_count + if(reason == "worker_saturated", do: 1, else: 0),
        results: [
          %{
            agent_id: agent.id,
            agent_name: agent.name,
            role: agent.role,
            work_item_id: work_item && work_item.id,
            status: if(reason == "worker_saturated", do: "skipped", else: "idle"),
            action: if(reason == "worker_saturated", do: "worker_saturated", else: "idle"),
            reason: reason,
            capacity_posture: pressure[:capacity_posture] || pressure["capacity_posture"],
            deferred_until: dispatch["deferred_until"],
            lease_owner: dispatch["lease_owner"],
            lease_expires_at: dispatch["lease_expires_at"]
          }
          | acc.results
        ]
    }
  end

  defp accumulate_role_queue_error(acc, %AgentProfile{} = agent, reason) do
    %{
      acc
      | error_count: acc.error_count + 1,
        results: [
          %{
            agent_id: agent.id,
            agent_name: agent.name,
            role: agent.role,
            status: "error",
            reason: inspect(reason)
          }
          | acc.results
        ]
    }
  end

  defp role_queue_processed_increment(result) do
    count = result[:processed_count] || 0

    cond do
      count > 0 ->
        count

      (result[:action] || result["action"]) == "claimed_remote" ->
        0

      true ->
        1
    end
  end

  defp role_queue_dispatch_pass?(opts) when is_list(opts) do
    Keyword.get(opts, :scheduler_pass) == "role_queue_dispatch"
  end

  defp role_queue_dispatch_pass?(_opts), do: false

  defp resume_work_item_summary(owner) do
    %{
      owner: owner,
      resumed_count: 0,
      skipped_count: 0,
      error_count: 0,
      results: []
    }
  end

  defp accumulate_resumed_work_item(acc, %WorkItem{} = work_item, summary) do
    result = %{
      work_item_id: work_item.id,
      assigned_agent_id: work_item.assigned_agent_id,
      status: summary.status,
      action: summary[:action] || "replayed"
    }

    %{
      acc
      | resumed_count: acc.resumed_count + 1,
        results: [result | acc.results]
    }
  end

  defp accumulate_skipped_work_item(acc, %WorkItem{} = work_item, reason) do
    result = %{
      work_item_id: work_item.id,
      assigned_agent_id: work_item.assigned_agent_id,
      status: "skipped",
      reason: to_string(reason)
    }

    %{
      acc
      | skipped_count: acc.skipped_count + 1,
        results: [result | acc.results]
    }
  end

  defp accumulate_resume_work_item_error(acc, %WorkItem{} = work_item, reason) do
    result = %{
      work_item_id: work_item.id,
      assigned_agent_id: work_item.assigned_agent_id,
      status: "error",
      reason: inspect(reason)
    }

    %{
      acc
      | error_count: acc.error_count + 1,
        results: [result | acc.results]
    }
  end

  defp process_work_item(agent, %WorkItem{execution_mode: "delegate"} = work_item, _opts) do
    entries = delegation_batch_entries(work_item)
    concurrency = delegation_batch_concurrency(work_item, length(entries))

    seeded_metadata =
      seed_delegation_batch_metadata(work_item.metadata || %{}, entries, concurrency)

    seeded_work_item = %{work_item | metadata: seeded_metadata}

    delegated_children =
      seeded_work_item
      |> select_delegation_batch_entries_for_dispatch(entries, concurrency)
      |> Enum.map(&dispatch_delegated_batch_item(seeded_work_item, agent, &1))

    children = Enum.map(delegated_children, & &1.child)

    batch_snapshot =
      build_delegation_batch_snapshot(seeded_work_item, children, delegated_children)

    first_child = List.first(children)

    {:ok, plan_artifact} =
      create_artifact(%{
        "work_item_id" => work_item.id,
        "type" => "plan",
        "title" => delegation_plan_title(batch_snapshot),
        "summary" => delegation_plan_summary(work_item, batch_snapshot),
        "body" => delegation_plan_body(work_item, delegated_children, batch_snapshot),
        "payload" => %{
          "delegated_work_item_id" => first_child && first_child.id,
          "delegated_work_item_ids" => Enum.map(children, & &1.id),
          "assigned_role" => first_child && first_child.assigned_role,
          "assigned_roles" => batch_snapshot["roles"],
          "required_outputs" => work_item.required_outputs,
          "delegation_batch" => batch_snapshot,
          "delegated_work_items" =>
            Enum.map(delegated_children, fn entry ->
              %{
                "id" => entry.child.id,
                "kind" => entry.child.kind,
                "goal" => entry.child.goal,
                "assigned_role" => entry.child.assigned_role,
                "delegation_context" => entry.delegation_context
              }
            end)
        },
        "provenance" => %{"source" => "autonomy", "phase" => "delegate"},
        "confidence" => 0.78
      })

    {:ok, updated} =
      save_work_item(work_item, %{
        "status" => "blocked",
        "result_refs" => %{
          "artifact_ids" => [plan_artifact.id],
          "child_work_item_ids" => Enum.map(children, & &1.id)
        },
        "metadata" => Map.put(seeded_metadata, "delegation_batch", batch_snapshot),
        "runtime_state" =>
          append_history(work_item.runtime_state, "blocked", %{
            "blocked_at" => DateTime.utc_now(),
            "reason" => "delegated",
            "child_work_item_ids" => Enum.map(children, & &1.id)
          })
      })

    {:processed,
     %{
       status: "blocked",
       processed_count: 1,
       work_item: updated,
       artifacts: [plan_artifact],
       action: "delegated",
       delegated_work_item: first_child,
       delegated_work_items: children
     }}
  end

  defp process_work_item(agent, %WorkItem{kind: "research"} = work_item, _opts) do
    {:ok, running} =
      save_work_item(work_item, %{
        "status" => "running",
        "runtime_state" =>
          append_history(work_item.runtime_state, "running", %{
            "started_at" => DateTime.utc_now(),
            "phase" => "research"
          })
      })

    evidence = Memory.search_ranked(agent.id, running.goal, 5, status: "active")

    {:ok, plan_artifact} =
      create_artifact(%{
        "work_item_id" => running.id,
        "type" => "plan",
        "title" => "Research plan",
        "summary" => "Brief -> evidence -> synthesis",
        "body" => research_plan_body(running, evidence),
        "payload" => %{
          "question" => running.goal,
          "evidence_count" => length(evidence),
          "pipeline" => ["brief", "evidence_ranking", "synthesis", "delivery"]
        },
        "provenance" => %{"source" => "autonomy", "phase" => "research_plan"},
        "confidence" => 0.66
      })

    report_payload = build_research_report(agent, running, evidence)

    artifact_review_required = running.review_required || report_payload["degraded"] == true
    degraded_review_required = report_payload["degraded"] == true

    {:ok, report_artifact} =
      create_artifact(%{
        "work_item_id" => running.id,
        "type" => "research_report",
        "title" => "Research report",
        "summary" => List.first(report_payload["recommended_actions"]) || "Research complete",
        "body" => report_payload["body"],
        "payload" => Map.delete(report_payload, "body"),
        "provenance" => %{"source" => "autonomy", "phase" => "research_execution"},
        "confidence" => report_payload["confidence"],
        "review_status" => if(artifact_review_required, do: "proposed", else: "validated")
      })

    decision_payload = build_research_decision_ledger(running, report_payload)

    {:ok, decision_artifact} =
      create_artifact(%{
        "work_item_id" => running.id,
        "type" => "decision_ledger",
        "title" => "Research decision ledger",
        "summary" => decision_payload["summary"],
        "body" => decision_payload["body"],
        "payload" => Map.delete(decision_payload, "body"),
        "provenance" => %{"source" => "autonomy", "phase" => "research_decision_ledger"},
        "confidence" => report_payload["confidence"],
        "review_status" => if(artifact_review_required, do: "proposed", else: "validated")
      })

    if degraded_review_required do
      {:ok, review_item} =
        enqueue_review_work_item(running, %{
          "goal" => "Review research work item ##{running.id}: #{running.goal}",
          "requested_action" => "promote_research_findings",
          "change_artifact_id" => nil,
          "proposal_artifact_id" => plan_artifact.id,
          "report_artifact_id" => report_artifact.id,
          "decision_artifact_id" => decision_artifact.id
        })

      {:ok, blocked} =
        save_work_item(running, %{
          "status" => "blocked",
          "approval_stage" => "validated",
          "review_required" => true,
          "result_refs" => %{
            "artifact_ids" => [plan_artifact.id, report_artifact.id, decision_artifact.id],
            "child_work_item_ids" => [review_item.id],
            "degraded" => report_payload["degraded"] == true
          },
          "metadata" =>
            (running.metadata || %{})
            |> Map.put("degraded_execution", report_payload["degraded"] == true)
            |> maybe_put_constraint_strategy(report_payload["constraint_strategy"]),
          "runtime_state" =>
            append_history(running.runtime_state, "blocked", %{
              "blocked_at" => DateTime.utc_now(),
              "phase" => "review",
              "artifact_id" => report_artifact.id,
              "review_work_item_id" => review_item.id,
              "degraded" => report_payload["degraded"] == true
            })
        })

      {:processed,
       %{
         status: "blocked",
         processed_count: 1,
         work_item: blocked,
         artifacts: [plan_artifact, report_artifact, decision_artifact],
         action: "research_review_requested",
         delegated_work_item: review_item
       }}
    else
      if running.review_required do
        {:ok, completed} =
          save_work_item(running, %{
            "status" => "completed",
            "approval_stage" => "validated",
            "result_refs" => %{
              "artifact_ids" => [plan_artifact.id, report_artifact.id, decision_artifact.id],
              "degraded" => false
            },
            "metadata" => Map.put(running.metadata || %{}, "degraded_execution", false),
            "runtime_state" =>
              append_history(running.runtime_state, "completed", %{
                "completed_at" => DateTime.utc_now(),
                "phase" => "research",
                "artifact_id" => report_artifact.id
              })
          })

        {:processed,
         %{
           status: "completed",
           processed_count: 1,
           work_item: completed,
           artifacts: [plan_artifact, report_artifact, decision_artifact],
           action: "researched"
         }}
      else
        {:ok, record} =
          create_approval_record(%{
            "subject_type" => "work_item",
            "subject_id" => running.id,
            "requested_action" => "promote_research_findings",
            "decision" => "approved",
            "rationale" =>
              "Research findings were auto-approved because review was not required.",
            "work_item_id" => running.id,
            "reviewer_agent_id" => agent.id,
            "metadata" => %{"auto_approved" => true}
          })

        {:ok, completed} =
          save_work_item(running, %{
            "status" => "completed",
            "approval_stage" => "operator_approved",
            "result_refs" => %{
              "artifact_ids" => [plan_artifact.id, report_artifact.id, decision_artifact.id],
              "approval_record_ids" => [record.id],
              "degraded" => false
            },
            "metadata" => Map.put(running.metadata || %{}, "degraded_execution", false),
            "runtime_state" =>
              append_history(running.runtime_state, "completed", %{
                "completed_at" => DateTime.utc_now(),
                "phase" => "research",
                "artifact_id" => report_artifact.id,
                "approval_record_id" => record.id
              })
          })

        promote_artifacts!(completed, "promote_research_findings", record, %{
          "auto_approved" => true
        })

        promoted_memory_ids =
          promote_artifact_derived_outputs!(completed, [report_artifact, decision_artifact])

        {:ok, completed} =
          save_work_item(completed, %{
            "result_refs" =>
              completed.result_refs
              |> Map.put("promoted_memory_ids", promoted_memory_ids)
          })

        {:processed,
         %{
           status: "completed",
           processed_count: 1,
           work_item: completed,
           artifacts: [plan_artifact, report_artifact, decision_artifact],
           action: "researched"
         }}
      end
    end
  end

  defp process_work_item(agent, %WorkItem{kind: kind} = work_item, _opts)
       when kind in ["engineering", "extension"] do
    capability = capability_profile(agent)

    if not Autonomy.side_effect_allowed?(capability, side_effect_class_for_kind(kind)) do
      {:processed,
       %{
         status: "failed",
         processed_count: 0,
         action: "side_effect_blocked",
         error: {:capability_mismatch, kind}
       }}
    else
      do_engineering_work_item(agent, work_item)
    end
  end

  defp process_work_item(agent, %WorkItem{kind: "review"} = work_item, _opts) do
    do_review_work_item(agent, work_item)
  end

  defp process_work_item(agent, %WorkItem{kind: "task", metadata: metadata} = work_item, _opts)
       when is_map(metadata) do
    case metadata["task_type"] do
      "publish_summary" -> do_publish_summary_work_item(agent, work_item)
      _ -> process_generic_work_item(agent, work_item)
    end
  end

  defp process_work_item(agent, %WorkItem{} = work_item, _opts) do
    process_generic_work_item(agent, work_item)
  end

  defp process_generic_work_item(agent, %WorkItem{} = work_item) do
    summary = "Autonomy execution for #{work_item.kind} is not implemented yet."

    {:ok, artifact} =
      create_artifact(%{
        "work_item_id" => work_item.id,
        "type" => "note",
        "title" => "Execution note",
        "summary" => summary,
        "body" => summary,
        "payload" => %{"assigned_role" => agent.role, "kind" => work_item.kind},
        "provenance" => %{"source" => "autonomy", "phase" => "fallback"}
      })

    {:ok, updated} =
      save_work_item(work_item, %{
        "status" => "completed",
        "result_refs" => %{"artifact_ids" => [artifact.id]},
        "runtime_state" =>
          append_history(work_item.runtime_state, "completed", %{
            "completed_at" => DateTime.utc_now(),
            "phase" => "fallback"
          })
      })

    {:processed,
     %{
       status: "completed",
       processed_count: 1,
       work_item: updated,
       artifacts: [artifact],
       action: "completed_fallback"
     }}
  end

  defp finalize_claimed_summary({:processed, summary}, %WorkItem{} = claimed) do
    case release_claimed_work_item(summary[:work_item], claimed) do
      {:ok, %WorkItem{} = updated_work_item} ->
        {:processed, Map.put(summary, :work_item, updated_work_item)}

      _ ->
        {:processed, summary}
    end
  end

  defp finalize_claimed_summary(result, _claimed), do: result

  defp release_claimed_work_item(nil, _claimed), do: :ok

  defp release_claimed_work_item(%WorkItem{} = work_item, %WorkItem{} = claimed) do
    ownership =
      claimed.metadata
      |> get_in(["ownership"])
      |> case do
        map when is_map(map) -> map
        _ -> claimed_work_item_ownership(claimed.id, claimed.status || "claimed")
      end

    owner = ownership["owner"] || Coordination.status().owner

    _ = Coordination.release_lease(lease_name(claimed.id), owner: owner)

    updated_ownership =
      ownership
      |> Map.put("stage", work_item.status)
      |> Map.put("active", false)
      |> Map.put("released_at", DateTime.utc_now())

    save_work_item(work_item, %{
      "metadata" => put_work_item_ownership(work_item.metadata, updated_ownership)
    })
  end

  defp note_remote_work_item_ownership(%WorkItem{} = work_item, lease, stage) do
    ownership = remote_work_item_ownership(lease, stage)

    save_work_item(work_item, %{
      "metadata" => put_work_item_ownership(work_item.metadata, ownership)
    })
  end

  defp build_research_report(agent, work_item, evidence) do
    delegated_context = delegated_context_memories(work_item)
    degraded? = degraded_execution?(work_item)
    constraint_strategy = delegated_constraint_strategy(delegated_context)

    evidence_lines =
      evidence
      |> Enum.map(fn ranked ->
        source = source_label(ranked)
        score = Float.round(ranked.score, 2)
        "- [#{score}] #{ranked.entry.content}#{if(source, do: " (#{source})", else: "")}"
      end)

    delegated_context_lines =
      delegated_context
      |> Enum.map(fn memory ->
        score = memory["score"] || 0.0
        "- [#{Float.round(score, 2)}] #{memory["content"]} (delegated #{memory["type"]})"
      end)

    prompt =
      [
        "You are Hydra-X's research worker.",
        "Produce a concise structured research report.",
        "Question: #{work_item.goal}",
        "Return short claims, open questions, and recommended actions grounded in the evidence.",
        if(delegated_context_lines != [],
          do: "Delegated planning context:\n" <> Enum.join(delegated_context_lines, "\n")
        ),
        "Evidence:",
        Enum.join(evidence_lines, "\n")
      ]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join("\n\n")

    messages = [%{role: "user", content: prompt}]
    estimated_tokens = Budget.estimate_prompt_tokens(messages)

    llm_body =
      if token_budget_available?(agent, work_item, estimated_tokens) do
        case Budget.preflight(agent.id, nil, estimated_tokens) do
          {:ok, _result} ->
            case Router.complete(%{
                   messages: messages,
                   agent_id: agent.id,
                   process_type: "autonomy"
                 }) do
              {:ok, response} ->
                Budget.record_usage(agent.id, nil,
                  tokens_in: estimated_tokens,
                  tokens_out: Budget.estimate_tokens(response.content || ""),
                  metadata: %{
                    provider: response.provider,
                    purpose: "autonomy_research",
                    work_item_id: work_item.id
                  }
                )

                response.content || fallback_research_body(work_item, evidence)

              {:error, _reason} ->
                fallback_research_body(work_item, evidence)
            end

          {:error, _details} ->
            fallback_research_body(work_item, evidence)
        end
      else
        fallback_research_body(work_item, evidence)
      end

    %{
      "question" => work_item.goal,
      "scope" => work_item.metadata["scope"] || "autonomous research",
      "sources" => Enum.map(evidence, &source_snapshot/1),
      "evidence" => Enum.map(evidence, &evidence_snapshot/1),
      "planning_context" => delegated_context,
      "degraded" => degraded?,
      "constraint_strategy" => constraint_strategy,
      "claims" => derive_claims(evidence, delegated_context),
      "open_questions" => derive_open_questions(work_item, evidence, delegated_context),
      "recommended_actions" => derive_recommended_actions(work_item, evidence, delegated_context),
      "confidence" => adjusted_confidence(derive_confidence(evidence), degraded?),
      "body" => llm_body
    }
  end

  defp build_research_decision_ledger(_work_item, report_payload) do
    summary =
      List.first(report_payload["recommended_actions"]) ||
        "Promote approved findings into durable memory."

    body =
      """
      Research question: #{report_payload["question"]}
      Scope: #{report_payload["scope"]}

      Claims:
      #{Enum.map_join(report_payload["claims"], "\n", &"- #{&1}")}

      Recommended actions:
      #{Enum.map_join(report_payload["recommended_actions"], "\n", &"- #{&1}")}

      Delivery posture: #{if(report_payload["degraded"], do: "degraded", else: "standard")}
      Constraint strategy: #{report_payload["constraint_strategy"] || "none"}

      Open questions:
      #{Enum.map_join(report_payload["open_questions"], "\n", &"- #{&1}")}
      """
      |> String.trim()

    %{
      "summary" => summary,
      "body" => body,
      "question" => report_payload["question"],
      "scope" => report_payload["scope"],
      "claims" => report_payload["claims"],
      "recommended_actions" => report_payload["recommended_actions"],
      "open_questions" => report_payload["open_questions"],
      "confidence" => report_payload["confidence"],
      "memory_promotions" => artifact_memory_blueprints("decision_ledger", report_payload)
    }
  end

  defp do_engineering_work_item(agent, work_item) do
    {:ok, running} =
      save_work_item(work_item, %{
        "status" => "running",
        "runtime_state" =>
          append_history(work_item.runtime_state, "running", %{
            "started_at" => DateTime.utc_now(),
            "phase" => "engineering"
          })
      })

    workspace_snapshot = workspace_snapshot(agent.workspace_root, running.goal)
    proposal_payload = build_engineering_proposal(agent, running, workspace_snapshot)

    {:ok, proposal_artifact} =
      create_artifact(%{
        "work_item_id" => running.id,
        "type" => "proposal",
        "title" => "Engineering proposal",
        "summary" => proposal_payload["summary"],
        "body" => proposal_payload["body"],
        "payload" => Map.delete(proposal_payload, "body"),
        "provenance" => %{"source" => "autonomy", "phase" => "engineering_proposal"},
        "confidence" => proposal_payload["confidence"],
        "review_status" => "proposed"
      })

    change_set_payload = build_code_change_set(running, workspace_snapshot, proposal_payload)

    {:ok, change_artifact} =
      create_artifact(%{
        "work_item_id" => running.id,
        "type" => if(running.kind == "extension", do: "patch_bundle", else: "code_change_set"),
        "title" =>
          if(running.kind == "extension", do: "Extension patch bundle", else: "Code change set"),
        "summary" => change_set_payload["summary"],
        "body" => change_set_payload["body"],
        "payload" => Map.delete(change_set_payload, "body"),
        "provenance" => %{"source" => "autonomy", "phase" => "engineering_patch"},
        "confidence" => 0.69,
        "review_status" => if(running.review_required, do: "proposed", else: "validated")
      })

    if running.review_required do
      requested_action =
        if running.kind == "extension", do: "enable_extension", else: "promote_code_change"

      {:ok, review_item} =
        enqueue_review_work_item(running, %{
          "goal" => "Review #{running.kind} work item ##{running.id}: #{running.goal}",
          "approval_stage" => "patch_ready",
          "requested_action" => requested_action,
          "change_artifact_id" => change_artifact.id,
          "proposal_artifact_id" => proposal_artifact.id
        })

      {:ok, updated} =
        save_work_item(running, %{
          "status" => "blocked",
          "approval_stage" => "patch_ready",
          "result_refs" => %{
            "artifact_ids" => [proposal_artifact.id, change_artifact.id],
            "child_work_item_ids" => [review_item.id]
          },
          "runtime_state" =>
            append_history(running.runtime_state, "blocked", %{
              "blocked_at" => DateTime.utc_now(),
              "phase" => "review",
              "review_work_item_id" => review_item.id
            })
        })

      {:processed,
       %{
         status: "blocked",
         processed_count: 1,
         work_item: updated,
         artifacts: [proposal_artifact, change_artifact],
         action: "engineering_review_requested",
         delegated_work_item: review_item
       }}
    else
      {:ok, record} =
        create_approval_record(%{
          "subject_type" => "work_item",
          "subject_id" => running.id,
          "requested_action" => "promote_code_change",
          "decision" => "approved",
          "rationale" => "Review was not required for this engineering work item.",
          "work_item_id" => running.id,
          "reviewer_agent_id" => agent.id,
          "metadata" => %{"auto_approved" => true}
        })

      {:ok, updated} =
        save_work_item(running, %{
          "status" => "completed",
          "approval_stage" => "validated",
          "result_refs" => %{
            "artifact_ids" => [proposal_artifact.id, change_artifact.id],
            "approval_record_ids" => [record.id]
          },
          "runtime_state" =>
            append_history(running.runtime_state, "completed", %{
              "completed_at" => DateTime.utc_now(),
              "phase" => "engineering",
              "approval_record_id" => record.id
            })
        })

      promote_artifacts!(updated, "validate_artifact", record, %{"auto_approved" => true})

      {:processed,
       %{
         status: "completed",
         processed_count: 1,
         work_item: updated,
         artifacts: [proposal_artifact, change_artifact],
         action: "engineering_completed"
       }}
    end
  end

  defp do_publish_summary_work_item(agent, work_item) do
    summary_artifact_id = get_in(work_item.metadata || %{}, ["summary_artifact_id"])

    summary_artifact =
      if is_integer(summary_artifact_id) do
        get_artifact!(summary_artifact_id)
      end

    follow_up_context =
      get_in(work_item.metadata || %{}, ["follow_up_context", "promoted_findings"]) || []

    delivery = get_in(work_item.metadata || %{}, ["delivery"]) || %{}

    {:ok, running} =
      save_work_item(work_item, %{
        "status" => "running",
        "runtime_state" =>
          append_history(work_item.runtime_state, "running", %{
            "started_at" => DateTime.utc_now(),
            "phase" => "publish_summary"
          })
      })

    payload = build_delivery_brief(agent, running, summary_artifact, follow_up_context, delivery)
    delivery_result = maybe_deliver_publish_summary(agent, running, payload)

    {:ok, artifact} =
      create_artifact(%{
        "work_item_id" => running.id,
        "type" => "delivery_brief",
        "title" => "Publish-ready summary",
        "summary" => payload["summary"],
        "body" => payload["body"],
        "payload" => Map.delete(payload, "body") |> Map.put("delivery", delivery_result),
        "provenance" => %{"source" => "autonomy", "phase" => "publish_summary"},
        "confidence" => payload["confidence"],
        "review_status" => if(payload["degraded"], do: "proposed", else: "validated")
      })

    action =
      case delivery_result["status"] do
        "delivered" -> "delivered_publish_summary"
        _ -> "prepared_delivery_brief"
      end

    {:ok, completed} =
      save_work_item(running, %{
        "status" => "completed",
        "approval_stage" =>
          if(payload["degraded"], do: "validated", else: running.approval_stage),
        "result_refs" => %{
          "artifact_ids" => [artifact.id],
          "delivery" => delivery_result,
          "degraded" => payload["degraded"] == true
        },
        "metadata" =>
          (running.metadata || %{})
          |> Map.put("degraded_execution", payload["degraded"] == true)
          |> maybe_put_constraint_strategy(payload["constraint_strategy"]),
        "runtime_state" =>
          append_history(running.runtime_state, "completed", %{
            "completed_at" => DateTime.utc_now(),
            "phase" => "publish_summary",
            "artifact_id" => artifact.id,
            "delivery_status" => delivery_result["status"],
            "degraded" => payload["degraded"] == true
          })
      })

    {:ok, completed, publish_review_item} =
      maybe_enqueue_publish_review_follow_up(completed, artifact, delivery, payload)

    {:processed,
     %{
       status: "completed",
       processed_count: 1,
       work_item: completed,
       artifacts: [artifact],
       action: action,
       follow_up_work_item: publish_review_item
     }}
  end

  defp do_review_work_item(agent, work_item) do
    target_id = work_item.metadata["review_target_work_item_id"]
    target = if is_integer(target_id), do: get_work_item!(target_id), else: nil

    source_artifact =
      review_source_artifact(target, work_item.metadata || %{})

    review_payload = build_review_report(work_item, target, source_artifact)
    decision = review_payload["decision"]
    decision_payload = build_review_decision_ledger(work_item, target, review_payload)

    {:ok, review_artifact} =
      create_artifact(%{
        "work_item_id" => work_item.id,
        "type" => "review_report",
        "title" => "Review report",
        "summary" => review_payload["summary"],
        "body" => review_payload["body"],
        "payload" => Map.delete(review_payload, "body"),
        "provenance" => %{"source" => "autonomy", "phase" => "review"},
        "confidence" => review_payload["confidence"],
        "review_status" => if(decision == "approved", do: "approved", else: "rejected")
      })

    {:ok, decision_artifact} =
      create_artifact(%{
        "work_item_id" => work_item.id,
        "type" => "decision_ledger",
        "title" => "Review decision ledger",
        "summary" => decision_payload["summary"],
        "body" => decision_payload["body"],
        "payload" => Map.delete(decision_payload, "body"),
        "provenance" => %{"source" => "autonomy", "phase" => "review_decision_ledger"},
        "confidence" => decision_payload["confidence"],
        "review_status" => if(decision == "approved", do: "approved", else: "rejected")
      })

    {:ok, approval_record} =
      create_approval_record(%{
        "subject_type" => "work_item",
        "subject_id" => target && target.id,
        "requested_action" => work_item.metadata["requested_action"] || "promote_work_item",
        "decision" => decision,
        "rationale" => review_payload["summary"],
        "work_item_id" => work_item.id,
        "reviewer_agent_id" => agent.id,
        "metadata" => %{
          "review_artifact_id" => review_artifact.id,
          "target_kind" => target && target.kind
        }
      })

    if source_artifact do
      record_artifact_decision!(
        source_artifact,
        work_item.metadata["requested_action"] || "promote_work_item",
        decision,
        review_payload["summary"],
        %{
          "review_artifact_id" => review_artifact.id,
          "review_work_item_id" => work_item.id,
          "target_work_item_id" => target && target.id
        },
        agent.id,
        work_item.id
      )
    end

    {:ok, updated} =
      save_work_item(work_item, %{
        "status" => "completed",
        "approval_stage" => if(decision == "approved", do: "validated", else: "proposal_only"),
        "result_refs" => %{
          "artifact_ids" => [review_artifact.id, decision_artifact.id],
          "approval_record_ids" => [approval_record.id]
        },
        "metadata" =>
          (work_item.metadata || %{})
          |> Map.put("processor_agent_id", agent.id)
          |> Map.put("reviewer_agent_id", agent.id),
        "runtime_state" =>
          append_history(work_item.runtime_state, "completed", %{
            "completed_at" => DateTime.utc_now(),
            "phase" => "review",
            "approval_record_id" => approval_record.id
          })
      })

    updated =
      if decision == "approved" do
        promoted_memory_ids =
          promote_artifact_derived_outputs!(updated, [review_artifact, decision_artifact])

        if promoted_memory_ids == [] do
          updated
        else
          {:ok, promoted} =
            save_work_item(updated, %{
              "result_refs" =>
                (updated.result_refs || %{})
                |> Map.put("promoted_memory_ids", promoted_memory_ids)
            })

          promoted
        end
      else
        updated
      end

    {:processed,
     %{
       status: "completed",
       processed_count: 1,
       work_item: updated,
       artifacts: [review_artifact, decision_artifact],
       action: "review_completed"
     }}
  end

  defp fallback_research_body(work_item, evidence) do
    delegated_context = delegated_context_memories(work_item)

    """
    Research question: #{work_item.goal}

    Delegated context:
    #{Enum.map_join(delegated_context, "\n", fn memory -> "- #{memory["type"]}: #{memory["content"]}" end)}

    Evidence summary:
    #{Enum.map_join(evidence, "\n", fn ranked -> "- #{ranked.entry.content}" end)}
    """
    |> String.trim()
  end

  defp build_engineering_proposal(agent, work_item, workspace_snapshot) do
    focus_files =
      workspace_snapshot["candidate_files"]
      |> Enum.take(4)
      |> Enum.join(", ")

    delegated_context = delegated_context_memories(work_item)

    delegated_context_block =
      delegated_context
      |> Enum.map_join("\n", fn memory -> "- #{memory["type"]}: #{memory["content"]}" end)

    prompt =
      [
        "You are Hydra-X's builder agent.",
        "Create a concise engineering proposal.",
        "Goal: #{work_item.goal}",
        "Role: #{agent.role}",
        "Workspace focus: #{focus_files}",
        if(delegated_context_block != "",
          do: "Delegated planning context:\n" <> delegated_context_block
        ),
        "Respond with a short proposal that includes likely changes, validation, risks, and rollback notes."
      ]
      |> Enum.join("\n\n")

    body =
      llm_body_for(agent, work_item, prompt, "autonomy_engineering") ||
        """
        Goal: #{work_item.goal}
        Delegated context: #{if(delegated_context_block == "", do: "none", else: delegated_context_block)}
        Likely changes: focus on #{focus_files}.
        Validation: run #{Enum.join(default_test_commands(work_item), ", ")}.
        Risks: validate policy drift and regression scope.
        Rollback: revert the scoped patch and restore prior config or code paths.
        """
        |> String.trim()

    %{
      "summary" => "Proposed #{work_item.kind} work for #{workspace_snapshot["workspace_root"]}",
      "body" => body,
      "repo_scope" => workspace_snapshot["workspace_root"],
      "candidate_files" => workspace_snapshot["candidate_files"],
      "validation_commands" => default_test_commands(work_item),
      "risks" => engineering_risks(work_item, workspace_snapshot),
      "rollback_notes" => engineering_rollback_notes(work_item),
      "confidence" => 0.63
    }
  end

  defp build_code_change_set(work_item, workspace_snapshot, proposal_payload) do
    changed_files =
      workspace_snapshot["candidate_files"]
      |> Enum.take(5)

    base_payload = %{
      "summary" => "Prepared #{length(changed_files)} candidate files for #{work_item.kind}",
      "body" =>
        """
        Repo scope: #{workspace_snapshot["workspace_root"]}
        Candidate files: #{Enum.join(changed_files, ", ")}
        Validation commands: #{Enum.join(default_test_commands(work_item), ", ")}
        Risks: #{Enum.join(proposal_payload["risks"], "; ")}
        Rollback: #{proposal_payload["rollback_notes"]}
        """
        |> String.trim(),
      "repo_scope" => workspace_snapshot["workspace_root"],
      "changed_files" => changed_files,
      "test_commands" => default_test_commands(work_item),
      "test_results" =>
        Enum.map(default_test_commands(work_item), fn command ->
          %{"command" => command, "status" => "pending"}
        end),
      "risks" => proposal_payload["risks"],
      "rollback_notes" => proposal_payload["rollback_notes"],
      "promotion_stage" => "patch_ready"
    }

    if work_item.kind == "extension" do
      Map.merge(
        base_payload,
        extension_package_payload(work_item, workspace_snapshot, changed_files)
      )
    else
      base_payload
    end
  end

  defp build_review_report(work_item, target, source_artifact) do
    source_payload = (source_artifact && source_artifact.payload) || %{}
    changed_files = List.wrap(source_payload["changed_files"])
    test_commands = List.wrap(source_payload["test_commands"])
    requested_action = work_item.metadata["requested_action"] || "promote_work_item"
    delegated_context = delegated_context_memories(target || work_item)
    delegated_context_block = render_delegated_context_block(delegated_context)

    inherited_delivery_decisions =
      merge_supporting_findings(
        List.wrap(get_in(target.metadata || %{}, ["follow_up_context", "delivery_decisions"])) ++
          List.wrap(
            get_in(work_item.metadata || %{}, ["follow_up_context", "delivery_decisions"])
          )
      )

    delivery_decisions =
      merge_supporting_findings(
        delivery_decision_memories(delegated_context) ++ inherited_delivery_decisions
      )

    decision_snapshot =
      build_delivery_decision_snapshot(delivery_decisions, inherited_delivery_decisions,
        decision_basis: "review_context",
        decision_scope: "review"
      )

    delivery_decision_block =
      delivery_decisions
      |> Enum.map_join("\n", fn memory ->
        "- #{memory["content"]}"
      end)

    findings =
      review_findings(
        changed_files,
        test_commands,
        target && target.kind,
        source_payload,
        source_artifact
      )

    decision = if(findings == [], do: "approved", else: "rejected")

    review_scope =
      case target && target.kind do
        kind when kind in ["engineering", "extension"] ->
          "#{length(changed_files)} candidate files"

        "research" ->
          "1 structured research report"

        _ ->
          "the available autonomy payload"
      end

    %{
      "summary" =>
        if(
          decision == "approved",
          do: "Validated #{requested_action} across #{review_scope}",
          else:
            "Rejected review because the supporting #{(target && target.kind) || "work"} artifacts were incomplete"
        ),
      "body" =>
        """
        Target work item: ##{target && target.id}
        Decision: #{decision}
        Candidate files: #{if(changed_files == [], do: "none", else: Enum.join(changed_files, ", "))}
        Validation commands: #{if(test_commands == [], do: "none", else: Enum.join(test_commands, ", "))}
        Source artifact: #{source_artifact && "#{source_artifact.type} ##{source_artifact.id}"}
        Delegated context: #{if(delegated_context_block == "", do: "none", else: delegated_context_block)}
        Delivery decision context: #{if(delivery_decision_block == "", do: "none", else: "\n" <> delivery_decision_block)}
        Delivery decision comparison: #{decision_snapshot["comparison_summary"] || "none"}
        """
        |> String.trim(),
      "decision" => decision,
      "findings" => findings,
      "target_goal" => target && target.goal,
      "delegated_context" => delegated_context,
      "delivery_decision_context" => delivery_decisions,
      "delivery_decision_snapshot" => decision_snapshot,
      "recommended_actions" =>
        review_recommended_actions(decision, target && target.kind, delegated_context),
      "memory_origin_role" => "reviewer",
      "scope" => "autonomous review",
      "confidence" => if(decision == "approved", do: 0.74, else: 0.41)
    }
  end

  defp enqueue_review_work_item(%WorkItem{} = target, attrs) when is_map(attrs) do
    attrs = Helpers.normalize_string_keys(attrs)

    save_work_item(%{
      "kind" => "review",
      "goal" => attrs["goal"] || "Review work item ##{target.id}: #{target.goal}",
      "status" => "planned",
      "execution_mode" => "review",
      "assigned_role" => "reviewer",
      "parent_work_item_id" => target.id,
      "priority" => max(target.priority, 1),
      "autonomy_level" => "execute_with_review",
      "approval_stage" => attrs["approval_stage"] || target.approval_stage,
      "required_outputs" => %{"artifact_types" => ["review_report"]},
      "metadata" => %{
        "review_target_work_item_id" => target.id,
        "change_artifact_id" => attrs["change_artifact_id"],
        "proposal_artifact_id" => attrs["proposal_artifact_id"],
        "report_artifact_id" => attrs["report_artifact_id"],
        "decision_artifact_id" => attrs["decision_artifact_id"],
        "requested_action" => attrs["requested_action"] || "promote_work_item",
        "delegation_context" => get_in(target.metadata || %{}, ["delegation_context"])
      }
    })
  end

  defp review_source_artifact(nil, _metadata), do: nil

  defp review_source_artifact(%WorkItem{} = target, metadata) when is_map(metadata) do
    artifact_id =
      case target.kind do
        kind when kind in ["engineering", "extension"] -> metadata["change_artifact_id"]
        "research" -> metadata["report_artifact_id"]
        _ -> metadata["report_artifact_id"] || metadata["change_artifact_id"]
      end

    if is_integer(artifact_id) do
      list_artifacts(work_item_id: target.id, limit: 20)
      |> Enum.find(&(&1.id == artifact_id))
    end
  end

  defp build_review_decision_ledger(_work_item, target, review_payload) do
    delegated_context = review_payload["delegated_context"] || []
    delivery_decision_context = review_payload["delivery_decision_context"] || []
    delivery_decision_snapshot = review_payload["delivery_decision_snapshot"] || %{}

    %{
      "summary" => review_payload["summary"],
      "body" =>
        """
        Review target: #{target && target.goal}
        Decision: #{review_payload["decision"]}
        Findings:
        #{Enum.map_join(review_payload["findings"] || [], "\n", &"- #{&1}")}

        Recommended actions:
        #{Enum.map_join(review_payload["recommended_actions"] || [], "\n", &"- #{&1}")}

        Delivery decisions considered:
        #{Enum.map_join(delivery_decision_context, "\n", fn memory -> "- #{memory["content"]}" end)}

        Delivery decision comparison:
        #{delivery_decision_snapshot["comparison_summary"] || "none"}

        Delegated context:
        #{Enum.map_join(delegated_context, "\n", fn memory -> "- #{memory["type"]}: #{memory["content"]}" end)}
        """
        |> String.trim(),
      "decision_type" => "review",
      "decision" => review_payload["decision"],
      "target_goal" => target && target.goal,
      "summary_source" => "review",
      "recommended_actions" => review_payload["recommended_actions"] || [],
      "open_questions" => [],
      "delivery_decision_context" => delivery_decision_context,
      "delivery_decision_snapshot" => delivery_decision_snapshot,
      "claims" =>
        (delivery_decision_context ++ delegated_context)
        |> Enum.take(2)
        |> Enum.map(& &1["content"]),
      "confidence" => review_payload["confidence"],
      "memory_origin_role" => "reviewer",
      "scope" => "autonomous review"
    }
  end

  defp build_delivery_brief(agent, work_item, summary_artifact, follow_up_context, delivery) do
    summary_payload = (summary_artifact && summary_artifact.payload) || %{}
    follow_up_metadata = get_in(work_item.metadata || %{}, ["follow_up_context"]) || %{}
    findings = Enum.take(follow_up_context, 4)
    degraded? = degraded_delivery_brief?(follow_up_metadata, summary_payload, findings)

    delivery_recovery =
      follow_up_metadata["delivery_recovery"] ||
        summary_payload["delivery_recovery"] ||
        get_in(work_item.metadata || %{}, ["delivery_recovery"]) ||
        %{}

    effective_delivery = resolved_delivery_config(delivery, delivery_recovery)
    delivery_mode = effective_delivery["mode"] || "report"
    delivery_channel = effective_delivery["channel"]
    delivery_target = effective_delivery["target"]

    publish_objective =
      delivery_recovery_objective(
        work_item,
        delivery_recovery,
        delivery_mode,
        delivery_channel,
        delivery_target
      )

    delivery_heading = delivery_recovery_heading(delivery_recovery)

    decision_confidence =
      delivery_decision_confidence(delivery_recovery, summary_payload, summary_artifact)

    confidence_posture = delivery_confidence_posture(decision_confidence, degraded?)

    delivery_destination =
      delivery_destination_label(delivery_mode, delivery_channel, delivery_target)

    destination_rationale =
      delivery_destination_rationale(
        delivery_recovery,
        decision_confidence,
        confidence_posture,
        delivery_destination
      )

    prior_delivery_decisions =
      merge_supporting_findings(
        delivery_decision_memories(findings) ++
          List.wrap(follow_up_metadata["delivery_decisions"])
      )

    current_delivery_decisions =
      merge_supporting_findings([
        %{
          "type" => "DeliveryDecision",
          "content" => destination_rationale,
          "source_artifact_type" => "delivery_brief"
        },
        %{
          "type" => "DeliveryDecision",
          "content" => publish_objective,
          "source_artifact_type" => "delivery_brief"
        }
      ])

    delivery_decision_snapshot =
      build_delivery_decision_snapshot(current_delivery_decisions, prior_delivery_decisions,
        decision_basis: delivery_recovery["decision_basis"] || "publish_delivery",
        decision_scope: "publish"
      )
      |> maybe_put_publish_prior_summary(delivery_recovery, delivery)

    constraint_strategy =
      follow_up_metadata["constraint_strategy"] ||
        summary_payload["constraint_strategy"] ||
        delegated_constraint_strategy(findings)

    publish_lines =
      findings
      |> Enum.map(fn finding ->
        "- #{finding["type"]}: #{finding["content"]}"
      end)

    llm_body =
      llm_body_for(
        agent,
        work_item,
        """
        You are Hydra-X's operator preparing a publish-ready summary.

        Goal: #{work_item.goal}
        Delivery mode: #{delivery_mode}
        Delivery channel: #{delivery_channel || "report"}
        Delivery target: #{delivery_target || "control plane"}
        Delivery posture: #{if(degraded?, do: "degraded", else: "standard")}
        Delivery recovery: #{delivery_recovery["strategy"] || "none"}
        Delivery destination: #{delivery_destination}
        Delivery confidence: #{Float.round(decision_confidence, 2)} (#{confidence_posture})
        Destination rationale: #{destination_rationale}
        Constraint strategy: #{constraint_strategy || "none"}
        Delivery objective: #{publish_objective}

        Summary artifact:
        #{(summary_artifact && summary_artifact.body) || work_item.goal}

        Follow-up findings:
        #{Enum.join(publish_lines, "\n")}
        """,
        "autonomy_delivery_brief"
      )

    body =
      llm_body ||
        """
        Publish goal: #{work_item.goal}
        Delivery mode: #{delivery_mode}
        Delivery channel: #{delivery_channel || "report"}
        Delivery target: #{delivery_target || "control plane"}
        Delivery posture: #{if(degraded?, do: "degraded", else: "standard")}
        Delivery recovery: #{delivery_recovery["strategy"] || "none"}
        Delivery destination: #{delivery_destination}
        Delivery confidence: #{Float.round(decision_confidence, 2)} (#{confidence_posture})
        Destination rationale: #{destination_rationale}
        Constraint strategy: #{constraint_strategy || "none"}
        Delivery objective: #{publish_objective}

        #{delivery_heading}:
        #{(summary_artifact && summary_artifact.body) || work_item.goal}

        Key findings to preserve:
        #{if(publish_lines == [], do: "- none", else: Enum.join(publish_lines, "\n"))}
        """
        |> String.trim()

    %{
      "summary" =>
        "Prepared #{if(degraded?, do: "degraded ", else: "")}#{delivery_mode} delivery brief for #{delivery_channel || "report"} publication",
      "body" => body,
      "delivery_mode" => delivery_mode,
      "delivery_channel" => delivery_channel,
      "delivery_target" => delivery_target,
      "degraded" => degraded?,
      "publish_objective" => publish_objective,
      "delivery_heading" => delivery_heading,
      "delivery_destination" => delivery_destination,
      "destination_rationale" => destination_rationale,
      "decision_confidence" => decision_confidence,
      "confidence_posture" => confidence_posture,
      "delivery_decision_snapshot" => delivery_decision_snapshot,
      "constraint_strategy" => constraint_strategy,
      "delivery_recovery" => delivery_recovery,
      "delivery" => %{
        "enabled" => Map.get(delivery, "enabled", false),
        "mode" => delivery_mode,
        "channel" => delivery_channel,
        "target" => delivery_target
      },
      "summary_artifact_id" => summary_artifact && summary_artifact.id,
      "source_work_item_id" => work_item.parent_work_item_id,
      "key_findings" => findings,
      "recommended_actions" =>
        [
          delivery_recovery["recommended_action"],
          delivery_recovery_guidance(delivery_recovery, degraded?),
          confidence_posture_guidance(confidence_posture, degraded?),
          delivery_target &&
            "Deliver to #{delivery_target} via #{delivery_channel || delivery_mode} once the chosen recovery path is approved."
        ]
        |> Enum.reject(&(&1 in [nil, ""])),
      "confidence" =>
        adjusted_confidence(
          summary_payload["confidence"] || (summary_artifact && summary_artifact.confidence) ||
            0.68,
          degraded?
        )
    }
  end

  defp delivery_decision_confidence(delivery_recovery, summary_payload, summary_artifact) do
    cond do
      is_float(delivery_recovery["decision_confidence"]) ->
        delivery_recovery["decision_confidence"]

      is_integer(delivery_recovery["decision_confidence"]) ->
        delivery_recovery["decision_confidence"] * 1.0

      is_float(summary_payload["confidence"]) ->
        summary_payload["confidence"]

      is_integer(summary_payload["confidence"]) ->
        summary_payload["confidence"] * 1.0

      match?(%Artifact{}, summary_artifact) and is_float(summary_artifact.confidence) ->
        summary_artifact.confidence

      match?(%Artifact{}, summary_artifact) and is_integer(summary_artifact.confidence) ->
        summary_artifact.confidence * 1.0

      true ->
        0.68
    end
    |> Float.round(3)
  end

  defp delivery_confidence_posture(confidence, degraded?) when confidence < 0.6 or degraded?,
    do: "requires_review"

  defp delivery_confidence_posture(confidence, _degraded?) when confidence < 0.75,
    do: "cautious"

  defp delivery_confidence_posture(_confidence, _degraded?), do: "ready"

  defp delivery_destination_label("channel", channel, target)
       when is_binary(channel) and channel != "" do
    if present_text?(target), do: "#{channel} -> #{target}", else: channel
  end

  defp delivery_destination_label(mode, _channel, target) when is_binary(mode) do
    if present_text?(target), do: "#{mode} -> #{target}", else: mode
  end

  defp delivery_destination_label(_mode, _channel, target) do
    target || "report"
  end

  defp delivery_destination_rationale(
         delivery_recovery,
         decision_confidence,
         confidence_posture,
         destination
       ) do
    basis =
      case delivery_recovery["decision_basis"] do
        "explicit_channel_signal" -> "explicit channel signal"
        "low_confidence" -> "low confidence safeguard"
        "revised_confident_summary" -> "revised confident summary"
        nil -> "current publish policy"
        value -> String.replace(value, "_", " ")
      end

    strategy_note =
      case delivery_recovery["strategy"] do
        "switch_delivery_channel" -> "rerouted delivery"
        "internal_report_fallback" -> "internal-only fallback"
        "revise_and_retry_channel" -> "revised retry path"
        _ -> "default delivery path"
      end

    "Selected #{destination} using #{basis} (#{strategy_note}) at confidence #{Float.round(decision_confidence, 2)} with #{confidence_posture} posture."
  end

  defp confidence_posture_guidance("requires_review", true),
    do: "Keep the degraded brief under explicit operator review before any external delivery."

  defp confidence_posture_guidance("requires_review", _degraded?),
    do: "Keep this brief under explicit operator review before any delivery attempt."

  defp confidence_posture_guidance("cautious", _degraded?),
    do: "Use a cautious review pass and confirm the destination rationale before publishing."

  defp confidence_posture_guidance("ready", _degraded?),
    do:
      "The delivery path is ready for the next approval step with the current destination rationale."

  defp delivery_recovery_objective(
         work_item,
         delivery_recovery,
         delivery_mode,
         delivery_channel,
         delivery_target
       ) do
    cond do
      delivery_recovery["strategy"] == "switch_delivery_channel" and
          present_text?(delivery_channel) ->
        "Revise the summary and route it through #{delivery_channel}#{publish_target_suffix(delivery_target)}."

      delivery_recovery["strategy"] == "internal_report_fallback" ->
        "Prepare an internal operator report#{publish_target_suffix(delivery_target || "control-plane")} until external delivery is safe again."

      delivery_recovery["strategy"] == "revise_and_retry_channel" and
          present_text?(delivery_channel) ->
        "Revise the summary and retry delivery through #{delivery_channel}#{publish_target_suffix(delivery_target)}."

      present_text?(delivery_channel) ->
        "Publish the finalized summary through #{delivery_channel}#{publish_target_suffix(delivery_target)}."

      true ->
        "Prepare the next #{delivery_mode} delivery for #{work_item.goal}."
    end
  end

  defp delivery_recovery_heading(delivery_recovery) do
    case delivery_recovery["strategy"] do
      "switch_delivery_channel" -> "Revised summary for rerouted delivery"
      "internal_report_fallback" -> "Internal operator report"
      "revise_and_retry_channel" -> "Revised summary for retry delivery"
      _ -> "Summary ready for publication"
    end
  end

  defp delivery_recovery_guidance(delivery_recovery, degraded?) do
    case delivery_recovery["strategy"] do
      "switch_delivery_channel" ->
        "Confirm the rerouted delivery target before external publication."

      "internal_report_fallback" ->
        "Keep this brief on the control plane until stronger evidence and explicit approval restore external delivery."

      "revise_and_retry_channel" ->
        if degraded? do
          "Review the degraded retry brief before another external delivery attempt."
        else
          "Review the revised retry brief before external delivery."
        end

      _ ->
        if degraded? do
          "Review the degraded publish-ready summary before any external delivery."
        else
          "Review the publish-ready summary before external delivery."
        end
    end
  end

  defp maybe_deliver_publish_summary(agent, work_item, payload) do
    delivery = payload["delivery"] || %{}
    enabled? = Map.get(delivery, "enabled", false)
    channel = delivery["channel"]
    target = delivery["target"]
    delivery_recovery = payload["delivery_recovery"] || %{}

    result =
      cond do
        enabled? != true ->
          %{"status" => "draft", "degraded" => payload["degraded"] == true}

        internal_report_recovery?(delivery_recovery) ->
          %{
            "status" => "skipped",
            "mode" => "report",
            "target" => delivery_recovery["recommended_target"] || "control-plane",
            "degraded" => payload["degraded"] == true,
            "reason" => "internal_report_recovery"
          }

        payload["degraded"] == true ->
          %{
            "status" => "draft",
            "channel" => channel,
            "target" => target,
            "degraded" => true,
            "reason" => "degraded_confidence_requires_review"
          }

        not (is_binary(channel) and channel != "") ->
          %{"status" => "skipped", "reason" => "missing_delivery_channel"}

        not (is_binary(target) and target != "") ->
          %{"status" => "skipped", "reason" => "missing_delivery_target", "channel" => channel}

        true ->
          execute_publish_delivery(agent, channel, target, payload["body"])
      end
      |> maybe_put_delivery_recovery_result(delivery_recovery)

    maybe_record_work_item_budget_usage(agent, work_item, "autonomy_delivery", 0, 0)
    result
  end

  defp maybe_enqueue_publish_review_follow_up(
         %WorkItem{} = publish_item,
         %Artifact{} = delivery_brief,
         delivery,
         payload
       ) do
    review_delivery = payload["delivery"] || delivery || %{}
    delivery_recovery = payload["delivery_recovery"] || %{}

    cond do
      payload["degraded"] != true ->
        {:ok, publish_item, nil}

      Map.get(review_delivery || %{}, "enabled", false) != true ->
        {:ok, publish_item, nil}

      internal_report_recovery?(delivery_recovery) ->
        {:ok, publish_item, nil}

      true ->
        {:ok, review_item} =
          ensure_follow_up_work_item(
            publish_item,
            "publish_approval",
            fn item ->
              get_in(item.metadata || %{}, ["delivery_brief_artifact_id"]) == delivery_brief.id
            end,
            %{
              "kind" => "task",
              "goal" =>
                "Approve degraded delivery for #{Map.get(review_delivery || %{}, "channel", Map.get(review_delivery || %{}, "mode", "report"))} #{Map.get(review_delivery || %{}, "target", "control-plane")}",
              "status" => "completed",
              "execution_mode" => "execute",
              "assigned_agent_id" => publish_item.assigned_agent_id,
              "assigned_role" => "operator",
              "parent_work_item_id" => publish_item.id,
              "priority" => max(publish_item.priority, 1),
              "autonomy_level" => "execute_with_review",
              "approval_stage" => "validated",
              "result_refs" => %{
                "artifact_ids" => [delivery_brief.id],
                "degraded" => true
              },
              "metadata" => %{
                "task_type" => "publish_approval",
                "publish_work_item_id" => publish_item.id,
                "delivery_brief_artifact_id" => delivery_brief.id,
                "delivery" => review_delivery,
                "delivery_decision" => %{
                  "destination" => payload["delivery_destination"],
                  "destination_rationale" => payload["destination_rationale"],
                  "decision_confidence" => payload["decision_confidence"],
                  "confidence_posture" => payload["confidence_posture"]
                },
                "delivery_decision_snapshot" => payload["delivery_decision_snapshot"] || %{},
                "delivery_recovery" => delivery_recovery,
                "degraded_execution" => true,
                "requested_action" => "publish_review_report",
                "follow_up_context" => get_in(publish_item.metadata || %{}, ["follow_up_context"])
              }
            }
          )

        {:ok, updated_publish_item} =
          save_work_item(publish_item, %{
            "result_refs" =>
              append_follow_up_result_refs(
                publish_item.result_refs,
                review_item,
                "publish_review"
              )
          })

        {:ok, updated_publish_item, review_item}
    end
  end

  defp execute_publish_delivery(agent, channel, target, content) do
    case HydraX.Runtime.authorize_delivery(agent.id, :job, channel) do
      :ok ->
        case deliver_publish_summary(channel, target, content) do
          {:ok, metadata} ->
            %{
              "status" => "delivered",
              "channel" => channel,
              "target" => target,
              "delivered_at" => DateTime.utc_now(),
              "metadata" => stringify_delivery_metadata(metadata)
            }

          {:error, reason} ->
            %{
              "status" => "failed",
              "channel" => channel,
              "target" => target,
              "attempted_at" => DateTime.utc_now(),
              "reason" => inspect(reason)
            }
        end

      {:error, reason} ->
        %{
          "status" => "blocked",
          "channel" => channel,
          "target" => target,
          "attempted_at" => DateTime.utc_now(),
          "reason" => inspect(reason)
        }
    end
  end

  defp deliver_publish_summary("telegram", target, content) do
    with config when not is_nil(config) <- HydraX.Runtime.TelegramAdmin.enabled_telegram_config(),
         {:ok, state} <-
           HydraX.Gateway.Adapters.Telegram.connect(%{
             "bot_token" => config.bot_token,
             "bot_username" => config.bot_username,
             "webhook_secret" => config.webhook_secret,
             "deliver" => Application.get_env(:hydra_x, :telegram_deliver)
           }),
         {:ok, metadata} <-
           normalize_publish_delivery_result(
             HydraX.Gateway.Adapters.Telegram.send_response(
               %{content: content, external_ref: target},
               state
             )
           ) do
      {:ok, metadata}
    else
      nil -> {:error, :telegram_not_configured}
      {:error, reason} -> {:error, reason}
    end
  end

  defp deliver_publish_summary("discord", target, content) do
    with config when not is_nil(config) <- HydraX.Runtime.DiscordAdmin.enabled_discord_config(),
         {:ok, state} <-
           HydraX.Gateway.Adapters.Discord.connect(%{
             "bot_token" => config.bot_token,
             "application_id" => config.application_id,
             "webhook_secret" => config.webhook_secret,
             "deliver" => Application.get_env(:hydra_x, :discord_deliver)
           }),
         {:ok, metadata} <-
           normalize_publish_delivery_result(
             HydraX.Gateway.Adapters.Discord.deliver(
               %{content: content, external_ref: target},
               state
             )
           ) do
      {:ok, metadata}
    else
      nil -> {:error, :discord_not_configured}
      {:error, reason} -> {:error, reason}
    end
  end

  defp deliver_publish_summary("slack", target, content) do
    with config when not is_nil(config) <- HydraX.Runtime.SlackAdmin.enabled_slack_config(),
         {:ok, state} <-
           HydraX.Gateway.Adapters.Slack.connect(%{
             "bot_token" => config.bot_token,
             "signing_secret" => config.signing_secret,
             "deliver" => Application.get_env(:hydra_x, :slack_deliver)
           }),
         {:ok, metadata} <-
           normalize_publish_delivery_result(
             HydraX.Gateway.Adapters.Slack.deliver(
               %{content: content, external_ref: target},
               state
             )
           ) do
      {:ok, metadata}
    else
      nil -> {:error, :slack_not_configured}
      {:error, reason} -> {:error, reason}
    end
  end

  defp deliver_publish_summary("webchat", target, content) do
    with config when not is_nil(config) <- HydraX.Runtime.WebchatAdmin.enabled_webchat_config(),
         {:ok, state} <-
           HydraX.Gateway.Adapters.Webchat.connect(%{
             "enabled" => config.enabled,
             "title" => config.title,
             "subtitle" => config.subtitle,
             "welcome_prompt" => config.welcome_prompt,
             "composer_placeholder" => config.composer_placeholder,
             "allow_anonymous_messages" => config.allow_anonymous_messages,
             "attachments_enabled" => config.attachments_enabled,
             "max_attachment_count" => config.max_attachment_count,
             "max_attachment_size_kb" => config.max_attachment_size_kb,
             "session_max_age_minutes" => config.session_max_age_minutes,
             "session_idle_timeout_minutes" => config.session_idle_timeout_minutes
           }),
         {:ok, metadata} <-
           normalize_publish_delivery_result(
             HydraX.Gateway.Adapters.Webchat.deliver(
               %{content: content, external_ref: target},
               state
             )
           ) do
      {:ok, metadata}
    else
      nil -> {:error, :webchat_not_configured}
      {:error, reason} -> {:error, reason}
    end
  end

  defp deliver_publish_summary(channel, _target, _content),
    do: {:error, {:unsupported_delivery_channel, channel}}

  defp normalize_publish_delivery_result(:ok), do: {:ok, %{}}

  defp normalize_publish_delivery_result({:ok, metadata}) when is_map(metadata),
    do: {:ok, metadata}

  defp normalize_publish_delivery_result({:error, reason}), do: {:error, reason}

  defp stringify_delivery_metadata(map) do
    Enum.reduce(map, %{}, fn
      {key, value}, acc when is_atom(key) -> Map.put(acc, Atom.to_string(key), value)
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end

  defp llm_body_for(agent, %WorkItem{} = work_item, prompt, purpose) do
    messages = [%{role: "user", content: prompt}]
    estimated_tokens = Budget.estimate_prompt_tokens(messages)

    if token_budget_available?(agent, work_item, estimated_tokens) do
      case Budget.preflight(agent.id, nil, estimated_tokens) do
        {:ok, _} ->
          case Router.complete(%{
                 messages: messages,
                 agent_id: agent.id,
                 process_type: "autonomy"
               }) do
            {:ok, response} ->
              maybe_record_work_item_budget_usage(
                agent,
                work_item,
                purpose,
                estimated_tokens,
                Budget.estimate_tokens(response.content || ""),
                %{provider: response.provider}
              )

              response.content

            {:error, _reason} ->
              nil
          end

        {:error, _} ->
          nil
      end
    end
  end

  defp token_budget_available?(agent, %WorkItem{} = work_item, estimated_tokens) do
    limit = get_in(work_item.budget || %{}, ["token_budget"])

    cond do
      not is_integer(limit) or limit <= 0 ->
        true

      true ->
        usage = Budget.work_item_usage(agent.id, work_item.id)
        usage.total_tokens + estimated_tokens <= limit
    end
  end

  defp maybe_record_work_item_budget_usage(
         agent,
         %WorkItem{} = work_item,
         purpose,
         tokens_in,
         tokens_out,
         extra_metadata \\ %{}
       ) do
    Budget.record_usage(agent.id, nil,
      tokens_in: tokens_in,
      tokens_out: tokens_out,
      metadata:
        extra_metadata
        |> Helpers.normalize_string_keys()
        |> Map.put("purpose", purpose)
        |> Map.put("work_item_id", work_item.id)
    )
  end

  defp workspace_snapshot(workspace_root, goal) do
    files =
      workspace_root
      |> list_workspace_files()
      |> Enum.reject(&String.starts_with?(&1, ".git/"))

    candidate_files =
      files
      |> Enum.sort_by(&workspace_goal_score(&1, goal), :desc)
      |> Enum.take(8)

    %{
      "workspace_root" => workspace_root,
      "contract_files" => Workspace.load_context(workspace_root) |> Map.keys(),
      "file_count" => length(files),
      "candidate_files" => candidate_files
    }
  end

  defp list_workspace_files(workspace_root) do
    workspace_root
    |> do_list_workspace_files(".")
    |> Enum.sort()
  end

  defp do_list_workspace_files(workspace_root, relative_path) do
    current =
      case relative_path do
        "." -> workspace_root
        other -> Path.join(workspace_root, other)
      end

    case File.ls(current) do
      {:ok, entries} ->
        Enum.flat_map(entries, fn entry ->
          child_relative =
            if relative_path == "." do
              entry
            else
              Path.join(relative_path, entry)
            end

          child_absolute = Path.join(workspace_root, child_relative)

          cond do
            File.dir?(child_absolute) ->
              do_list_workspace_files(workspace_root, child_relative)

            File.regular?(child_absolute) ->
              [child_relative]

            true ->
              []
          end
        end)

      _ ->
        []
    end
  end

  defp workspace_goal_score(path, goal) do
    delegation_goal_score(path, goal)
  end

  defp delegation_goal_score(text, goal)
       when is_binary(text) and is_binary(goal) do
    tokens =
      goal
      |> String.downcase()
      |> String.split(~r/[^a-z0-9]+/, trim: true)

    downcased = String.downcase(text)
    Enum.count(tokens, &String.contains?(downcased, &1))
  end

  defp delegation_goal_score(_text, _goal), do: 0

  defp default_test_commands(%WorkItem{kind: "extension"}),
    do: ["mix test --failed", "mix compile"]

  defp default_test_commands(_work_item),
    do: ["mix test --failed", "mix format --check-formatted"]

  defp engineering_risks(work_item, workspace_snapshot) do
    [
      "candidate file scope may omit affected dependencies",
      "#{workspace_snapshot["file_count"]} workspace files may broaden regression scope",
      "promotion remains blocked until reviewer validation for #{work_item.kind}"
    ]
  end

  defp engineering_rollback_notes(work_item) do
    "Revert the #{work_item.kind} patch, restore changed files from git history, and rerun validation commands."
  end

  defp review_findings(changed_files, test_commands, target_kind, source_payload, source_artifact) do
    case target_kind do
      kind when kind in ["engineering", "extension"] ->
        []
        |> maybe_add_finding(
          changed_files == [],
          "No candidate changed files were prepared for review."
        )
        |> maybe_add_finding(
          test_commands == [],
          "No validation commands were attached to the change set."
        )
        |> maybe_add_finding(
          target_kind == "extension" and is_nil(source_payload["extension_package"]),
          "Extension packages must include explicit compatibility and registration metadata."
        )
        |> maybe_add_finding(
          target_kind == "extension" and
            get_in(source_payload, ["registration", "enablement_status"]) != "approval_required",
          "Generated extensions must remain approval-gated until an operator enables them."
        )

      "research" ->
        []
        |> maybe_add_finding(
          is_nil(source_artifact) or source_artifact.type != "research_report",
          "No structured research report was prepared for reviewer approval."
        )
        |> maybe_add_finding(
          List.wrap(source_payload["claims"]) == [],
          "Research reports must include explicit claims before findings can be promoted."
        )
        |> maybe_add_finding(
          List.wrap(source_payload["recommended_actions"]) == [],
          "Research reports must include recommended actions for reviewer approval."
        )

      _ ->
        []
        |> maybe_add_finding(
          is_nil(source_artifact),
          "No reviewable artifact payload was prepared for this work item."
        )
    end
  end

  defp maybe_add_finding(list, false, _message), do: list
  defp maybe_add_finding(list, true, message), do: list ++ [message]

  defp delegation_plan_body(parent, %WorkItem{} = child, delegation_context)
       when is_list(delegation_context) do
    delegation_plan_body(parent, [%{child: child, delegation_context: delegation_context}], %{
      "mode" => "single",
      "expected_count" => 1
    })
  end

  defp delegation_plan_body(parent, delegated_children, batch_snapshot)
       when is_list(delegated_children) do
    """
    Parent goal: #{parent.goal}
    Delegation mode: #{batch_snapshot["mode"]}
    Expected children: #{batch_snapshot["expected_count"]}

    Delegated work:
    #{Enum.map_join(delegated_children, "\n\n", &delegation_plan_child_block/1)}
    """
    |> String.trim()
  end

  defp delegation_plan_child_block(%{child: child, delegation_context: delegation_context}) do
    """
    Child work item: ##{child.id}
    Goal: #{child.goal}
    Delegated role: #{child.assigned_role}
    Kind: #{child.kind}
    Execution mode: #{child.execution_mode}
    Delegated context:
    #{Enum.map_join(delegation_context, "\n", fn memory -> "- #{memory["type"]}: #{memory["content"]}" end)}
    """
    |> String.trim()
  end

  defp delegation_plan_title(%{"expected_count" => expected_count}) when expected_count > 1,
    do: "Delegation batch plan"

  defp delegation_plan_title(_snapshot), do: "Delegation plan"

  defp delegation_plan_summary(parent, %{"expected_count" => expected_count, "roles" => roles})
       when expected_count > 1 do
    "Delegated #{parent.kind} batch of #{expected_count} tasks to #{Enum.join(List.wrap(roles), ", ")}"
  end

  defp delegation_plan_summary(parent, %{"roles" => [role | _]}),
    do: "Delegated #{parent.kind} to #{role}"

  defp delegation_plan_summary(parent, _snapshot), do: "Delegated #{parent.kind}"

  defp delegation_summary_line(_parent, children, supporting_memories) do
    child_count = length(children)
    finding_count = length(supporting_memories)

    cond do
      finding_count > 0 ->
        "Planner synthesized #{child_count} delegated outcomes and #{finding_count} promoted findings"

      true ->
        "Planner synthesized #{child_count} delegated outcomes"
    end
  end

  defp delegation_summary_body(parent, children, supporting_memories) do
    delivery_decisions = delivery_decision_findings(supporting_memories)

    findings_without_delivery =
      supporting_memories
      |> List.wrap()
      |> Enum.reject(&delivery_decision_finding?/1)

    findings_block =
      case findings_without_delivery do
        [] ->
          "No promoted findings were available from completed delegated work."

        findings ->
          Enum.map_join(findings, "\n", fn finding ->
            score =
              case finding["score"] do
                value when is_float(value) -> " [#{Float.round(value, 2)}]"
                value when is_integer(value) -> " [#{value}]"
                _ -> ""
              end

            source =
              [
                finding["source_role"],
                finding["source_artifact_type"]
              ]
              |> Enum.reject(&(&1 in [nil, ""]))
              |> Enum.join(" · ")

            reason =
              finding["summary_reason"] ||
                List.first(List.wrap(finding["reasons"])) ||
                "promoted child finding"

            "- ##{finding["source_work_item_id"]} #{finding["type"]}#{score}: #{finding["content"]} (#{reason})#{if(source == "", do: "", else: " [#{source}]")}"
          end)
      end

    delivery_decisions_block =
      case delivery_decisions do
        [] ->
          "No prior delivery decisions were elevated into this synthesis."

        entries ->
          Enum.map_join(entries, "\n", fn finding ->
            source =
              [finding["source_role"], finding["source_artifact_type"]]
              |> Enum.reject(&(&1 in [nil, ""]))
              |> Enum.join(" · ")

            "- ##{finding["source_work_item_id"]} #{finding["content"]}#{if(source == "", do: "", else: " [#{source}]")}"
          end)
      end

    """
    Parent goal: #{parent.goal}

    Delegated work outcomes:
    #{Enum.map_join(children, "\n", &delegated_child_summary/1)}

    Promoted findings shaping this synthesis:
    #{findings_block}

    Delivery decisions shaping this synthesis:
    #{delivery_decisions_block}
    """
    |> String.trim()
  end

  defp delegated_child_summary(child) do
    failure =
      case get_in(child.result_refs || %{}, ["policy_failure"]) do
        failure when is_map(failure) ->
          " (#{policy_failure_summary(failure)})"

        _ ->
          ""
      end

    "- ##{child.id} #{child.goal} [#{child.status}]#{failure}"
  end

  defp delegation_batch_entries(%WorkItem{} = work_item) do
    metadata = work_item.metadata || %{}
    default_goal = metadata["delegate_goal"] || work_item.goal
    default_kind = work_item.kind
    default_role = metadata["delegate_role"] || Autonomy.role_for_kind(default_kind)
    default_priority = max(work_item.priority, 1)

    metadata
    |> Map.get("delegate_batch", [])
    |> List.wrap()
    |> case do
      [] ->
        [
          %{
            "goal" => default_goal,
            "kind" => default_kind,
            "assigned_role" => Autonomy.normalize_role(default_role),
            "assigned_agent_id" => nil,
            "priority" => default_priority,
            "autonomy_level" => work_item.autonomy_level,
            "approval_stage" => work_item.approval_stage,
            "review_required" => work_item.review_required,
            "budget" => work_item.budget,
            "required_outputs" => work_item.required_outputs,
            "deliverables" => work_item.deliverables,
            "metadata" => %{},
            "child_key" => "delegate-1"
          }
        ]

      entries ->
        entries
        |> Enum.with_index(1)
        |> Enum.map(fn {entry, index} ->
          normalize_delegation_batch_entry(
            entry,
            work_item,
            index,
            default_goal,
            default_kind,
            default_role,
            default_priority
          )
        end)
    end
  end

  defp seed_delegation_batch_metadata(metadata, entries, concurrency) do
    Map.put(metadata || %{}, "delegation_batch", %{
      "mode" => if(length(entries) > 1, do: "parallel", else: "single"),
      "expected_count" => length(entries),
      "batch_concurrency" => concurrency,
      "batch_strategy" => delegation_batch_strategy(metadata),
      "items" => Enum.map(entries, &delegation_batch_planned_item/1)
    })
  end

  defp select_delegation_batch_entries_for_dispatch(
         work_item,
         entries,
         concurrency,
         existing_items \\ []
       )

  defp select_delegation_batch_entries_for_dispatch(
         _work_item,
         _entries,
         concurrency,
         _existing_items
       )
       when not is_integer(concurrency) or concurrency <= 0 do
    []
  end

  defp select_delegation_batch_entries_for_dispatch(
         work_item,
         entries,
         concurrency,
         existing_items
       ) do
    case delegation_batch_strategy(work_item) do
      "balance_roles" ->
        balance_delegation_batch_entries(entries, concurrency, existing_items)

      _ ->
        Enum.take(entries, concurrency)
    end
  end

  defp balance_delegation_batch_entries(entries, concurrency, existing_items) do
    indexed_entries = Enum.with_index(entries)
    role_capacity = delegation_role_capacity()
    active_role_counts = delegation_active_role_counts(existing_items)

    {selected, _counts} =
      Enum.reduce(1..concurrency, {[], active_role_counts}, fn _slot, {chosen, counts} ->
        remaining =
          indexed_entries
          |> Enum.reject(fn {_entry, index} ->
            Enum.any?(chosen, fn {_chosen, chosen_index} -> chosen_index == index end)
          end)

        case best_delegation_batch_entry(remaining, counts, role_capacity) do
          nil ->
            {chosen, counts}

          {entry, index} ->
            role = entry["assigned_role"] || entry["role"]

            {
              chosen ++ [{entry, index}],
              Map.update(counts, role, 1, &(&1 + 1))
            }
        end
      end)

    Enum.map(selected, fn {entry, _index} -> entry end)
  end

  defp best_delegation_batch_entry([], _counts, _role_capacity), do: nil

  defp best_delegation_batch_entry(indexed_entries, counts, role_capacity) do
    indexed_entries
    |> Enum.max_by(
      fn {entry, index} ->
        role = entry["assigned_role"] || entry["role"]
        pressure = Map.get(role_capacity, role, %{})

        {
          delegation_role_capacity_score(pressure),
          -Map.get(counts, role, 0),
          -delegation_entry_priority(entry),
          -index
        }
      end,
      fn -> nil end
    )
  end

  defp delegation_role_capacity do
    active_agents =
      Agents.list_agents()
      |> Enum.filter(&(&1.status == "active"))

    all_work_items = list_work_items(limit: 500, preload: false)
    role_queue_backlog = build_role_queue_backlog(all_work_items, active_agents)

    build_worker_pressure(all_work_items, active_agents, role_queue_backlog)
    |> Enum.group_by(& &1.role)
    |> Map.new(fn {role, workers} ->
      {role,
       %{
         total_workers: length(workers),
         idle_workers: Enum.count(workers, &(&1.capacity_posture == "idle")),
         available_workers: Enum.count(workers, &(&1.capacity_posture == "available")),
         busy_workers: Enum.count(workers, &(&1.capacity_posture == "busy")),
         saturated_workers: Enum.count(workers, &(&1.capacity_posture == "saturated")),
         active_claimed_count: Enum.reduce(workers, 0, &(&1.active_claimed_count + &2)),
         shared_role_queue_count:
           Enum.max(Enum.map(workers, &(&1.shared_role_queue_count || 0)), fn -> 0 end)
       }}
    end)
  end

  defp delegation_active_role_counts(items) when is_list(items) do
    items
    |> Enum.reduce(%{}, fn item, acc ->
      status = item["status"] || item[:status]
      role = item["assigned_role"] || item[:assigned_role] || item["role"] || item[:role]

      if role in [nil, ""] or status in (@terminal_work_item_statuses ++ ["pending_dispatch"]) do
        acc
      else
        Map.update(acc, role, 1, &(&1 + 1))
      end
    end)
  end

  defp delegation_active_role_counts(_items), do: %{}

  defp delegation_role_capacity_score(pressure) when is_map(pressure) do
    (pressure[:idle_workers] || pressure["idle_workers"] || 0) * 4.0 +
      (pressure[:available_workers] || pressure["available_workers"] || 0) * 2.0 +
      (pressure[:busy_workers] || pressure["busy_workers"] || 0) * 0.5 -
      (pressure[:saturated_workers] || pressure["saturated_workers"] || 0) * 3.0 -
      min(pressure[:shared_role_queue_count] || pressure["shared_role_queue_count"] || 0, 8) *
        0.25 -
      min(pressure[:active_claimed_count] || pressure["active_claimed_count"] || 0, 8) * 0.15
  end

  defp delegation_role_capacity_score(_pressure), do: 0.0

  defp delegation_entry_priority(entry) when is_map(entry) do
    entry["priority"] || entry[:priority] || 0
  end

  defp delegation_entry_priority(_entry), do: 0

  defp dispatch_delegated_batch_item(%WorkItem{} = work_item, %AgentProfile{} = agent, entry) do
    child_goal = entry["goal"]
    override_context = delegation_override_context(work_item)

    delegation_limit =
      if Enum.any?(override_context, &delivery_decision_finding?/1), do: 5, else: 3

    delegation_context =
      merge_delegation_context(
        delegation_context_snapshot(agent.id, child_goal),
        override_context,
        delegation_limit
      )

    child_metadata =
      entry["metadata"]
      |> delegation_child_metadata(work_item, agent, entry)
      |> maybe_put_delegation_context(delegation_context, agent.id, child_goal)

    {:ok, child} =
      save_work_item(%{
        "kind" => entry["kind"],
        "goal" => child_goal,
        "status" => "planned",
        "execution_mode" => "execute",
        "assigned_role" => entry["assigned_role"],
        "assigned_agent_id" => entry["assigned_agent_id"],
        "delegated_by_agent_id" => agent.id,
        "parent_work_item_id" => work_item.id,
        "priority" => entry["priority"],
        "autonomy_level" => entry["autonomy_level"],
        "approval_stage" => entry["approval_stage"],
        "review_required" => entry["review_required"],
        "budget" => entry["budget"],
        "required_outputs" => entry["required_outputs"],
        "deliverables" => entry["deliverables"],
        "metadata" => child_metadata
      })

    %{child: child, spec: entry, delegation_context: delegation_context}
  end

  defp normalize_delegation_batch_entry(
         entry,
         %WorkItem{} = work_item,
         index,
         default_goal,
         default_kind,
         default_role,
         default_priority
       )
       when is_map(entry) do
    normalized = Helpers.normalize_string_keys(entry)
    kind = normalized["kind"] || default_kind

    role =
      normalized["assigned_role"] || normalized["delegate_role"] || normalized["role"] ||
        Autonomy.role_for_kind(kind) || default_role

    %{
      "goal" => normalized["goal"] || default_goal,
      "kind" => kind,
      "assigned_role" => Autonomy.normalize_role(role),
      "assigned_agent_id" => normalized["assigned_agent_id"],
      "priority" => normalized["priority"] || default_priority,
      "autonomy_level" => normalized["autonomy_level"] || work_item.autonomy_level,
      "approval_stage" => normalized["approval_stage"] || work_item.approval_stage,
      "review_required" => Map.get(normalized, "review_required", work_item.review_required),
      "budget" => normalized["budget"] || work_item.budget,
      "required_outputs" => normalized["required_outputs"] || default_required_outputs(kind),
      "deliverables" => normalized["deliverables"] || work_item.deliverables,
      "metadata" => Helpers.normalize_string_keys(normalized["metadata"] || %{}),
      "child_key" => normalized["child_key"] || normalized["key"] || "delegate-#{index}"
    }
  end

  defp delegation_child_metadata(
         metadata,
         %WorkItem{} = work_item,
         %AgentProfile{} = agent,
         entry
       ) do
    Map.merge(
      Helpers.normalize_string_keys(metadata || %{}),
      %{
        "assignment_mode" => "role_claim",
        "claim_scope" => "role_pool",
        "delegated_from_role" => agent.role,
        "delegated_from_work_item_id" => work_item.id,
        "delegation_batch_key" => entry["child_key"]
      }
    )
  end

  defp build_delegation_batch_snapshot(work_item, children, delegated_children \\ nil)

  defp build_delegation_batch_snapshot(work_item, children, delegated_children) do
    metadata_snapshot =
      work_item
      |> work_item_metadata()
      |> Map.get("delegation_batch", %{})
      |> Helpers.normalize_string_keys()

    planned_items =
      cond do
        List.wrap(metadata_snapshot["items"]) != [] ->
          Enum.map(List.wrap(metadata_snapshot["items"]), &delegation_batch_planned_item/1)

        is_list(delegated_children) and delegated_children != [] ->
          Enum.map(delegated_children, &delegation_batch_planned_item/1)

        true ->
          []
      end

    live_entries =
      cond do
        is_list(delegated_children) and delegated_children != [] ->
          Enum.map(delegated_children, &delegation_batch_child_entry/1)

        children != [] ->
          Enum.map(children, &delegation_batch_child_entry/1)

        true ->
          []
      end

    live_entries_by_key =
      live_entries
      |> Enum.filter(&present_text?(&1["child_key"]))
      |> Map.new(&{&1["child_key"], &1})

    child_entries =
      case planned_items do
        [] ->
          live_entries

        entries ->
          Enum.map(entries, fn item ->
            key = item["child_key"]
            live = key && Map.get(live_entries_by_key, key)

            if live do
              Map.merge(item, live)
            else
              item
            end
          end)
      end

    expected_count =
      metadata_snapshot["expected_count"] || length(child_entries) ||
        delegation_expected_count(work_item)

    roles =
      child_entries
      |> Enum.map(&(&1["assigned_role"] || &1["role"]))
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.uniq()

    terminal_count =
      Enum.count(child_entries, &(&1["status"] in @terminal_work_item_statuses))

    pending_count =
      Enum.count(child_entries, fn item ->
        item["status"] == "pending_dispatch" or is_nil(item["id"])
      end)

    pending_roles =
      child_entries
      |> Enum.filter(fn item ->
        item["status"] == "pending_dispatch" or is_nil(item["id"])
      end)
      |> Enum.map(&(&1["assigned_role"] || &1["role"]))
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.frequencies()

    completed_count = Enum.count(child_entries, &(&1["status"] == "completed"))
    failed_count = Enum.count(child_entries, &(&1["status"] == "failed"))
    canceled_count = Enum.count(child_entries, &(&1["status"] == "canceled"))
    dispatched_count = Enum.count(child_entries, &is_integer(&1["id"]))

    active_count =
      case child_entries do
        [] ->
          max(expected_count - terminal_count, 0)

        _ ->
          Enum.count(child_entries, fn item ->
            item["status"] not in (@terminal_work_item_statuses ++ ["pending_dispatch"])
          end)
      end

    if expected_count <= 0 do
      %{}
    else
      %{
        "mode" => if(expected_count > 1, do: "parallel", else: "single"),
        "expected_count" => expected_count,
        "batch_strategy" => delegation_batch_strategy(work_item, metadata_snapshot),
        "batch_concurrency" =>
          delegation_batch_concurrency(
            work_item,
            expected_count,
            metadata_snapshot["batch_concurrency"]
          ),
        "dispatched_count" => dispatched_count,
        "pending_count" => pending_count,
        "pending_roles" => pending_roles,
        "active_count" => active_count,
        "terminal_count" => terminal_count,
        "completed_count" => completed_count,
        "failed_count" => failed_count,
        "canceled_count" => canceled_count,
        "roles" => roles,
        "items" => child_entries,
        "child_work_item_ids" =>
          child_entries
          |> Enum.map(& &1["id"])
          |> Enum.filter(&is_integer/1),
        "batch_label" =>
          metadata_snapshot["batch_label"] ||
            if(expected_count > 1, do: "parallel delegation batch", else: "delegation")
      }
    end
  end

  defp delegation_batch_child_entry(%{child: child, spec: spec}) do
    child
    |> delegation_batch_child_entry()
    |> Map.put("child_key", spec["child_key"])
  end

  defp delegation_batch_child_entry(%WorkItem{} = child) do
    %{
      "id" => child.id,
      "goal" => child.goal,
      "kind" => child.kind,
      "assigned_role" => child.assigned_role,
      "status" => child.status,
      "child_key" => get_in(child.metadata || %{}, ["delegation_batch_key"])
    }
  end

  defp delegation_batch_planned_item(%{spec: spec}) do
    delegation_batch_planned_item(spec)
  end

  defp delegation_batch_planned_item(spec) when is_map(spec) do
    normalized = Helpers.normalize_string_keys(spec)

    %{
      "id" => normalized["id"],
      "goal" => normalized["goal"],
      "kind" => normalized["kind"],
      "assigned_role" => normalized["assigned_role"],
      "assigned_agent_id" => normalized["assigned_agent_id"],
      "priority" => normalized["priority"],
      "autonomy_level" => normalized["autonomy_level"],
      "approval_stage" => normalized["approval_stage"],
      "review_required" => normalized["review_required"],
      "budget" => normalized["budget"],
      "required_outputs" => normalized["required_outputs"],
      "deliverables" => normalized["deliverables"],
      "metadata" => Helpers.normalize_string_keys(normalized["metadata"] || %{}),
      "child_key" => normalized["child_key"],
      "status" => normalized["status"] || "pending_dispatch"
    }
  end

  defp delegation_batch_children(%WorkItem{} = work_item) do
    case Map.get(work_item, :child_work_items) do
      children when is_list(children) ->
        children

      %Ecto.Association.NotLoaded{} ->
        list_work_items(
          parent_work_item_id: work_item.id,
          limit: delegated_child_limit(work_item),
          preload: false
        )

      _ ->
        list_work_items(
          parent_work_item_id: work_item.id,
          limit: delegated_child_limit(work_item),
          preload: false
        )
    end
  end

  defp delegation_batch_children(work_item) when is_map(work_item) do
    case Map.get(work_item, :child_work_items) || Map.get(work_item, "child_work_items") do
      children when is_list(children) ->
        children

      _ ->
        case Map.get(work_item, :id) || Map.get(work_item, "id") do
          id when is_integer(id) ->
            list_work_items(
              parent_work_item_id: id,
              limit: delegated_child_limit(work_item),
              preload: false
            )

          _ ->
            []
        end
    end
  end

  defp delegation_expected_count(%WorkItem{} = work_item) do
    metadata = work_item.metadata || %{}
    batch = Map.get(metadata, "delegation_batch", %{})

    batch["expected_count"] ||
      metadata
      |> Map.get("delegate_batch", [])
      |> List.wrap()
      |> length()
      |> max(1)
  end

  defp delegation_expected_count(work_item) when is_map(work_item) do
    metadata = work_item_metadata(work_item)
    batch = Map.get(metadata, "delegation_batch", %{})

    batch["expected_count"] ||
      metadata
      |> Map.get("delegate_batch", [])
      |> List.wrap()
      |> length()
      |> max(1)
  end

  defp delegation_batch_concurrency(work_item, expected_count) do
    delegation_batch_concurrency(work_item, expected_count, nil)
  end

  defp delegation_batch_concurrency(_work_item, expected_count, seeded_concurrency)
       when is_integer(seeded_concurrency) do
    clamp_delegation_batch_concurrency(seeded_concurrency, expected_count)
  end

  defp delegation_batch_concurrency(%WorkItem{} = work_item, expected_count, _seeded_concurrency) do
    metadata = work_item.metadata || %{}

    value =
      metadata["delegate_batch_concurrency"] ||
        get_in(metadata, ["delegation_batch", "batch_concurrency"]) ||
        expected_count

    clamp_delegation_batch_concurrency(value, expected_count)
  end

  defp delegation_batch_concurrency(work_item, expected_count, _seeded_concurrency)
       when is_map(work_item) do
    metadata = work_item_metadata(work_item)

    value =
      metadata["delegate_batch_concurrency"] ||
        get_in(metadata, ["delegation_batch", "batch_concurrency"]) ||
        expected_count

    clamp_delegation_batch_concurrency(value, expected_count)
  end

  defp delegation_batch_strategy(work_item), do: delegation_batch_strategy(work_item, nil)

  defp delegation_batch_strategy(%WorkItem{} = work_item, seeded_snapshot) do
    delegation_batch_strategy_from_metadata(work_item.metadata || %{}, seeded_snapshot)
  end

  defp delegation_batch_strategy(work_item, seeded_snapshot) when is_map(work_item) do
    delegation_batch_strategy_from_metadata(work_item_metadata(work_item), seeded_snapshot)
  end

  defp delegation_batch_strategy_from_metadata(metadata, seeded_snapshot)
       when is_map(metadata) and (is_map(seeded_snapshot) or is_nil(seeded_snapshot)) do
    metadata["delegate_batch_strategy"] ||
      get_in(metadata, ["delegation_batch", "batch_strategy"]) ||
      (seeded_snapshot && seeded_snapshot["batch_strategy"]) ||
      "ordered"
  end

  defp clamp_delegation_batch_concurrency(value, expected_count)
       when is_integer(value) and is_integer(expected_count) do
    value
    |> max(1)
    |> min(max(expected_count, 1))
  end

  defp clamp_delegation_batch_concurrency(_value, expected_count), do: max(expected_count, 1)

  defp delegation_batch_expandable?(%WorkItem{} = work_item) do
    case delegation_batch_snapshot(work_item) do
      %{} = snapshot ->
        (snapshot["pending_count"] || 0) > 0 and delegation_batch_available_slots(snapshot) > 0

      _ ->
        false
    end
  end

  defp delegation_batch_available_slots(%{} = snapshot) do
    max((snapshot["batch_concurrency"] || 1) - (snapshot["active_count"] || 0), 0)
  end

  defp pending_delegation_batch_items(%{} = snapshot) do
    snapshot
    |> Map.get("items", [])
    |> List.wrap()
    |> Enum.filter(fn item ->
      item["status"] == "pending_dispatch" or is_nil(item["id"])
    end)
  end

  defp delegated_child_limit(work_item) do
    max(delegation_expected_count(work_item), 20)
  end

  defp append_artifact_ref(result_refs, artifact_id) when is_integer(artifact_id) do
    ids =
      result_refs
      |> Kernel.||(%{})
      |> Map.get("artifact_ids", [])
      |> List.wrap()
      |> Kernel.++([artifact_id])
      |> Enum.uniq()

    Map.put(result_refs || %{}, "artifact_ids", ids)
  end

  defp work_item_metadata(%WorkItem{} = work_item), do: work_item.metadata || %{}

  defp work_item_metadata(work_item) when is_map(work_item),
    do: Map.get(work_item, :metadata) || Map.get(work_item, "metadata") || %{}

  defp research_plan_body(work_item, evidence) do
    """
    Question: #{work_item.goal}

    Evidence candidates:
    #{Enum.map_join(evidence, "\n", fn ranked -> "- #{ranked.entry.type}: #{ranked.entry.content}" end)}
    """
    |> String.trim()
  end

  defp derive_claims(evidence, delegated_context) do
    evidence_claims =
      evidence
      |> Enum.take(3)
      |> Enum.map(fn ranked -> ranked.entry.content end)

    if evidence_claims == [] do
      delegated_context
      |> Enum.take(3)
      |> Enum.map(& &1["content"])
    else
      evidence_claims
    end
  end

  defp derive_open_questions(work_item, evidence, delegated_context) do
    cond do
      evidence == [] and delegated_context == [] ->
        ["No supporting memory evidence was found for #{work_item.goal}."]

      delegated_context != [] ->
        ["Which delegated findings should be validated with fresh evidence before wider action?"]

      true ->
        ["What new external evidence should be gathered to validate the current findings?"]
    end
  end

  defp derive_recommended_actions(work_item, evidence, delegated_context) do
    cond do
      evidence == [] and delegated_context == [] ->
        ["Gather fresh sources for #{work_item.goal} before acting on it."]

      delegated_context != [] ->
        [
          "Validate the delegated research findings and use them to guide the next execution step."
        ]

      true ->
        ["Review the report and promote any durable findings into long-term memory."]
    end
  end

  defp derive_confidence([]), do: 0.28

  defp derive_confidence(evidence) do
    evidence
    |> Enum.map(& &1.score)
    |> Enum.max(fn -> 0.0 end)
    |> Kernel./(3.0)
    |> min(0.92)
    |> Float.round(2)
  end

  defp source_snapshot(ranked) do
    metadata = ranked.entry.metadata || %{}

    %{
      "memory_id" => ranked.entry.id,
      "type" => ranked.entry.type,
      "source_file" => metadata["source_file"],
      "source_section" => metadata["source_section"],
      "source_channel" => metadata["source_channel"],
      "source" => metadata["source"]
    }
  end

  defp evidence_snapshot(ranked) do
    %{
      "memory_id" => ranked.entry.id,
      "content" => ranked.entry.content,
      "score" => ranked.score,
      "reasons" => ranked.reasons,
      "score_breakdown" => ranked.score_breakdown
    }
  end

  defp source_label(ranked) do
    metadata = ranked.entry.metadata || %{}

    Enum.reject(
      [
        metadata["source_file"],
        metadata["source_section"],
        metadata["source_channel"]
      ],
      &(&1 in [nil, ""])
    )
    |> Enum.join(" · ")
    |> case do
      "" -> nil
      label -> label
    end
  end

  defp delegation_context_snapshot(agent_id, goal, limit \\ 3) do
    memory_context =
      agent_id
      |> Memory.search_ranked(goal, max(limit * 4, 8), status: "active")
      |> Enum.filter(fn ranked ->
        metadata = ranked.entry.metadata || %{}
        metadata["memory_scope"] == "artifact_derived"
      end)
      |> Enum.map(&delegation_context_memory_snapshot/1)

    follow_up_context = planner_follow_up_context_snapshot(agent_id, goal, limit)

    (memory_context ++ follow_up_context)
    |> merge_delegation_context([], limit)
  end

  defp delegation_context_memory_snapshot(ranked) do
    metadata = ranked.entry.metadata || %{}

    %{
      "memory_id" => ranked.entry.id,
      "type" => ranked.entry.type,
      "content" => ranked.entry.content,
      "score" => ranked.score,
      "reasons" => ranked.reasons || [],
      "score_breakdown" => ranked.score_breakdown || %{},
      "source_work_item_id" => metadata["source_work_item_id"],
      "source_artifact_type" => metadata["source_artifact_type"]
    }
  end

  defp planner_follow_up_context_snapshot(agent_id, goal, limit) do
    WorkItem
    |> where(
      [work_item],
      work_item.status == "completed" and
        work_item.assigned_role == "planner" and
        work_item.assigned_agent_id == ^agent_id
    )
    |> order_by([work_item], desc: work_item.updated_at)
    |> limit(^max(limit * 3, 6))
    |> Repo.all()
    |> Enum.flat_map(fn work_item ->
      work_item
      |> finalized_follow_up_entries()
      |> Enum.map(&planner_follow_up_snapshot(&1, work_item, goal))
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp finalized_follow_up_entries(%WorkItem{} = work_item) do
    follow_up_context =
      work_item.metadata
      |> case do
        metadata when is_map(metadata) -> Map.get(metadata, "follow_up_context", %{})
        _ -> %{}
      end

    List.wrap(follow_up_context["promoted_findings"]) ++
      List.wrap(follow_up_context["delivery_decisions"])
  end

  defp planner_follow_up_snapshot(entry, work_item, goal) when is_map(entry) do
    content = entry["content"] || entry["action"]
    score = planner_follow_up_score(work_item.goal, content, goal, entry["score"])

    if score <= 0.0 do
      nil
    else
      %{
        "memory_id" => entry["memory_id"],
        "type" => entry["type"] || "Decision",
        "content" => content,
        "score" => score,
        "reasons" => ["finalized planner synthesis"],
        "score_breakdown" => %{
          "finalized_parent_goal_fit" => delegation_goal_score(work_item.goal, goal),
          "finalized_finding_fit" => delegation_goal_score(content, goal),
          "source_score" => base_follow_up_score(entry["score"])
        },
        "source_work_item_id" => work_item.id,
        "source_artifact_type" => entry["source_artifact_type"] || "decision_ledger"
      }
    end
  end

  defp planner_follow_up_snapshot(_entry, _work_item, _goal), do: nil

  defp delegation_override_context(%WorkItem{} = work_item) do
    metadata = work_item.metadata || %{}
    follow_up_context = Map.get(metadata, "follow_up_context", %{})

    constraint_findings =
      metadata
      |> Map.get("constraint_findings", [])
      |> List.wrap()
      |> Enum.map(&constraint_context_snapshot(&1, work_item))
      |> Enum.reject(&is_nil/1)

    strategy =
      case Map.get(metadata, "constraint_strategy") do
        value when is_binary(value) and value != "" ->
          [
            %{
              "memory_id" => nil,
              "type" => "Constraint",
              "content" => value,
              "score" => 1.2,
              "reasons" => ["delegated constraint strategy"],
              "score_breakdown" => %{"constraint_strategy" => 1.0},
              "source_work_item_id" => work_item.id,
              "source_artifact_type" => "constraint_strategy"
            }
          ]

        _ ->
          []
      end

    delivery_decisions =
      follow_up_context
      |> Map.get("delivery_decisions", [])
      |> List.wrap()

    constraint_findings ++ strategy ++ delivery_decisions
  end

  defp constraint_context_snapshot(entry, work_item) when is_map(entry) do
    content = entry["content"] || entry[:content]
    type = entry["type"] || entry[:type] || "Constraint"

    if is_binary(content) and content != "" do
      %{
        "memory_id" => entry["memory_id"] || entry[:memory_id],
        "type" => type,
        "content" => content,
        "score" => entry["score"] || entry[:score] || 1.1,
        "reasons" => ["delegated constraint"],
        "score_breakdown" => %{"constraint_signal" => 1.0},
        "source_work_item_id" =>
          entry["source_work_item_id"] || entry[:source_work_item_id] || work_item.id,
        "source_artifact_type" =>
          entry["source_artifact_type"] || entry[:source_artifact_type] || "constraint"
      }
    end
  end

  defp constraint_context_snapshot(_entry, _work_item), do: nil

  defp merge_delegation_context(base_context, extra_context, limit) do
    (List.wrap(base_context) ++ List.wrap(extra_context))
    |> Enum.uniq_by(fn memory ->
      {memory["source_work_item_id"], memory["source_artifact_type"], memory["type"],
       memory["content"]}
    end)
    |> Enum.sort_by(fn memory ->
      {-(memory["score"] || 0.0), memory["source_work_item_id"] || 0, memory["content"] || ""}
    end)
    |> Enum.take(limit)
  end

  defp planner_follow_up_score(parent_goal, content, goal, source_score) do
    delegation_goal_score(parent_goal, goal) +
      delegation_goal_score(content, goal) +
      base_follow_up_score(source_score)
  end

  defp base_follow_up_score(score) when is_float(score), do: score
  defp base_follow_up_score(score) when is_integer(score), do: score * 1.0
  defp base_follow_up_score(_score), do: 0.35

  defp maybe_put_delegation_context(metadata, [], _agent_id, _goal), do: metadata

  defp maybe_put_delegation_context(metadata, delegation_context, agent_id, goal) do
    Map.put(metadata, "delegation_context", %{
      "source_agent_id" => agent_id,
      "query" => goal,
      "captured_at" => DateTime.utc_now(),
      "promoted_memories" => delegation_context
    })
  end

  defp delegated_context_memories(work_item) do
    get_in(work_item.metadata || %{}, ["delegation_context", "promoted_memories"]) || []
  end

  defp render_delegated_context_block(delegated_context) do
    delegated_context
    |> Enum.map_join("\n", fn memory -> "- #{memory["type"]}: #{memory["content"]}" end)
  end

  defp review_recommended_actions("approved", "research", delegated_context) do
    base = ["Promote the validated research findings into durable operator memory."]

    if delegated_context == [] do
      base
    else
      base ++ ["Keep the delegated research findings attached to the promoted report context."]
    end
  end

  defp review_recommended_actions("approved", _target_kind, delegated_context) do
    base = ["Promote the validated implementation guidance into durable operator memory."]

    if delegated_context == [] do
      base
    else
      base ++ ["Keep the delegated research findings attached to the implementation plan."]
    end
  end

  defp review_recommended_actions(_decision, _target_kind, _delegated_context), do: []

  defp next_work_item_for_agent(agent) do
    WorkItem
    |> where(
      [work_item],
      work_item.status in ["planned", "replayed"] and
        (work_item.assigned_agent_id == ^agent.id or
           (is_nil(work_item.assigned_agent_id) and work_item.assigned_role == ^agent.role))
    )
    |> order_by([work_item], desc: work_item.priority, asc: work_item.inserted_at)
    |> limit(10)
    |> Repo.all()
    |> Enum.map(&get_work_item!(&1.id))
    |> Enum.find(fn work_item ->
      not work_item_remotely_owned?(work_item) and
        not work_item_execution_deferred?(work_item) and
        not role_queue_dispatch_deferred?(work_item)
    end)
    |> case do
      nil -> nil
      work_item -> work_item
    end
  end

  defp normalize_work_item_attrs(attrs, %WorkItem{} = work_item) do
    normalized = Helpers.normalize_string_keys(attrs)

    assigned_role =
      normalized["assigned_role"] ||
        work_item.assigned_role ||
        Autonomy.role_for_kind(normalized["kind"] || work_item.kind)

    base_metadata = normalized["metadata"] || work_item.metadata || %{}

    metadata =
      base_metadata
      |> Helpers.normalize_string_keys()
      |> Map.put_new(
        "side_effect_class",
        side_effect_class_for_kind_and_metadata(
          normalized["kind"] || work_item.kind,
          base_metadata
        )
      )

    normalized
    |> Map.put_new("kind", work_item.kind || "task")
    |> Map.put_new("status", work_item.status || "planned")
    |> Map.put_new(
      "execution_mode",
      work_item.execution_mode || default_execution_mode(assigned_role)
    )
    |> Map.put("assigned_role", Autonomy.normalize_role(assigned_role))
    |> Map.put_new(
      "autonomy_level",
      work_item.autonomy_level || default_autonomy_level(assigned_role)
    )
    |> Map.put_new("approval_stage", work_item.approval_stage || "draft")
    |> Map.put_new("budget", work_item.budget || default_budget())
    |> Map.put_new("input_artifact_refs", work_item.input_artifact_refs || %{})
    |> Map.put_new(
      "required_outputs",
      work_item.required_outputs || default_required_outputs(normalized["kind"] || work_item.kind)
    )
    |> Map.put_new("deliverables", work_item.deliverables || %{})
    |> Map.put_new("result_refs", work_item.result_refs || %{})
    |> Map.put_new("runtime_state", work_item.runtime_state || %{})
    |> Map.put("metadata", metadata)
    |> maybe_resolve_assigned_agent(work_item)
  end

  defp maybe_resolve_assigned_agent(attrs, %WorkItem{} = work_item) do
    assigned_agent_id = attrs["assigned_agent_id"] || work_item.assigned_agent_id

    cond do
      is_integer(assigned_agent_id) ->
        attrs

      assignment_deferred_to_worker_pool?(attrs, work_item) ->
        attrs

      true ->
        case resolve_assigned_agent(attrs) do
          nil ->
            attrs

          %{agent: agent, resolution: resolution} ->
            attrs
            |> Map.put("assigned_agent_id", agent.id)
            |> put_assignment_resolution(resolution)
        end
    end
  end

  defp assignment_deferred_to_worker_pool?(attrs, %WorkItem{} = work_item) do
    metadata = attrs["metadata"] || work_item.metadata || %{}

    metadata["assignment_mode"] == "role_claim" and
      is_nil(attrs["assigned_agent_id"] || work_item.assigned_agent_id)
  end

  defp claimed_work_item_assignment(%WorkItem{} = work_item, %AgentProfile{} = agent) do
    if worker_pool_claimable?(work_item, agent) do
      resolution = worker_claim_resolution(agent, work_item)

      {agent.id, put_assignment_resolution_metadata(work_item.metadata, resolution)}
    else
      {nil, work_item.metadata || %{}}
    end
  end

  defp claimed_work_item_assignment(%WorkItem{} = work_item, _agent) do
    {nil, work_item.metadata || %{}}
  end

  defp worker_pool_claimable?(%WorkItem{} = work_item, %AgentProfile{} = agent) do
    metadata = work_item.metadata || %{}

    metadata["assignment_mode"] == "role_claim" and
      is_nil(work_item.assigned_agent_id) and
      work_item.status in ["planned", "replayed"] and
      is_binary(work_item.assigned_role) and
      work_item.assigned_role == agent.role
  end

  defp worker_claim_resolution(%AgentProfile{} = agent, %WorkItem{} = work_item) do
    %{
      "strategy" => "worker_claim",
      "resolved_agent_id" => agent.id,
      "resolved_agent_name" => agent.name,
      "resolved_agent_slug" => agent.slug,
      "resolved_role" => agent.role,
      "score" => nil,
      "pending_work_items" => nil,
      "claim_scope" => get_in(work_item.metadata || %{}, ["claim_scope"]) || "role_pool",
      "reasons" => ["claimed from role pool", "lease acquired"]
    }
  end

  defp put_assignment_resolution_metadata(metadata, resolution) do
    Map.put(metadata || %{}, "assignment_resolution", resolution)
  end

  defp maybe_put_claimed_agent_id(attrs, nil), do: attrs

  defp maybe_put_claimed_agent_id(attrs, assigned_agent_id),
    do: Map.put(attrs, "assigned_agent_id", assigned_agent_id)

  defp resolve_assigned_agent(attrs) when is_map(attrs) do
    active_agents =
      Agents.list_agents()
      |> Enum.filter(&(&1.status == "active"))

    candidates =
      build_assignment_candidates(active_agents, attrs)

    exact_role_matches =
      Enum.filter(candidates, fn candidate ->
        candidate.match? and candidate.agent.role == attrs["assigned_role"]
      end)

    fallback_matches =
      Enum.filter(candidates, & &1.match?)

    cond do
      exact_role_matches != [] ->
        assignment_choice(exact_role_matches, "role_capability_match")

      fallback_matches != [] ->
        assignment_choice(fallback_matches, "capability_fallback")

      true ->
        nil
    end
  end

  defp build_assignment_candidates([], _attrs), do: []

  defp build_assignment_candidates(agents, attrs) do
    pending_counts = pending_assignment_counts(agents)
    pressure_by_agent_id = assignment_worker_pressure(agents)

    Enum.map(agents, fn agent ->
      build_assignment_candidate(
        agent,
        attrs,
        Map.get(pending_counts, agent.id, 0),
        Map.get(pressure_by_agent_id, agent.id, %{})
      )
    end)
  end

  defp build_assignment_candidate(agent, attrs, pending_count, pressure) do
    profile = capability_profile(agent)
    required_artifact_types = required_assignment_artifact_types(attrs)
    required_delivery_modes = required_assignment_delivery_modes(attrs)
    side_effect_class = required_assignment_side_effect_class(attrs)
    autonomy_level = attrs["autonomy_level"]
    role_match = agent.role == attrs["assigned_role"]
    autonomy_allowed = Autonomy.autonomy_level_allowed?(profile, autonomy_level)
    side_effect_allowed = Autonomy.side_effect_allowed?(profile, side_effect_class)
    artifact_match = capability_supports_artifacts?(profile, required_artifact_types)
    delivery_match = capability_supports_delivery_modes?(profile, required_delivery_modes)
    capacity_posture = pressure[:capacity_posture] || pressure["capacity_posture"]

    active_claimed_count =
      pressure[:active_claimed_count] || pressure["active_claimed_count"] || 0

    shared_role_queue_count =
      pressure[:shared_role_queue_count] || pressure["shared_role_queue_count"] || 0

    match? = autonomy_allowed and side_effect_allowed and artifact_match and delivery_match

    score =
      if match? do
        0.0
        |> maybe_add_score(role_match, 4.0)
        |> maybe_add_score(autonomy_allowed, 2.5)
        |> maybe_add_score(side_effect_allowed, 2.5)
        |> maybe_add_score(artifact_match, 2.0)
        |> maybe_add_score(delivery_match, 2.0)
        |> maybe_add_score(agent.is_default, 0.5)
        |> Kernel.+(assignment_capacity_bonus(capacity_posture))
        |> Kernel.-(min(active_claimed_count, 4) * 0.35)
        |> Kernel.-(min(pending_count, 12) * 0.25)
        |> Kernel.-(min(shared_role_queue_count, 8) * 0.1)
      else
        -1.0
      end

    %{
      agent: agent,
      match?: match?,
      score: score,
      pending_count: pending_count,
      capacity_posture: capacity_posture,
      active_claimed_count: active_claimed_count,
      shared_role_queue_count: shared_role_queue_count,
      role_match: role_match,
      reasons:
        assignment_reasons(
          agent,
          role_match,
          side_effect_class,
          required_delivery_modes,
          required_artifact_types,
          pending_count,
          capacity_posture,
          active_claimed_count,
          shared_role_queue_count
        )
    }
  end

  defp assignment_choice(candidates, strategy) do
    candidate =
      candidates
      |> Enum.sort_by(fn candidate ->
        {-candidate.score, candidate.pending_count, not candidate.agent.is_default,
         candidate.agent.name}
      end)
      |> List.first()

    if candidate do
      %{
        agent: candidate.agent,
        resolution: %{
          "strategy" => strategy,
          "resolved_agent_id" => candidate.agent.id,
          "resolved_agent_name" => candidate.agent.name,
          "resolved_agent_slug" => candidate.agent.slug,
          "resolved_role" => candidate.agent.role,
          "score" => Float.round(candidate.score, 2),
          "pending_work_items" => candidate.pending_count,
          "capacity_posture" => candidate.capacity_posture,
          "active_claimed_count" => candidate.active_claimed_count,
          "shared_role_queue_count" => candidate.shared_role_queue_count,
          "reasons" => candidate.reasons
        }
      }
    end
  end

  defp assignment_worker_pressure([]), do: %{}

  defp assignment_worker_pressure(agents) do
    all_work_items = list_work_items(limit: 500, preload: false)
    role_queue_backlog = build_role_queue_backlog(all_work_items, agents)

    all_work_items
    |> build_worker_pressure(agents, role_queue_backlog)
    |> Map.new(&{&1.agent_id, &1})
  end

  defp pending_assignment_counts(agents) do
    agent_ids =
      agents
      |> Enum.map(& &1.id)
      |> Enum.reject(&is_nil/1)

    if agent_ids == [] do
      %{}
    else
      WorkItem
      |> where(
        [work_item],
        work_item.assigned_agent_id in ^agent_ids and
          work_item.status not in ^@terminal_work_item_statuses
      )
      |> group_by([work_item], work_item.assigned_agent_id)
      |> select([work_item], {work_item.assigned_agent_id, count(work_item.id)})
      |> Repo.all()
      |> Map.new()
    end
  end

  defp required_assignment_artifact_types(attrs) do
    attrs
    |> get_in(["required_outputs", "artifact_types"])
    |> List.wrap()
    |> Enum.reject(&(&1 in [nil, ""]))
  end

  defp required_assignment_delivery_modes(attrs) do
    metadata_delivery = get_in(attrs, ["metadata", "delivery"]) || %{}
    deliverables = attrs["deliverables"] || %{}

    [
      metadata_delivery["mode"],
      deliverables["mode"],
      if(
        present_text?(metadata_delivery["channel"]) or present_text?(deliverables["channel"]),
        do: "channel"
      )
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
  end

  defp required_assignment_side_effect_class(attrs) do
    get_in(attrs, ["metadata", "side_effect_class"]) ||
      side_effect_class_for_kind_and_metadata(attrs["kind"], attrs["metadata"])
  end

  defp capability_supports_artifacts?(profile, required_artifact_types) do
    required_artifact_types == [] or
      MapSet.subset?(
        MapSet.new(required_artifact_types),
        MapSet.new(List.wrap(profile["artifact_types"]))
      )
  end

  defp capability_supports_delivery_modes?(profile, required_delivery_modes) do
    required_delivery_modes == [] or
      MapSet.subset?(
        MapSet.new(required_delivery_modes),
        MapSet.new(List.wrap(profile["delivery_modes"]))
      )
  end

  defp assignment_reasons(
         agent,
         role_match,
         side_effect_class,
         required_delivery_modes,
         required_artifact_types,
         pending_count,
         capacity_posture,
         active_claimed_count,
         shared_role_queue_count
       ) do
    [
      role_match && "exact role match",
      side_effect_class && "supports #{side_effect_class}",
      required_delivery_modes != [] &&
        "supports #{Enum.join(required_delivery_modes, "/")} delivery",
      required_artifact_types != [] &&
        "produces #{Enum.join(required_artifact_types, ", ")}",
      is_binary(capacity_posture) && "pressure #{capacity_posture}",
      active_claimed_count > 0 && "active claims #{active_claimed_count}",
      shared_role_queue_count > 0 && "shared backlog #{shared_role_queue_count}",
      pending_count == 0 && "queue clear",
      pending_count > 0 && "queue #{pending_count}",
      agent.is_default && "default agent"
    ]
    |> Enum.reject(&(&1 in [false, nil, ""]))
  end

  defp assignment_capacity_bonus("idle"), do: 1.25
  defp assignment_capacity_bonus("available"), do: 0.75
  defp assignment_capacity_bonus("busy"), do: -0.5
  defp assignment_capacity_bonus("saturated"), do: -3.0
  defp assignment_capacity_bonus(_posture), do: 0.0

  defp maybe_add_score(score, true, value), do: score + value
  defp maybe_add_score(score, _condition, _value), do: score

  defp put_assignment_resolution(attrs, resolution) do
    metadata = attrs["metadata"] || %{}
    Map.put(attrs, "metadata", Map.put(metadata, "assignment_resolution", resolution))
  end

  defp default_execution_mode("planner"), do: "delegate"
  defp default_execution_mode(_role), do: "execute"

  defp default_autonomy_level("trader"), do: "observe"
  defp default_autonomy_level("builder"), do: "execute_with_promotion"
  defp default_autonomy_level(_role), do: "execute_with_review"

  defp default_budget do
    %{
      "token_budget" => 8_000,
      "tool_budget" => 10,
      "time_budget_minutes" => 20,
      "max_delegation_depth" => 2,
      "max_retries" => 2
    }
  end

  defp default_required_outputs("research"), do: %{"artifact_types" => ["research_report"]}

  defp default_required_outputs("engineering"),
    do: %{"artifact_types" => ["proposal", "code_change_set"]}

  defp default_required_outputs("extension"),
    do: %{"artifact_types" => ["proposal", "patch_bundle"]}

  defp default_required_outputs("review"),
    do: %{"artifact_types" => ["review_report", "decision_ledger"]}

  defp default_required_outputs(_kind), do: %{"artifact_types" => ["note"]}

  defp authorize_work_item(agent, %WorkItem{} = work_item) do
    capability = capability_profile(agent)
    side_effect_class = side_effect_class_for_work_item(work_item)

    with :ok <- validate_autonomy_level(capability, work_item),
         :ok <- validate_time_budget(work_item),
         :ok <- validate_delegation_depth(work_item),
         :ok <- validate_token_budget(agent, work_item),
         :ok <- validate_tool_budget(agent, work_item),
         :ok <- validate_retry_budget(work_item),
         :ok <- validate_side_effect_class(capability, work_item, side_effect_class),
         :ok <- validate_external_delivery_approval(work_item, side_effect_class),
         :ok <- validate_financial_action_mode(work_item, side_effect_class) do
      :ok
    end
  end

  defp validate_time_budget(%WorkItem{} = work_item) do
    limit = get_in(work_item.budget || %{}, ["time_budget_minutes"])
    started_at = work_item_started_at(work_item)

    cond do
      not is_integer(limit) or limit <= 0 ->
        :ok

      is_nil(started_at) ->
        :ok

      DateTime.diff(DateTime.utc_now(), started_at, :minute) < limit ->
        :ok

      true ->
        {:error,
         %{
           "type" => "time_budget",
           "limit_minutes" => limit,
           "elapsed_minutes" => DateTime.diff(DateTime.utc_now(), started_at, :minute),
           "reason" => "work item exceeded its allowed execution window"
         }}
    end
  end

  defp validate_delegation_depth(%WorkItem{execution_mode: "delegate"} = work_item) do
    limit = get_in(work_item.budget || %{}, ["max_delegation_depth"])
    depth = work_item_delegation_depth(work_item)

    cond do
      not is_integer(limit) or limit < 0 ->
        :ok

      depth < limit ->
        :ok

      true ->
        {:error,
         %{
           "type" => "delegation_depth",
           "limit" => limit,
           "current_depth" => depth,
           "reason" => "delegation depth budget is exhausted"
         }}
    end
  end

  defp validate_delegation_depth(_work_item), do: :ok

  defp validate_token_budget(agent, %WorkItem{} = work_item) do
    limit = get_in(work_item.budget || %{}, ["token_budget"])

    cond do
      not is_integer(limit) or limit <= 0 ->
        :ok

      true ->
        usage = Budget.work_item_usage(agent.id, work_item.id)

        if usage.total_tokens < limit do
          :ok
        else
          {:error,
           %{
             "type" => "token_budget",
             "limit_tokens" => limit,
             "used_tokens" => usage.total_tokens,
             "reason" => "work item token budget is exhausted"
           }}
        end
    end
  end

  defp validate_tool_budget(agent, %WorkItem{} = work_item) do
    limit = get_in(work_item.budget || %{}, ["tool_budget"])

    cond do
      not is_integer(limit) or limit <= 0 ->
        :ok

      true ->
        usage = Budget.work_item_usage(agent.id, work_item.id)

        if usage.entries < limit do
          :ok
        else
          {:error,
           %{
             "type" => "tool_budget",
             "limit_calls" => limit,
             "used_calls" => usage.entries,
             "reason" => "work item tool budget is exhausted"
           }}
        end
    end
  end

  defp validate_retry_budget(%WorkItem{} = work_item) do
    limit = get_in(work_item.budget || %{}, ["max_retries"])
    retries = work_item_retry_count(work_item)

    cond do
      not is_integer(limit) or limit < 0 ->
        :ok

      retries < limit ->
        :ok

      true ->
        {:error,
         %{
           "type" => "retry_budget",
           "limit_retries" => limit,
           "used_retries" => retries,
           "reason" => "work item retry budget is exhausted"
         }}
    end
  end

  defp validate_autonomy_level(capability, %WorkItem{} = work_item) do
    if Autonomy.autonomy_level_allowed?(capability, work_item.autonomy_level) do
      :ok
    else
      {:error,
       %{
         "type" => "autonomy_level",
         "requested_level" => work_item.autonomy_level,
         "max_allowed_level" => capability["max_autonomy_level"],
         "reason" => "requested autonomy exceeds the assigned agent capability profile"
       }}
    end
  end

  defp validate_side_effect_class(capability, %WorkItem{} = work_item, side_effect_class) do
    if Autonomy.side_effect_allowed?(capability, side_effect_class) do
      :ok
    else
      {:error,
       %{
         "type" => "side_effect_class",
         "requested_class" => side_effect_class,
         "allowed_classes" => List.wrap(capability["side_effect_classes"]),
         "reason" => "requested side effect is not permitted for the assigned agent role",
         "work_item_kind" => work_item.kind
       }}
    end
  end

  defp validate_external_delivery_approval(%WorkItem{} = work_item, "external_delivery") do
    if work_item.approval_stage in ["validated", "operator_approved", "merge_ready"] do
      :ok
    else
      {:error,
       %{
         "type" => "approval_stage",
         "required_stage" => "validated",
         "current_stage" => work_item.approval_stage,
         "reason" => "external delivery requires a validated or operator-approved work item"
       }}
    end
  end

  defp validate_external_delivery_approval(_work_item, _side_effect_class), do: :ok

  defp validate_financial_action_mode(%WorkItem{metadata: metadata}, "financial_action")
       when is_map(metadata) do
    if metadata["simulation"] == true do
      :ok
    else
      {:error,
       %{
         "type" => "financial_action_locked",
         "required_mode" => "simulation",
         "reason" => "financial autonomy stays simulation-only until explicitly unlocked"
       }}
    end
  end

  defp validate_financial_action_mode(_work_item, _side_effect_class), do: :ok

  defp block_work_item_for_policy(%WorkItem{} = work_item, failure) do
    summary = "Autonomy policy blocked execution: #{policy_failure_summary(failure)}"

    {:ok, artifact} =
      create_artifact(%{
        "work_item_id" => work_item.id,
        "type" => "note",
        "title" => "Policy block",
        "summary" => summary,
        "body" => summary,
        "payload" => %{"policy_failure" => failure},
        "provenance" => %{"source" => "autonomy", "phase" => "policy_gate"},
        "review_status" => "validated"
      })

    artifact_ids =
      (work_item.result_refs || %{})
      |> Map.get("artifact_ids", [])
      |> List.wrap()
      |> Kernel.++([artifact.id])
      |> Enum.uniq()

    {:ok, updated} =
      save_work_item(work_item, %{
        "status" => "failed",
        "result_refs" =>
          (work_item.result_refs || %{})
          |> Map.put("artifact_ids", artifact_ids)
          |> Map.put("policy_failure", failure),
        "runtime_state" =>
          append_history(work_item.runtime_state, "failed", %{
            "phase" => "policy_gate",
            "policy_failure" => failure
          })
      })

    {:processed,
     %{
       status: "failed",
       processed_count: 0,
       action: "policy_blocked",
       work_item: updated,
       artifacts: [artifact],
       error: failure
     }}
  end

  defp append_history(runtime_state, status, details) do
    runtime_state = runtime_state || %{}
    history = List.wrap(runtime_state["history"])

    Map.put(
      runtime_state,
      "history",
      history ++
        [
          %{
            "status" => status,
            "at" => DateTime.utc_now(),
            "details" => details
          }
        ]
    )
  end

  defp next_artifact_version(nil, _type), do: 1

  defp next_artifact_version(work_item_id, type) do
    Repo.one(
      from artifact in Artifact,
        where: artifact.work_item_id == ^work_item_id and artifact.type == ^type,
        select: max(artifact.version)
    )
    |> case do
      nil -> 1
      version -> version + 1
    end
  end

  defp lease_name(work_item_id), do: "work_item:#{work_item_id}"

  defp claimed_work_item_ownership(work_item_id, stage) do
    %{
      "mode" => Coordination.coordination_mode(),
      "lease_name" => lease_name(work_item_id),
      "owner" => Coordination.status().owner,
      "stage" => stage,
      "active" => true,
      "claimed_at" => DateTime.utc_now()
    }
  end

  defp remote_work_item_ownership(lease, stage) do
    %{
      "mode" => Coordination.coordination_mode(),
      "lease_name" => lease.name,
      "owner" => lease.owner,
      "stage" => stage,
      "active" => true,
      "claimed_at" => lease.updated_at || lease.inserted_at
    }
  end

  defp put_work_item_ownership(metadata, ownership) do
    Map.put(metadata || %{}, "ownership", ownership)
  end

  defp side_effect_class_for_work_item(%WorkItem{metadata: metadata, kind: kind}) do
    side_effect_class_for_kind_and_metadata(kind, metadata || %{})
  end

  defp side_effect_class_for_kind_and_metadata(kind, metadata) when is_map(metadata) do
    metadata = Helpers.normalize_string_keys(metadata)

    cond do
      metadata["side_effect_class"] in Autonomy.side_effect_classes() ->
        metadata["side_effect_class"]

      kind == "task" and metadata["task_type"] == "publish_summary" and
          get_in(metadata, ["delivery", "enabled"]) == true ->
        "external_delivery"

      true ->
        side_effect_class_for_kind(kind)
    end
  end

  defp side_effect_class_for_kind_and_metadata(kind, _metadata),
    do: side_effect_class_for_kind(kind)

  defp side_effect_class_for_kind("engineering"), do: "repo_write"
  defp side_effect_class_for_kind("extension"), do: "plugin_install"
  defp side_effect_class_for_kind("trading"), do: "financial_action"
  defp side_effect_class_for_kind(_kind), do: "read_only"

  defp policy_failure_summary(%{"reason" => reason}) when is_binary(reason), do: reason
  defp policy_failure_summary(%{reason: reason}) when is_binary(reason), do: reason
  defp policy_failure_summary(_failure), do: "policy requirements were not satisfied"

  defp budget_policy_failure?(result_refs) when is_map(result_refs) do
    case get_in(result_refs, ["policy_failure", "type"]) do
      type
      when type in [
             "token_budget",
             "time_budget",
             "delegation_depth",
             "tool_budget",
             "retry_budget"
           ] ->
        true

      _ ->
        false
    end
  end

  defp work_item_started_at(%WorkItem{} = work_item) do
    history = get_in(work_item.runtime_state || %{}, ["history"]) || []

    Enum.find_value(history, fn entry ->
      details = entry["details"] || %{}

      if entry["status"] == "running" do
        parse_datetime(details["started_at"])
      end
    end) || work_item.inserted_at
  end

  defp work_item_delegation_depth(%WorkItem{} = work_item) do
    do_work_item_delegation_depth(work_item.parent_work_item_id, 0)
  end

  defp work_item_retry_count(%WorkItem{} = work_item) do
    history = get_in(work_item.runtime_state || %{}, ["history"]) || []

    Enum.count(history, fn entry ->
      entry["status"] in ["failed", "rejected"]
    end)
  end

  defp do_work_item_delegation_depth(nil, depth), do: depth

  defp do_work_item_delegation_depth(parent_id, depth) when is_integer(parent_id) do
    case Repo.get(WorkItem, parent_id) do
      nil -> depth
      %WorkItem{} = item -> do_work_item_delegation_depth(item.parent_work_item_id, depth + 1)
    end
  end

  defp parse_datetime(%DateTime{} = value), do: value

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  defp parse_datetime(_value), do: nil

  defp extension_package_payload(work_item, workspace_snapshot, changed_files) do
    package_name =
      work_item.goal
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")
      |> case do
        "" -> "autonomy-extension-#{work_item.id || "draft"}"
        slug -> slug
      end

    %{
      "extension_package" => %{
        "name" => package_name,
        "package_type" => "hydra_extension",
        "artifact_contract" => ["proposal", "patch_bundle", "review_report"],
        "generated_at" => DateTime.utc_now(),
        "workspace_root" => workspace_snapshot["workspace_root"]
      },
      "compatibility" => %{
        "hydra_runtime" => "post_preview",
        "required_roles" => ["builder", "reviewer", "operator"],
        "required_tools" => ["workspace_patch", "workspace_write"],
        "test_commands" => default_test_commands(work_item)
      },
      "registration" => %{
        "manifest_path" => ".hydra/extensions/#{package_name}.json",
        "install_mode" => "manual_registration",
        "enablement_status" => "approval_required",
        "target_directory" => Path.join(workspace_snapshot["workspace_root"], "priv/extensions")
      },
      "changed_files" => changed_files
    }
  end

  defp approval_action_allowed?(%WorkItem{kind: kind, approval_stage: stage}, requested_action) do
    case {kind, requested_action} do
      {"extension", "enable_extension"} -> stage in ["validated", "operator_approved"]
      {_, "merge_ready"} -> stage in ["validated", "operator_approved"]
      {_, "promote_code_change"} -> stage in ["patch_ready", "validated"]
      {_, "publish_review_report"} -> stage in ["validated", "operator_approved"]
      {_, "promote_work_item"} -> true
      _ -> true
    end
  end

  defp next_approval_stage(%WorkItem{kind: "extension"}, "enable_extension"),
    do: "operator_approved"

  defp next_approval_stage(_work_item, "merge_ready"), do: "merge_ready"
  defp next_approval_stage(_work_item, "promote_code_change"), do: "validated"
  defp next_approval_stage(_work_item, "publish_review_report"), do: "operator_approved"
  defp next_approval_stage(_work_item, "promote_work_item"), do: "operator_approved"
  defp next_approval_stage(work_item, _requested_action), do: work_item.approval_stage

  defp rejection_stage(%WorkItem{approval_stage: "draft"}), do: "proposal_only"
  defp rejection_stage(%WorkItem{} = work_item), do: work_item.approval_stage

  defp approval_result_refs(work_item, record, requested_action, metadata) do
    result_refs = work_item.result_refs || %{}
    approval_ids = Enum.uniq(List.wrap(result_refs["approval_record_ids"]) ++ [record.id])

    result_refs
    |> Map.put("approval_record_ids", approval_ids)
    |> Map.put("last_requested_action", requested_action)
    |> Map.put("last_approval_metadata", metadata)
    |> maybe_put_extension_enablement(work_item, requested_action)
  end

  defp rejection_result_refs(work_item, record, requested_action, metadata) do
    result_refs = work_item.result_refs || %{}
    approval_ids = Enum.uniq(List.wrap(result_refs["approval_record_ids"]) ++ [record.id])

    result_refs
    |> Map.put("approval_record_ids", approval_ids)
    |> Map.put("last_requested_action", requested_action)
    |> Map.put("last_rejection_metadata", metadata)
    |> Map.put("rejected_at", DateTime.utc_now())
  end

  defp maybe_put_extension_enablement(
         result_refs,
         %WorkItem{kind: "extension"},
         "enable_extension"
       ) do
    Map.put(result_refs, "extension_enablement_status", "approved_not_enabled")
  end

  defp maybe_put_extension_enablement(result_refs, _work_item, _requested_action), do: result_refs

  defp promote_artifacts!(%WorkItem{} = work_item, requested_action, parent_record, metadata) do
    desired_status =
      case requested_action do
        "merge_ready" -> "approved"
        "enable_extension" -> "approved"
        _ -> "validated"
      end

    work_item.id
    |> work_item_artifacts()
    |> Enum.each(fn artifact ->
      record_artifact_decision!(
        artifact,
        requested_action,
        "approved",
        "Artifact approved through work item ##{work_item.id}.",
        Map.merge(metadata || %{}, %{
          "parent_work_item_id" => work_item.id,
          "parent_approval_record_id" => parent_record.id
        }),
        parent_record.reviewer_agent_id,
        parent_record.work_item_id || work_item.id,
        desired_status
      )
    end)
  end

  defp reject_artifacts!(%WorkItem{} = work_item, requested_action, parent_record, metadata) do
    work_item.id
    |> work_item_artifacts()
    |> Enum.each(fn artifact ->
      record_artifact_decision!(
        artifact,
        requested_action,
        "rejected",
        "Artifact rejected through work item ##{work_item.id}.",
        Map.merge(metadata || %{}, %{
          "parent_work_item_id" => work_item.id,
          "parent_approval_record_id" => parent_record.id
        }),
        parent_record.reviewer_agent_id,
        parent_record.work_item_id || work_item.id,
        "rejected"
      )
    end)
  end

  defp record_artifact_decision!(
         %Artifact{} = artifact,
         requested_action,
         decision,
         rationale,
         metadata,
         reviewer_agent_id,
         work_item_id,
         review_status_override \\ nil
       ) do
    {:ok, record} =
      create_approval_record(%{
        "subject_type" => "artifact",
        "subject_id" => artifact.id,
        "requested_action" => requested_action,
        "decision" => decision,
        "rationale" => rationale,
        "promoted_at" => if(decision == "approved", do: DateTime.utc_now(), else: nil),
        "reviewer_agent_id" => reviewer_agent_id,
        "work_item_id" => work_item_id || artifact.work_item_id,
        "metadata" => metadata || %{}
      })

    approval_ids =
      artifact.metadata
      |> Kernel.||(%{})
      |> Map.get("approval_record_ids", [])
      |> List.wrap()
      |> Kernel.++([record.id])
      |> Enum.uniq()

    review_status =
      review_status_override || artifact_review_status_for_decision(requested_action, decision)

    {:ok, updated} =
      artifact
      |> Artifact.changeset(%{
        "review_status" => review_status,
        "metadata" =>
          artifact.metadata
          |> Kernel.||(%{})
          |> Map.put("approval_record_ids", approval_ids)
          |> Map.put("last_requested_action", requested_action)
          |> Map.put("last_approval_decision", decision)
      })
      |> Repo.update()

    {updated, record}
  end

  defp maybe_promote_artifact_derived_work_item(
         %WorkItem{kind: kind} = work_item,
         requested_action
       )
       when kind in ["research", "review"] and
              requested_action in [
                "promote_work_item",
                "promote_research_findings",
                "publish_review_report"
              ] do
    artifacts = work_item_artifacts(work_item.id)
    promoted_memory_ids = promote_artifact_derived_outputs!(work_item, artifacts)

    if promoted_memory_ids == [] do
      work_item
    else
      {:ok, updated} =
        save_work_item(work_item, %{
          "result_refs" =>
            (work_item.result_refs || %{})
            |> Map.put("promoted_memory_ids", promoted_memory_ids)
        })

      updated
    end
  end

  defp maybe_promote_artifact_derived_work_item(%WorkItem{} = work_item, _requested_action),
    do: work_item

  defp maybe_complete_publish_review_work_item(
         %WorkItem{} = work_item,
         requested_action,
         approval_record
       )
       when requested_action in ["publish_review_report", "promote_work_item"] do
    metadata = work_item.metadata || %{}

    if metadata["task_type"] == "publish_approval" do
      complete_publish_review!(work_item, approval_record)
    else
      work_item
    end
  end

  defp maybe_complete_publish_review_work_item(
         %WorkItem{} = work_item,
         _requested_action,
         _record
       ),
       do: work_item

  defp maybe_reject_publish_review_work_item(
         %WorkItem{} = work_item,
         requested_action,
         rejection_record
       )
       when requested_action in ["publish_review_report", "promote_work_item"] do
    metadata = work_item.metadata || %{}

    if metadata["task_type"] == "publish_approval" do
      reject_publish_review!(work_item, rejection_record)
    else
      work_item
    end
  end

  defp maybe_reject_publish_review_work_item(
         %WorkItem{} = work_item,
         _requested_action,
         _record
       ),
       do: work_item

  defp complete_publish_review!(%WorkItem{} = review_item, approval_record) do
    publish_item = get_work_item!(review_item.metadata["publish_work_item_id"])
    delivery_brief = get_artifact!(review_item.metadata["delivery_brief_artifact_id"])

    delivery =
      Map.get(delivery_brief.payload || %{}, "delivery") || review_item.metadata["delivery"] ||
        %{}

    delivery_recovery =
      Map.get(delivery_brief.payload || %{}, "delivery_recovery") ||
        review_item.metadata["delivery_recovery"] ||
        %{}

    agent_id = review_item.assigned_agent_id || publish_item.assigned_agent_id
    agent = Agents.get_agent!(agent_id)

    delivery_result =
      execute_publish_delivery(
        agent,
        delivery["channel"],
        delivery["target"],
        delivery_brief.body
      )
      |> maybe_put_delivery_recovery_result(delivery_recovery)

    {:ok, updated_publish_item} =
      save_work_item(publish_item, %{
        "approval_stage" => "operator_approved",
        "result_refs" =>
          (publish_item.result_refs || %{})
          |> Map.put("delivery", delivery_result)
          |> Map.put("last_requested_action", "publish_review_report"),
        "metadata" =>
          (publish_item.metadata || %{})
          |> Map.put("degraded_execution", false),
        "runtime_state" =>
          append_history(publish_item.runtime_state, "approved", %{
            "approved_at" => DateTime.utc_now(),
            "phase" => "publish_review",
            "approval_record_id" => approval_record.id,
            "delivery_status" => delivery_result["status"]
          })
      })

    {updated_brief, _artifact_record} =
      record_artifact_decision!(
        delivery_brief,
        "publish_review_report",
        "approved",
        "Approved degraded delivery through work item ##{review_item.id}.",
        %{
          "review_work_item_id" => review_item.id,
          "publish_work_item_id" => publish_item.id,
          "delivery_status" => delivery_result["status"]
        },
        approval_record.reviewer_agent_id || agent.id,
        review_item.id,
        "approved"
      )

    {:ok, updated_brief} =
      updated_brief
      |> Artifact.changeset(%{
        "payload" =>
          (updated_brief.payload || %{})
          |> Map.put("delivery", delivery_result)
          |> Map.put("review_outcome", %{
            "decision" => "approved",
            "delivery_status" => delivery_result["status"],
            "review_work_item_id" => review_item.id,
            "approval_record_id" => approval_record.id,
            "destination_rationale" =>
              get_in(review_item.metadata || %{}, ["delivery_decision", "destination_rationale"]),
            "confidence_posture" =>
              get_in(review_item.metadata || %{}, ["delivery_decision", "confidence_posture"])
          })
          |> Map.update(
            "delivery_decision_snapshot",
            %{},
            &Map.put(&1, "review_decision", "approved")
          )
      })
      |> Repo.update()

    {:ok, updated_review_item} =
      save_work_item(review_item, %{
        "result_refs" =>
          (review_item.result_refs || %{})
          |> Map.put(
            "artifact_ids",
            Enum.uniq(
              List.wrap((review_item.result_refs || %{})["artifact_ids"]) ++ [updated_brief.id]
            )
          )
          |> Map.put("delivery", delivery_result)
          |> Map.put("linked_publish_work_item_id", updated_publish_item.id)
      })

    updated_review_item
  end

  defp reject_publish_review!(%WorkItem{} = review_item, rejection_record) do
    publish_item = get_work_item!(review_item.metadata["publish_work_item_id"])
    delivery_brief = get_artifact!(review_item.metadata["delivery_brief_artifact_id"])
    delivery = review_item.metadata["delivery"] || %{}

    rejection_result = %{
      "status" => "rejected",
      "channel" => delivery["channel"],
      "target" => delivery["target"],
      "degraded" => true,
      "reason" => "operator_rejected_delivery",
      "reviewed_at" => DateTime.utc_now()
    }

    {:ok, updated_publish_item} =
      save_work_item(publish_item, %{
        "result_refs" =>
          (publish_item.result_refs || %{})
          |> Map.put("delivery", rejection_result)
          |> Map.put("last_requested_action", "publish_review_report")
          |> Map.put("last_rejection_metadata", %{
            "approval_record_id" => rejection_record.id,
            "rationale" => rejection_record.rationale
          }),
        "metadata" =>
          (publish_item.metadata || %{})
          |> Map.put("degraded_execution", true),
        "runtime_state" =>
          append_history(publish_item.runtime_state, "rejected", %{
            "rejected_at" => DateTime.utc_now(),
            "phase" => "publish_review",
            "approval_record_id" => rejection_record.id,
            "delivery_status" => rejection_result["status"]
          })
      })

    {updated_brief, _artifact_record} =
      record_artifact_decision!(
        delivery_brief,
        "publish_review_report",
        "rejected",
        "Rejected degraded delivery through work item ##{review_item.id}.",
        %{
          "review_work_item_id" => review_item.id,
          "publish_work_item_id" => publish_item.id,
          "delivery_status" => rejection_result["status"]
        },
        rejection_record.reviewer_agent_id,
        review_item.id,
        "rejected"
      )

    {:ok, updated_brief} =
      updated_brief
      |> Artifact.changeset(%{
        "payload" =>
          (updated_brief.payload || %{})
          |> Map.put("delivery", rejection_result)
          |> Map.put("review_outcome", %{
            "decision" => "rejected",
            "delivery_status" => rejection_result["status"],
            "review_work_item_id" => review_item.id,
            "approval_record_id" => rejection_record.id,
            "destination_rationale" =>
              get_in(review_item.metadata || %{}, ["delivery_decision", "destination_rationale"]),
            "confidence_posture" =>
              get_in(review_item.metadata || %{}, ["delivery_decision", "confidence_posture"])
          })
          |> Map.update(
            "delivery_decision_snapshot",
            %{},
            &Map.put(&1, "review_decision", "rejected")
          )
      })
      |> Repo.update()

    {:ok, updated_publish_item, follow_up_work_item} =
      maybe_enqueue_rejected_publish_follow_up(
        updated_publish_item,
        updated_brief,
        review_item,
        rejection_record
      )

    {:ok, updated_review_item} =
      save_work_item(review_item, %{
        "result_refs" =>
          (review_item.result_refs || %{})
          |> Map.put("delivery", rejection_result)
          |> Map.put("linked_publish_work_item_id", updated_publish_item.id)
          |> maybe_put_follow_up_work_item_id(follow_up_work_item)
          |> Map.put(
            "artifact_ids",
            Enum.uniq(
              List.wrap((review_item.result_refs || %{})["artifact_ids"]) ++ [updated_brief.id]
            )
          )
      })

    updated_review_item
  end

  defp maybe_enqueue_rejected_publish_follow_up(
         %WorkItem{} = publish_item,
         %Artifact{} = delivery_brief,
         %WorkItem{} = review_item,
         rejection_record
       ) do
    follow_up_context = get_in(publish_item.metadata || %{}, ["follow_up_context"]) || %{}
    rejection_finding = rejected_publish_constraint_finding(publish_item, rejection_record)

    delivery_recovery =
      rejected_publish_delivery_recovery(publish_item, review_item, rejection_record)

    constraint_findings =
      merge_supporting_findings(
        List.wrap(follow_up_context["constraint_findings"]) ++ [rejection_finding]
      )

    constraint_strategy =
      derive_constraint_strategy(constraint_findings)

    supporting_memories =
      merge_supporting_findings(List.wrap(follow_up_context["promoted_findings"]))

    {planner_agent_id, planner_goal, delegated_by_agent_id, work_kind, approval_stage,
     deliverables, required_outputs, review_required, budget} =
      rejected_publish_follow_up_defaults(publish_item)

    follow_up_deliverables =
      apply_delivery_recovery_to_deliverables(deliverables, delivery_recovery)

    {:ok, follow_up_work_item} =
      ensure_follow_up_work_item(
        publish_item,
        "rejected_publish_replan",
        fn item ->
          get_in(item.metadata || %{}, ["publish_review_work_item_id"]) == review_item.id
        end,
        %{
          "kind" => work_kind,
          "goal" => "Re-plan #{planner_goal} after degraded delivery was rejected.",
          "status" => "planned",
          "execution_mode" => "delegate",
          "assigned_role" => "planner",
          "assigned_agent_id" => planner_agent_id,
          "delegated_by_agent_id" => delegated_by_agent_id,
          "parent_work_item_id" => publish_item.id,
          "priority" => max(publish_item.priority, 1),
          "autonomy_level" => publish_item.autonomy_level,
          "approval_stage" => approval_stage,
          "deliverables" => follow_up_deliverables,
          "budget" => budget,
          "required_outputs" => required_outputs,
          "review_required" => review_required,
          "input_artifact_refs" => %{"summary_artifact_id" => delivery_brief.id},
          "metadata" => %{
            "task_type" => "rejected_publish_replan",
            "delegate_goal" => planner_goal,
            "delegate_role" => Autonomy.role_for_kind(work_kind),
            "delivery_brief_artifact_id" => delivery_brief.id,
            "publish_work_item_id" => publish_item.id,
            "publish_review_work_item_id" => review_item.id,
            "delivery_recovery" => delivery_recovery,
            "constraint_findings" => constraint_findings,
            "constraint_strategy" => constraint_strategy,
            "follow_up_context" =>
              build_follow_up_context(
                publish_item,
                supporting_memories,
                delivery_brief,
                constraint_findings,
                constraint_strategy,
                delivery_recovery
              )
          }
        }
      )

    {:ok, updated_publish_item} =
      save_work_item(publish_item, %{
        "result_refs" =>
          append_follow_up_result_refs(publish_item.result_refs, follow_up_work_item, "replan"),
        "runtime_state" =>
          append_history(publish_item.runtime_state, "blocked", %{
            "blocked_at" => DateTime.utc_now(),
            "phase" => "publish_replan",
            "replan_work_item_id" => follow_up_work_item.id,
            "approval_record_id" => rejection_record.id
          })
      })

    {:ok, updated_publish_item, follow_up_work_item}
  end

  defp rejected_publish_follow_up_defaults(%WorkItem{} = publish_item) do
    parent =
      if is_integer(publish_item.parent_work_item_id) do
        get_work_item!(publish_item.parent_work_item_id)
      end

    planner_agent =
      cond do
        match?(%WorkItem{assigned_role: "planner"}, parent) and
            is_integer(parent.assigned_agent_id) ->
          Agents.get_agent!(parent.assigned_agent_id)

        is_integer(publish_item.assigned_agent_id) ->
          publish_item.assigned_agent_id
          |> Agents.get_agent!()
          |> case do
            %{role: "planner"} = agent -> agent
            _other -> planner_fallback_agent()
          end

        true ->
          planner_fallback_agent()
      end

    planner_goal =
      cond do
        match?(%WorkItem{}, parent) and present_text?(parent.goal) ->
          parent.goal

        present_text?(publish_item.goal) ->
          publish_item.goal

        true ->
          "the constrained publish workflow"
      end

    {
      planner_agent && planner_agent.id,
      planner_goal,
      (planner_agent && planner_agent.id) || publish_item.assigned_agent_id,
      if(match?(%WorkItem{}, parent), do: parent.kind, else: "research"),
      if(match?(%WorkItem{}, parent),
        do: parent.approval_stage,
        else: publish_item.approval_stage
      ),
      if(match?(%WorkItem{}, parent), do: parent.deliverables, else: publish_item.deliverables),
      if(match?(%WorkItem{}, parent),
        do: parent.required_outputs,
        else: publish_item.required_outputs
      ),
      if(match?(%WorkItem{}, parent),
        do: parent.review_required,
        else: publish_item.review_required
      ),
      if(match?(%WorkItem{}, parent), do: parent.budget, else: publish_item.budget)
    }
  end

  defp planner_fallback_agent do
    Agents.list_agents()
    |> Enum.find(fn agent -> agent.role == "planner" end)
  end

  defp rejected_publish_constraint_finding(%WorkItem{} = publish_item, rejection_record) do
    rationale =
      rejection_record.rationale
      |> case do
        value when is_binary(value) and value != "" -> value
        _ -> "operator requested a revised summary before external delivery"
      end

    %{
      "memory_id" => nil,
      "type" => "Constraint",
      "content" => "Re-plan #{publish_item.goal} because #{rationale}.",
      "score" => 0.94,
      "summary_reason" => "delivery_rejected",
      "source_work_item_id" => publish_item.id,
      "source_goal" => publish_item.goal,
      "source_kind" => publish_item.kind,
      "source_role" => publish_item.assigned_role,
      "source_artifact_type" => "delivery_review",
      "reasons" => ["constraint_backpressure"],
      "policy_failure_type" => "delivery_rejected"
    }
  end

  defp rejected_publish_delivery_recovery(
         %WorkItem{} = publish_item,
         %WorkItem{} = review_item,
         rejection_record
       ) do
    delivery =
      review_item.metadata["delivery"] ||
        get_in(publish_item.metadata || %{}, ["delivery"]) ||
        %{}

    rationale = rejection_record.rationale || ""
    channel_switch = rejected_publish_recovery_channel(rationale)

    cond do
      rejected_publish_internal_report?(rationale) ->
        %{
          "strategy" => "internal_report_fallback",
          "reason" => "operator_rejected_delivery",
          "rationale" => rationale,
          "recommended_delivery_mode" => "report",
          "recommended_target" => "control-plane",
          "previous_mode" => delivery["mode"] || "channel",
          "previous_channel" => delivery["channel"],
          "previous_target" => delivery["target"],
          "recommended_action" =>
            "Prepare an internal report until the summary is revised and explicitly approved for external delivery."
        }

      present_text?(channel_switch) ->
        %{
          "strategy" => "switch_delivery_channel",
          "reason" => "operator_requested_channel_switch",
          "rationale" => rationale,
          "recommended_delivery_mode" => "channel",
          "recommended_channel" => channel_switch,
          "recommended_target" => delivery["target"],
          "previous_mode" => delivery["mode"] || "channel",
          "previous_channel" => delivery["channel"],
          "previous_target" => delivery["target"],
          "recommended_action" =>
            "Revise the summary and reroute it through #{channel_switch} before requesting delivery approval again."
        }

      true ->
        %{
          "strategy" => "revise_and_retry_channel",
          "reason" => "operator_requested_revision",
          "rationale" => rationale,
          "recommended_delivery_mode" => "channel",
          "recommended_channel" => delivery["channel"],
          "recommended_target" => delivery["target"],
          "previous_mode" => delivery["mode"] || "channel",
          "previous_channel" => delivery["channel"],
          "previous_target" => delivery["target"],
          "recommended_action" =>
            "Revise the summary, strengthen the supporting evidence, and retry the same delivery path only after explicit approval."
        }
    end
  end

  defp rejected_publish_internal_report?(rationale) do
    rationale =
      rationale
      |> to_string()
      |> String.downcase()

    Enum.any?(
      ["internal", "control plane", "control-plane", "report"],
      &String.contains?(rationale, &1)
    )
  end

  defp rejected_publish_recovery_channel(rationale) do
    rationale =
      rationale
      |> to_string()
      |> String.downcase()

    cond do
      String.contains?(rationale, "slack") -> "slack"
      String.contains?(rationale, "discord") -> "discord"
      String.contains?(rationale, "telegram") -> "telegram"
      String.contains?(rationale, "webchat") -> "webchat"
      true -> nil
    end
  end

  defp maybe_put_follow_up_work_item_id(result_refs, %WorkItem{} = follow_up_work_item) do
    Map.put(result_refs, "linked_follow_up_work_item_id", follow_up_work_item.id)
  end

  defp maybe_put_follow_up_work_item_id(result_refs, _follow_up_work_item), do: result_refs

  defp maybe_promote_artifact_derived_artifact(%Artifact{type: type} = artifact, requested_action)
       when type in ["research_report", "review_report", "decision_ledger"] and
              requested_action in [
                "promote_artifact",
                "publish_research_report",
                "publish_review_report"
              ] do
    work_item = get_work_item!(artifact.work_item_id)
    promoted_memory_ids = promote_artifact_derived_outputs!(work_item, [artifact])

    if promoted_memory_ids == [] do
      artifact
    else
      {:ok, _updated} =
        save_work_item(work_item, %{
          "result_refs" =>
            (work_item.result_refs || %{})
            |> Map.put(
              "promoted_memory_ids",
              Enum.uniq(
                List.wrap(get_in(work_item.result_refs || %{}, ["promoted_memory_ids"])) ++
                  promoted_memory_ids
              )
            )
        })

      artifact
    end
  end

  defp maybe_promote_artifact_derived_artifact(%Artifact{} = artifact, _requested_action),
    do: artifact

  defp promote_artifact_derived_outputs!(%WorkItem{} = work_item, artifacts) do
    promoted_memory_ids =
      artifacts
      |> Enum.flat_map(&promote_memories_from_artifact(work_item, &1))
      |> Enum.uniq()

    if promoted_memory_ids != [] and is_integer(work_item.assigned_agent_id) do
      Agents.refresh_agent_bulletin!(work_item.assigned_agent_id)
    end

    promoted_memory_ids
  end

  defp promote_memories_from_artifact(_work_item, %Artifact{type: type})
       when type not in ["research_report", "review_report", "decision_ledger"],
       do: []

  defp promote_memories_from_artifact(%WorkItem{} = work_item, %Artifact{} = artifact) do
    target_agent_id = artifact_memory_agent_id(work_item)

    if is_nil(target_agent_id) do
      []
    else
      artifact_memory_blueprints(artifact.type, artifact.payload || %{})
      |> Enum.with_index()
      |> Enum.flat_map(fn {memory_attrs, index} ->
        promotion_key =
          memory_attrs["promotion_key"] ||
            "#{memory_attrs["promotion_slot"]}:#{memory_attrs["type"]}:#{memory_attrs["content"]}"

        existing =
          Memory.list_memories(agent_id: target_agent_id, limit: 500)
          |> Enum.find(fn entry ->
            metadata = entry.metadata || %{}

            metadata["source_artifact_id"] == artifact.id or
              (metadata["source_work_item_id"] == work_item.id and
                 metadata["promotion_key"] == promotion_key)
          end)

        if existing do
          [existing.id]
        else
          {:ok, memory} =
            Memory.create_memory(%{
              agent_id: target_agent_id,
              type: memory_attrs["type"],
              status: "active",
              content: memory_attrs["content"],
              importance: memory_attrs["importance"],
              metadata:
                memory_attrs["metadata"]
                |> Map.put("source_work_item_id", work_item.id)
                |> Map.put("source_artifact_id", artifact.id)
                |> Map.put("source_artifact_type", artifact.type)
                |> Map.put("promotion_slot", memory_attrs["promotion_slot"])
                |> Map.put("promotion_key", promotion_key)
                |> Map.put("promotion_index", index)
                |> Map.put("research_question", work_item.goal),
              last_seen_at: DateTime.utc_now()
            })

          [memory.id]
        end
      end)
    end
  end

  defp artifact_memory_blueprints("research_report", payload) do
    payload
    |> Map.get("claims", [])
    |> Enum.take(3)
    |> Enum.map(fn claim ->
      artifact_memory_blueprint(
        "Fact",
        claim,
        "claims",
        0.77,
        payload,
        %{
          "expires_at" => DateTime.add(DateTime.utc_now(), 30 * 24 * 60 * 60, :second),
          "promotion_reason" => "approved_research_claim"
        }
      )
    end)
  end

  defp artifact_memory_blueprints("decision_ledger", payload) do
    decision_memories =
      case decision_memory_summary(payload) do
        nil ->
          []

        summary ->
          [
            artifact_memory_blueprint(
              "Decision",
              summary,
              "decision_summary",
              0.82,
              payload,
              %{"promotion_reason" => "approved_research_decision"}
            )
          ]
      end

    action_memories =
      payload
      |> Map.get("recommended_actions", [])
      |> Enum.take(3)
      |> Enum.map(fn action ->
        artifact_memory_blueprint(
          "Goal",
          action,
          "recommended_actions",
          0.72,
          payload,
          %{"promotion_reason" => "approved_research_action"}
        )
      end)

    open_question_memories =
      payload
      |> Map.get("open_questions", [])
      |> Enum.reject(&generic_open_question?/1)
      |> Enum.take(2)
      |> Enum.map(fn question ->
        artifact_memory_blueprint(
          "Todo",
          "Investigate: #{question}",
          "open_questions",
          0.61,
          payload,
          %{"promotion_reason" => "approved_research_follow_up"}
        )
      end)

    decision_memories ++ action_memories ++ open_question_memories
  end

  defp artifact_memory_blueprints("review_report", payload) do
    decision_memory =
      case review_decision_summary(payload) do
        nil ->
          []

        summary ->
          [
            artifact_memory_blueprint(
              "Decision",
              summary,
              "review_decision",
              0.8,
              payload,
              %{"promotion_reason" => "approved_review_decision"}
            )
          ]
      end

    follow_up_memories =
      payload
      |> Map.get("recommended_actions", [])
      |> Enum.take(2)
      |> Enum.map(fn action ->
        artifact_memory_blueprint(
          "Goal",
          action,
          "review_actions",
          0.69,
          payload,
          %{"promotion_reason" => "approved_review_action"}
        )
      end)

    decision_memory ++ follow_up_memories
  end

  defp artifact_memory_blueprints(_artifact_type, _payload), do: []

  defp finalized_child_findings(children) do
    merge_supporting_findings(
      finalized_child_memories(children) ++ constrained_child_findings(children)
    )
  end

  defp finalized_child_memories(children) do
    children
    |> Enum.flat_map(fn child ->
      child.id
      |> work_item_artifacts()
      |> Enum.flat_map(&finalized_child_artifact_findings(child, &1))
    end)
  end

  defp constrained_child_findings(children) do
    children
    |> Enum.flat_map(&child_constraint_findings/1)
  end

  defp child_constraint_findings(%WorkItem{} = child) do
    case get_in(child.result_refs || %{}, ["policy_failure"]) do
      failure when is_map(failure) ->
        [constraint_child_finding(child, failure)]

      _ when child.status == "failed" ->
        [
          generic_child_constraint_finding(
            child,
            "re-plan the delegated work because it failed before completion",
            "execution_failed"
          )
        ]

      _ when child.status == "canceled" ->
        [
          generic_child_constraint_finding(
            child,
            "re-plan the delegated work because it was canceled before completion",
            "execution_canceled"
          )
        ]

      _ ->
        []
    end
  end

  defp constraint_child_finding(%WorkItem{} = child, failure) do
    failure = Helpers.normalize_string_keys(failure)
    failure_type = failure["type"] || "policy_failure"

    %{
      "memory_id" => nil,
      "type" => "Constraint",
      "content" => "Re-plan #{child.goal} because #{policy_failure_summary(failure)}.",
      "score" => 1.0,
      "summary_reason" => failure_type,
      "source_work_item_id" => child.id,
      "source_goal" => child.goal,
      "source_kind" => child.kind,
      "source_role" => child.assigned_role,
      "source_artifact_type" => "policy_failure",
      "reasons" => ["constraint_backpressure"],
      "policy_failure_type" => failure_type
    }
  end

  defp generic_child_constraint_finding(%WorkItem{} = child, message, reason) do
    %{
      "memory_id" => nil,
      "type" => "Constraint",
      "content" => "Re-plan #{child.goal} because #{message}.",
      "score" => 0.75,
      "summary_reason" => reason,
      "source_work_item_id" => child.id,
      "source_goal" => child.goal,
      "source_kind" => child.kind,
      "source_role" => child.assigned_role,
      "source_artifact_type" => "work_item_status",
      "reasons" => ["constraint_backpressure"]
    }
  end

  defp derive_constraint_strategy(constraint_findings) do
    constraint_findings
    |> Enum.map(&constraint_strategy_line/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.join(" ")
    |> case do
      "" ->
        "Reduce scope, preserve the highest-value finding first, and ask for review if the constrained path is still unsafe."

      strategy ->
        strategy
    end
  end

  defp constraint_strategy_line(%{"policy_failure_type" => "token_budget"}) do
    "Keep scope narrow, reuse the evidence already captured, and produce the shortest useful synthesis."
  end

  defp constraint_strategy_line(%{"policy_failure_type" => "tool_budget"}) do
    "Avoid new tool calls, rely on existing artifacts and memory, and prefer synthesis over fresh collection."
  end

  defp constraint_strategy_line(%{"policy_failure_type" => "retry_budget"}) do
    "Do not repeat the same failing approach; change strategy or escalate for review."
  end

  defp constraint_strategy_line(%{"policy_failure_type" => "time_budget"}) do
    "Prefer the fastest viable path and summarize known evidence instead of gathering more."
  end

  defp constraint_strategy_line(%{"policy_failure_type" => "delegation_depth"}) do
    "Do not delegate further; synthesize the best answer at the current planner level."
  end

  defp constraint_strategy_line(%{"summary_reason" => "execution_failed"}) do
    "Retry with a simpler plan and preserve the highest-value partial output first."
  end

  defp constraint_strategy_line(%{"summary_reason" => "execution_canceled"}) do
    "Resume with a narrower plan and keep the work restartable."
  end

  defp constraint_strategy_line(%{"summary_reason" => "delivery_rejected"}) do
    "Strengthen confidence with clearer evidence, revise the summary for review, and avoid external delivery until the revised brief is explicitly approved."
  end

  defp constraint_strategy_line(_finding), do: nil

  defp degraded_execution?(%WorkItem{} = work_item) do
    delegated_context_memories(work_item)
    |> Enum.any?(fn memory ->
      memory["type"] == "Constraint" or
        "delegated constraint" in List.wrap(memory["reasons"]) or
        "delegated constraint strategy" in List.wrap(memory["reasons"])
    end)
  end

  defp degraded_delivery_brief?(follow_up_metadata, summary_payload, findings) do
    Map.get(follow_up_metadata || %{}, "needs_replan") == true or
      present_text?(Map.get(follow_up_metadata || %{}, "constraint_strategy")) or
      present_text?(get_in(follow_up_metadata || %{}, ["delivery_recovery", "strategy"])) or
      present_text?(summary_payload["constraint_strategy"]) or
      present_text?(get_in(summary_payload || %{}, ["delivery_recovery", "strategy"])) or
      List.wrap(summary_payload["constraint_findings"]) != [] or
      Enum.any?(List.wrap(findings), &((&1["type"] || &1[:type]) == "Constraint"))
  end

  defp resolved_delivery_config(delivery, delivery_recovery) do
    mode =
      delivery_recovery["recommended_delivery_mode"] ||
        delivery["mode"] ||
        "report"

    channel =
      if mode == "channel" do
        delivery_recovery["recommended_channel"] || delivery["channel"]
      end

    target =
      cond do
        mode == "channel" ->
          delivery_recovery["recommended_target"] || delivery["target"]

        present_text?(delivery_recovery["recommended_target"]) ->
          delivery_recovery["recommended_target"]

        true ->
          "control-plane"
      end

    %{"mode" => mode, "channel" => channel, "target" => target}
  end

  defp internal_report_recovery?(delivery_recovery) do
    strategy = delivery_recovery["strategy"]
    recommended_mode = delivery_recovery["recommended_delivery_mode"]

    strategy in ["internal_report_fallback", "report_only_recovery"] or
      (present_text?(recommended_mode) and recommended_mode != "channel")
  end

  defp maybe_put_delivery_recovery_result(result, delivery_recovery)
       when is_map(delivery_recovery) and map_size(delivery_recovery) > 0 do
    Map.put(result, "recovery", delivery_recovery)
  end

  defp maybe_put_delivery_recovery_result(result, _delivery_recovery), do: result

  defp delegated_constraint_strategy(delegated_context) do
    delegated_context
    |> List.wrap()
    |> Enum.find_value(fn memory ->
      if "delegated constraint strategy" in List.wrap(memory["reasons"]) do
        memory["content"]
      end
    end)
  end

  defp adjusted_confidence(value, true) when is_float(value), do: min(value, 0.52)
  defp adjusted_confidence(value, true) when is_integer(value), do: min(value * 1.0, 0.52)
  defp adjusted_confidence(value, _degraded), do: value

  defp maybe_put_constraint_strategy(metadata, value) when is_binary(value) and value != "",
    do: Map.put(metadata, "constraint_strategy", value)

  defp maybe_put_constraint_strategy(metadata, _value), do: metadata

  defp merge_supporting_findings(findings) do
    findings
    |> Enum.uniq_by(fn finding ->
      {
        finding["source_work_item_id"],
        finding["source_artifact_type"],
        finding["type"],
        finding["content"]
      }
    end)
    |> Enum.sort_by(fn finding ->
      {-(finding["score"] || 0.0), finding["source_work_item_id"] || 0, finding["content"] || ""}
    end)
    |> Enum.take(8)
  end

  defp finalized_child_artifact_findings(child, %Artifact{} = artifact) do
    payload = artifact.payload || %{}
    source_role = payload["memory_origin_role"] || child.assigned_role
    score = artifact.confidence || 0.0

    summary_finding =
      case artifact.summary do
        summary when is_binary(summary) and summary != "" ->
          [
            finalized_child_finding(
              child,
              artifact,
              inferred_artifact_finding_type(artifact.type),
              summary,
              score,
              source_role
            )
          ]

        _ ->
          []
      end

    claim_findings =
      payload
      |> Map.get("claims", [])
      |> Enum.take(2)
      |> Enum.map(fn claim ->
        finalized_child_finding(child, artifact, "Claim", claim, score, source_role)
      end)

    action_findings =
      payload
      |> Map.get("recommended_actions", [])
      |> Enum.take(2)
      |> Enum.map(fn action ->
        finalized_child_finding(child, artifact, "Goal", action, score, source_role)
      end)

    delivery_findings =
      delivery_artifact_findings(child, artifact, payload, score, source_role)

    summary_finding ++ claim_findings ++ action_findings ++ delivery_findings
  end

  defp finalized_child_finding(child, artifact, type, content, score, source_role) do
    %{
      "memory_id" => nil,
      "type" => type,
      "content" => content,
      "score" => score,
      "summary_reason" => artifact.type,
      "source_work_item_id" => child.id,
      "source_goal" => child.goal,
      "source_kind" => child.kind,
      "source_role" => source_role,
      "source_artifact_type" => artifact.type,
      "reasons" => []
    }
  end

  defp delivery_artifact_findings(child, artifact, payload, score, source_role) do
    if artifact.type == "delivery_brief" do
      decision_snapshot = payload["delivery_decision_snapshot"] || %{}

      [
        payload["publish_objective"] &&
          finalized_child_finding(
            child,
            artifact,
            "DeliveryDecision",
            payload["publish_objective"],
            score,
            source_role
          ),
        payload["destination_rationale"] &&
          finalized_child_finding(
            child,
            artifact,
            "DeliveryDecision",
            payload["destination_rationale"],
            score,
            source_role
          ),
        decision_snapshot["prior_summary"] &&
          finalized_child_finding(
            child,
            artifact,
            "DeliveryDecision",
            decision_snapshot["prior_summary"],
            score,
            source_role
          ),
        decision_snapshot["comparison_summary"] &&
          finalized_child_finding(
            child,
            artifact,
            "DeliveryDecision",
            decision_snapshot["comparison_summary"],
            score,
            source_role
          ),
        get_in(payload || %{}, ["review_outcome", "decision"]) &&
          finalized_child_finding(
            child,
            artifact,
            "DeliveryReview",
            "Delivery review #{get_in(payload || %{}, ["review_outcome", "decision"])} with #{get_in(payload || %{}, ["review_outcome", "confidence_posture"]) || "unknown"} posture.",
            score,
            source_role
          )
      ]
      |> Enum.reject(&is_nil/1)
    else
      []
    end
  end

  defp delivery_decision_findings(findings) do
    findings
    |> List.wrap()
    |> Enum.filter(&delivery_decision_finding?/1)
  end

  defp delivery_decision_finding?(%{"type" => type})
       when type in ["DeliveryDecision", "DeliveryReview"],
       do: true

  defp delivery_decision_finding?(%{"source_artifact_type" => "delivery_brief"}), do: true
  defp delivery_decision_finding?(_finding), do: false

  defp delivery_decision_memories(memories) do
    memories
    |> List.wrap()
    |> Enum.filter(fn memory ->
      memory["source_artifact_type"] == "delivery_brief" or
        memory["type"] in ["DeliveryDecision", "DeliveryReview"]
    end)
    |> Enum.take(3)
  end

  defp build_delivery_decision_snapshot(current_entries, prior_entries, attrs) do
    current_entries = List.wrap(current_entries)
    prior_entries = List.wrap(prior_entries)
    current_summary = delivery_decision_summary(List.first(current_entries))
    prior_summary = delivery_decision_summary(List.first(prior_entries))

    %{
      "decision_scope" => Keyword.get(attrs, :decision_scope),
      "decision_basis" => Keyword.get(attrs, :decision_basis),
      "current_summary" => current_summary,
      "prior_summary" => prior_summary,
      "comparison_summary" =>
        delivery_decision_comparison_summary(current_summary, prior_summary),
      "current_count" => length(current_entries),
      "prior_count" => length(prior_entries)
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp maybe_put_publish_prior_summary(snapshot, delivery_recovery, delivery) do
    fallback =
      publish_prior_summary_from_recovery(delivery_recovery) ||
        publish_prior_summary_from_delivery(delivery)

    case {snapshot["prior_summary"], fallback} do
      {nil, value} when is_binary(value) and value != "" ->
        Map.put(snapshot, "prior_summary", value)

      _ ->
        snapshot
    end
  end

  defp publish_prior_summary_from_recovery(delivery_recovery) when is_map(delivery_recovery) do
    previous_mode = delivery_recovery["previous_mode"]
    previous_channel = delivery_recovery["previous_channel"]
    previous_target = delivery_recovery["previous_target"]

    cond do
      is_binary(previous_channel) and previous_channel != "" and is_binary(previous_target) and
          previous_target != "" ->
        "Previous delivery path: #{previous_channel} -> #{previous_target}"

      is_binary(previous_channel) and previous_channel != "" ->
        "Previous delivery path: #{previous_channel}"

      is_binary(previous_mode) and previous_mode != "" and is_binary(previous_target) and
          previous_target != "" ->
        "Previous delivery path: #{previous_mode} -> #{previous_target}"

      is_binary(previous_mode) and previous_mode != "" ->
        "Previous delivery path: #{previous_mode}"

      true ->
        nil
    end
  end

  defp publish_prior_summary_from_recovery(_delivery_recovery), do: nil

  defp publish_prior_summary_from_delivery(delivery) when is_map(delivery) do
    mode = delivery["mode"]
    channel = delivery["channel"]
    target = delivery["target"]

    cond do
      is_binary(channel) and channel != "" and is_binary(target) and target != "" ->
        "Previous delivery path: #{channel} -> #{target}"

      is_binary(channel) and channel != "" ->
        "Previous delivery path: #{channel}"

      is_binary(mode) and mode != "" and is_binary(target) and target != "" ->
        "Previous delivery path: #{mode} -> #{target}"

      is_binary(mode) and mode != "" ->
        "Previous delivery path: #{mode}"

      true ->
        nil
    end
  end

  defp publish_prior_summary_from_delivery(_delivery), do: nil

  defp delivery_decision_summary(%{"content" => value}) when is_binary(value) and value != "",
    do: value

  defp delivery_decision_summary(_entry), do: nil

  defp delivery_decision_comparison_summary(current, prior)
       when is_binary(current) and current != "" and is_binary(prior) and prior != "" do
    if current == prior do
      "Retained the prior delivery guidance."
    else
      "Shifted delivery guidance from the prior path to the current recommendation."
    end
  end

  defp delivery_decision_comparison_summary(current, _prior)
       when is_binary(current) and current != "" do
    "Established delivery guidance for this artifact."
  end

  defp delivery_decision_comparison_summary(_current, _prior), do: nil

  defp inferred_artifact_finding_type("decision_ledger"), do: "Decision"
  defp inferred_artifact_finding_type("review_report"), do: "Decision"
  defp inferred_artifact_finding_type("research_report"), do: "Finding"
  defp inferred_artifact_finding_type("delivery_brief"), do: "DeliveryDecision"
  defp inferred_artifact_finding_type(_artifact_type), do: "Finding"

  defp artifact_memory_blueprint(type, content, slot, importance, payload, metadata) do
    scope = payload["scope"] || artifact_scope(payload)

    %{
      "type" => type,
      "content" => content,
      "importance" => importance,
      "promotion_slot" => slot,
      "promotion_key" => "#{slot}:#{type}:#{content}",
      "metadata" =>
        metadata
        |> Map.put("promotion_state", "durable")
        |> Map.put("memory_scope", "artifact_derived")
        |> Map.put("memory_origin_role", payload["memory_origin_role"] || "researcher")
        |> Map.put("confidence", payload["confidence"])
        |> Map.put("scope", scope)
    }
  end

  defp review_decision_summary(payload) do
    cond do
      payload["decision"] == "approved" and present_text?(payload["summary"]) ->
        payload["summary"]

      payload["decision"] == "approved" and present_text?(payload["target_goal"]) ->
        "Validated review for #{payload["target_goal"]}"

      true ->
        nil
    end
  end

  defp artifact_scope(%{"decision_type" => "review"}), do: "autonomous review"
  defp artifact_scope(_payload), do: "autonomous research"

  defp artifact_memory_agent_id(%WorkItem{} = work_item) do
    work_item.assigned_agent_id ||
      get_in(work_item.metadata || %{}, ["processor_agent_id"]) ||
      get_in(work_item.metadata || %{}, ["reviewer_agent_id"]) ||
      work_item.delegated_by_agent_id
  end

  defp decision_memory_summary(payload) do
    cond do
      present_text?(payload["summary"]) ->
        payload["summary"]

      present_text?(List.first(payload["recommended_actions"] || [])) ->
        List.first(payload["recommended_actions"])

      present_text?(payload["question"]) ->
        "Research decision: #{payload["question"]}"

      true ->
        nil
    end
  end

  defp generic_open_question?(question) when is_binary(question) do
    String.contains?(String.downcase(question), "what new external evidence should be gathered")
  end

  defp generic_open_question?(_question), do: false

  defp present_text?(value) when is_binary(value), do: String.trim(value) != ""
  defp present_text?(_value), do: false

  defp artifact_review_status_for_decision(_requested_action, "rejected"), do: "rejected"
  defp artifact_review_status_for_decision("merge_ready", "approved"), do: "approved"
  defp artifact_review_status_for_decision("enable_extension", "approved"), do: "approved"
  defp artifact_review_status_for_decision("publish_review_report", "approved"), do: "approved"
  defp artifact_review_status_for_decision("publish_research_report", "approved"), do: "approved"
  defp artifact_review_status_for_decision(_requested_action, "approved"), do: "validated"

  defp maybe_enqueue_publish_follow_up(
         %WorkItem{} = parent,
         %Artifact{} = summary_artifact,
         supporting_memories
       ) do
    deliverables = parent.deliverables || %{}

    if parent.assigned_role == "planner" and deliverables["publish_summary"] == true do
      follow_up_context = build_follow_up_context(parent, supporting_memories, summary_artifact)
      delivery_recovery = follow_up_context["delivery_recovery"] || %{}

      resolved_deliverables =
        apply_delivery_recovery_to_deliverables(deliverables, delivery_recovery)

      goal = publish_follow_up_goal(parent, resolved_deliverables, delivery_recovery)

      {:ok, follow_up_work_item} =
        ensure_follow_up_work_item(
          parent,
          "publish_summary",
          fn item ->
            get_in(item.metadata || %{}, ["summary_artifact_id"]) == summary_artifact.id
          end,
          %{
            "kind" => "task",
            "goal" => goal,
            "status" => "planned",
            "execution_mode" => "execute",
            "assigned_role" => resolved_deliverables["assigned_role"] || "operator",
            "assigned_agent_id" => resolved_deliverables["assigned_agent_id"],
            "delegated_by_agent_id" => parent.assigned_agent_id || parent.delegated_by_agent_id,
            "parent_work_item_id" => parent.id,
            "priority" => max(parent.priority - 1, 0),
            "autonomy_level" => parent.autonomy_level,
            "approval_stage" => "validated",
            "deliverables" => resolved_deliverables,
            "input_artifact_refs" => %{"summary_artifact_id" => summary_artifact.id},
            "required_outputs" => %{"artifact_types" => ["delivery_brief"]},
            "metadata" => %{
              "task_type" => "publish_summary",
              "summary_artifact_id" => summary_artifact.id,
              "delivery" => %{
                "enabled" => resolved_deliverables["enabled"] == true,
                "mode" => resolved_deliverables["mode"] || "report",
                "channel" => resolved_deliverables["channel"],
                "target" => resolved_deliverables["target"]
              },
              "delivery_recovery" => delivery_recovery,
              "follow_up_context" => follow_up_context
            }
          }
        )

      {:ok, updated_parent} =
        save_work_item(parent, %{
          "result_refs" =>
            append_follow_up_result_refs(parent.result_refs, follow_up_work_item, "publish")
        })

      {:ok, updated_parent, follow_up_work_item}
    else
      {:ok, parent, nil}
    end
  end

  defp maybe_enqueue_replan_follow_up(
         %WorkItem{} = parent,
         %Artifact{} = summary_artifact,
         supporting_memories,
         constraint_findings
       ) do
    if parent.assigned_role == "planner" and constraint_findings != [] do
      constraint_strategy = derive_constraint_strategy(constraint_findings)

      follow_up_context =
        build_follow_up_context(
          parent,
          supporting_memories,
          summary_artifact,
          constraint_findings,
          constraint_strategy
        )

      delivery_recovery = follow_up_context["delivery_recovery"] || %{}

      resolved_deliverables =
        apply_delivery_recovery_to_deliverables(parent.deliverables, delivery_recovery)

      {:ok, follow_up_work_item} =
        ensure_follow_up_work_item(
          parent,
          "constraint_replan",
          fn item ->
            get_in(item.metadata || %{}, ["summary_artifact_id"]) == summary_artifact.id
          end,
          %{
            "kind" => parent.kind,
            "goal" => "Re-plan #{parent.goal} within the current autonomy constraints.",
            "status" => "planned",
            "execution_mode" => "delegate",
            "assigned_role" => "planner",
            "assigned_agent_id" => parent.assigned_agent_id,
            "delegated_by_agent_id" => parent.assigned_agent_id || parent.delegated_by_agent_id,
            "parent_work_item_id" => parent.id,
            "priority" => max(parent.priority - 1, 0),
            "autonomy_level" => parent.autonomy_level,
            "approval_stage" => parent.approval_stage,
            "deliverables" => resolved_deliverables,
            "input_artifact_refs" => %{"summary_artifact_id" => summary_artifact.id},
            "required_outputs" => parent.required_outputs,
            "review_required" => parent.review_required,
            "metadata" => %{
              "task_type" => "constraint_replan",
              "delegate_goal" => parent.goal,
              "summary_artifact_id" => summary_artifact.id,
              "constraint_findings" => Enum.take(constraint_findings, 5),
              "constraint_strategy" => constraint_strategy,
              "delivery_recovery" => delivery_recovery,
              "follow_up_context" => follow_up_context
            }
          }
        )

      {:ok, updated_parent} =
        save_work_item(parent, %{
          "result_refs" =>
            append_follow_up_result_refs(parent.result_refs, follow_up_work_item, "replan")
        })

      {:ok, updated_parent, follow_up_work_item}
    else
      {:ok, parent, nil}
    end
  end

  defp publish_follow_up_goal(parent, resolved_deliverables, delivery_recovery) do
    resolved_deliverables = Helpers.normalize_string_keys(resolved_deliverables || %{})
    delivery_recovery = Helpers.normalize_string_keys(delivery_recovery || %{})
    channel = resolved_deliverables["channel"]
    target = resolved_deliverables["target"]

    cond do
      present_text?(resolved_deliverables["goal"]) ->
        resolved_deliverables["goal"]

      delivery_recovery["strategy"] == "switch_delivery_channel" and present_text?(channel) ->
        "Revise and publish the finalized summary for #{parent.goal} through #{channel}#{publish_target_suffix(target)}"

      delivery_recovery["strategy"] == "internal_report_fallback" ->
        "Prepare an internal operator report for #{parent.goal}#{publish_target_suffix(target)}"

      delivery_recovery["strategy"] == "revise_and_retry_channel" and present_text?(channel) ->
        "Revise and retry the finalized summary for #{parent.goal} through #{channel}#{publish_target_suffix(target)}"

      present_text?(channel) ->
        "Publish the finalized summary for #{parent.goal} through #{channel}#{publish_target_suffix(target)}"

      true ->
        "Publish the finalized summary for #{parent.goal}"
    end
  end

  defp publish_target_suffix(target) when is_binary(target) and target != "", do: " to #{target}"
  defp publish_target_suffix(_target), do: ""

  defp finalize_parent_attrs(
         claimed,
         children,
         summary_artifact,
         artifact_ids,
         supporting_memories,
         constraint_findings
       ) do
    approval_records = approval_records_for_subject("work_item", claimed.id)
    latest_decision = approval_records |> List.first() |> then(&(&1 && &1.decision))

    follow_up_context =
      build_follow_up_context(claimed, supporting_memories, summary_artifact, constraint_findings)

    delegation_batch = build_delegation_batch_snapshot(claimed, children)

    {status, approval_stage} =
      case latest_decision do
        "rejected" -> {"failed", claimed.approval_stage}
        "approved" -> {"completed", "validated"}
        _ -> {"completed", claimed.approval_stage}
      end

    %{
      "status" => status,
      "approval_stage" => approval_stage,
      "result_refs" => %{
        "artifact_ids" => Enum.uniq([summary_artifact.id | artifact_ids]),
        "child_work_item_ids" => Enum.map(children, & &1.id),
        "approval_record_ids" => Enum.map(approval_records, & &1.id),
        "supporting_memory_ids" =>
          supporting_memories
          |> Enum.map(& &1["memory_id"])
          |> Enum.filter(&is_integer/1)
          |> Enum.uniq(),
        "follow_up_context" => follow_up_context
      },
      "metadata" =>
        (claimed.metadata || %{})
        |> Map.put("delegation_batch", delegation_batch)
        |> Map.put("follow_up_context", follow_up_context),
      "runtime_state" =>
        append_history(claimed.runtime_state, status, %{
          "completed_at" => DateTime.utc_now(),
          "phase" => "finalize",
          "summary_artifact_id" => summary_artifact.id,
          "approval_decision" => latest_decision,
          "supporting_memory_count" => length(supporting_memories)
        })
    }
  end

  defp build_follow_up_context(
         parent,
         supporting_memories,
         summary_artifact,
         constraint_findings \\ [],
         constraint_strategy \\ nil,
         delivery_recovery \\ nil
       ) do
    contextual_memories =
      merge_supporting_findings(
        List.wrap(supporting_memories) ++
          List.wrap(get_in(parent.metadata || %{}, ["follow_up_context", "delivery_decisions"])) ++
          follow_up_summary_artifact_findings(parent, summary_artifact)
      )

    base_recovery =
      delivery_recovery || inherited_delivery_recovery(parent) ||
        derived_delivery_recovery(parent, constraint_findings)

    %{
      "query" => parent.goal,
      "captured_at" => DateTime.utc_now(),
      "summary_artifact_id" => summary_artifact.id,
      "promoted_findings" => Enum.take(contextual_memories, 5),
      "delivery_decisions" => Enum.take(delivery_decision_findings(contextual_memories), 3),
      "constraint_findings" => Enum.take(constraint_findings, 5),
      "constraint_strategy" => constraint_strategy,
      "needs_replan" => constraint_findings != []
    }
    |> maybe_put_delivery_recovery(
      refine_delivery_recovery(
        parent,
        summary_artifact,
        contextual_memories,
        constraint_findings,
        base_recovery
      )
    )
  end

  defp follow_up_summary_artifact_findings(_parent, nil), do: []

  defp follow_up_summary_artifact_findings(parent, %Artifact{} = artifact) do
    payload = artifact.payload || %{}

    if artifact.type == "delivery_brief" do
      score = artifact.confidence || 0.0
      source_role = payload["memory_origin_role"] || parent.assigned_role
      decision_snapshot = payload["delivery_decision_snapshot"] || %{}

      [
        payload["publish_objective"] &&
          %{
            "memory_id" => nil,
            "type" => "DeliveryDecision",
            "content" => payload["publish_objective"],
            "score" => score,
            "summary_reason" => "delivery_brief",
            "source_work_item_id" => parent.id,
            "source_goal" => parent.goal,
            "source_kind" => parent.kind,
            "source_role" => source_role,
            "source_artifact_type" => artifact.type,
            "reasons" => ["summary artifact delivery decision"]
          },
        payload["destination_rationale"] &&
          %{
            "memory_id" => nil,
            "type" => "DeliveryDecision",
            "content" => payload["destination_rationale"],
            "score" => score,
            "summary_reason" => "delivery_brief",
            "source_work_item_id" => parent.id,
            "source_goal" => parent.goal,
            "source_kind" => parent.kind,
            "source_role" => source_role,
            "source_artifact_type" => artifact.type,
            "reasons" => ["summary artifact delivery rationale"]
          },
        decision_snapshot["prior_summary"] &&
          %{
            "memory_id" => nil,
            "type" => "DeliveryDecision",
            "content" => decision_snapshot["prior_summary"],
            "score" => score,
            "summary_reason" => "delivery_brief",
            "source_work_item_id" => parent.id,
            "source_goal" => parent.goal,
            "source_kind" => parent.kind,
            "source_role" => source_role,
            "source_artifact_type" => artifact.type,
            "reasons" => ["summary artifact prior delivery decision"]
          },
        decision_snapshot["comparison_summary"] &&
          %{
            "memory_id" => nil,
            "type" => "DeliveryDecision",
            "content" => decision_snapshot["comparison_summary"],
            "score" => score,
            "summary_reason" => "delivery_brief",
            "source_work_item_id" => parent.id,
            "source_goal" => parent.goal,
            "source_kind" => parent.kind,
            "source_role" => source_role,
            "source_artifact_type" => artifact.type,
            "reasons" => ["summary artifact delivery decision comparison"]
          }
      ]
      |> Enum.reject(&is_nil/1)
    else
      []
    end
  end

  defp maybe_put_delivery_recovery(follow_up_context, recovery)
       when is_map(recovery) and map_size(recovery) > 0 do
    Map.put(follow_up_context, "delivery_recovery", recovery)
  end

  defp maybe_put_delivery_recovery(follow_up_context, _recovery), do: follow_up_context

  defp inherited_delivery_recovery(%WorkItem{} = parent) do
    get_in(parent.metadata || %{}, ["delivery_recovery"]) ||
      get_in(parent.metadata || %{}, ["follow_up_context", "delivery_recovery"])
  end

  defp refine_delivery_recovery(
         _parent,
         _summary_artifact,
         _supporting_memories,
         _constraint_findings,
         nil
       ),
       do: nil

  defp refine_delivery_recovery(
         _parent,
         summary_artifact,
         supporting_memories,
         constraint_findings,
         delivery_recovery
       )
       when is_map(delivery_recovery) and map_size(delivery_recovery) > 0 do
    confidence = publish_recovery_confidence(summary_artifact, supporting_memories)

    recommended_channel =
      publish_recovery_channel_signal(summary_artifact, supporting_memories, delivery_recovery)

    previous_mode =
      delivery_recovery["previous_mode"] || delivery_recovery["recommended_delivery_mode"] ||
        "channel"

    previous_channel =
      delivery_recovery["previous_channel"] || delivery_recovery["recommended_channel"]

    previous_target =
      delivery_recovery["previous_target"] || delivery_recovery["recommended_target"]

    cond do
      present_text?(recommended_channel) and recommended_channel != previous_channel ->
        %{
          "strategy" => "switch_delivery_channel",
          "reason" => delivery_recovery["reason"] || "planner_refined_recovery",
          "rationale" => delivery_recovery["rationale"],
          "recommended_delivery_mode" => "channel",
          "recommended_channel" => recommended_channel,
          "recommended_target" => delivery_recovery["recommended_target"] || previous_target,
          "previous_mode" => previous_mode,
          "previous_channel" => previous_channel,
          "previous_target" => previous_target,
          "recommended_action" =>
            "Revise the summary and reroute it through #{recommended_channel} before requesting delivery approval again.",
          "decision_basis" => "explicit_channel_signal",
          "decision_confidence" => confidence
        }

      confidence < 0.6 or constraint_findings != [] ->
        %{
          "strategy" => "internal_report_fallback",
          "reason" => delivery_recovery["reason"] || "planner_refined_recovery",
          "rationale" => delivery_recovery["rationale"],
          "recommended_delivery_mode" => "report",
          "recommended_target" => "control-plane",
          "previous_mode" => previous_mode,
          "previous_channel" => previous_channel,
          "previous_target" => previous_target,
          "recommended_action" =>
            "Keep the publish path internal until the revised summary has stronger confidence and explicit approval for external delivery.",
          "decision_basis" => "low_confidence",
          "decision_confidence" => confidence
        }

      true ->
        %{
          "strategy" => "revise_and_retry_channel",
          "reason" => delivery_recovery["reason"] || "planner_refined_recovery",
          "rationale" => delivery_recovery["rationale"],
          "recommended_delivery_mode" => previous_mode,
          "recommended_channel" => previous_channel,
          "recommended_target" => previous_target,
          "previous_mode" => previous_mode,
          "previous_channel" => previous_channel,
          "previous_target" => previous_target,
          "recommended_action" =>
            "Revise the summary and retry the delivery path once the updated brief is approved.",
          "decision_basis" => "revised_confident_summary",
          "decision_confidence" => confidence
        }
    end
  end

  defp apply_delivery_recovery_to_deliverables(deliverables, delivery_recovery) do
    deliverables = Helpers.normalize_string_keys(deliverables || %{})

    base_delivery = %{
      "enabled" => Map.get(deliverables, "enabled", false),
      "mode" => Map.get(deliverables, "mode", "report"),
      "channel" => Map.get(deliverables, "channel"),
      "target" => Map.get(deliverables, "target")
    }

    resolved_delivery = resolved_delivery_config(base_delivery, delivery_recovery || %{})

    deliverables
    |> Map.put("enabled", Map.get(resolved_delivery, "enabled", base_delivery["enabled"]))
    |> Map.put("mode", resolved_delivery["mode"] || base_delivery["mode"])
    |> Map.put("channel", resolved_delivery["channel"])
    |> Map.put("target", resolved_delivery["target"])
    |> Map.put("delivery", resolved_delivery)
  end

  defp publish_recovery_confidence(summary_artifact, supporting_memories) do
    artifact_confidence =
      cond do
        match?(%Artifact{}, summary_artifact) and is_float(summary_artifact.confidence) ->
          summary_artifact.confidence

        match?(%Artifact{}, summary_artifact) and is_integer(summary_artifact.confidence) ->
          summary_artifact.confidence * 1.0

        true ->
          0.0
      end

    evidence_confidence =
      supporting_memories
      |> List.wrap()
      |> Enum.map(fn memory ->
        case memory["score"] do
          value when is_float(value) -> value
          value when is_integer(value) -> value * 1.0
          _ -> 0.0
        end
      end)
      |> case do
        [] -> artifact_confidence
        scores -> Enum.sum(scores) / length(scores)
      end

    if artifact_confidence > 0.0 do
      Float.round(artifact_confidence * 0.7 + evidence_confidence * 0.3, 3)
    else
      Float.round(evidence_confidence, 3)
    end
  end

  defp publish_recovery_channel_signal(summary_artifact, supporting_memories, delivery_recovery) do
    inherited_channel = delivery_recovery["recommended_channel"]

    if present_text?(inherited_channel) do
      inherited_channel
    else
      texts =
        [
          summary_artifact && summary_artifact.summary,
          summary_artifact && summary_artifact.body
        ] ++ Enum.map(List.wrap(supporting_memories), & &1["content"])

      Enum.find_value(texts, &channel_signal_from_text/1)
    end
  end

  defp channel_signal_from_text(text) when is_binary(text) do
    normalized = String.downcase(text)

    cond do
      String.contains?(normalized, "slack") -> "slack"
      String.contains?(normalized, "discord") -> "discord"
      String.contains?(normalized, "telegram") -> "telegram"
      String.contains?(normalized, "webchat") -> "webchat"
      true -> nil
    end
  end

  defp channel_signal_from_text(_text), do: nil

  defp derived_delivery_recovery(parent, constraint_findings) do
    if Enum.any?(constraint_findings, &(&1["summary_reason"] == "delivery_rejected")) do
      delivery =
        get_in(parent.deliverables || %{}, ["delivery"]) ||
          get_in(parent.metadata || %{}, ["delivery"]) ||
          %{}

      %{
        "strategy" => "internal_report_fallback",
        "reason" => "operator_rejected_delivery",
        "recommended_delivery_mode" => "report",
        "recommended_target" => "control-plane",
        "previous_mode" => delivery["mode"] || "channel",
        "previous_channel" => delivery["channel"],
        "previous_target" => delivery["target"],
        "recommended_action" =>
          "Prepare an internal report until the publish path is revised and validated."
      }
    end
  end

  defp append_follow_up_result_refs(result_refs, %WorkItem{} = follow_up_work_item, type) do
    ids =
      result_refs
      |> Kernel.||(%{})
      |> Map.get("follow_up_work_item_ids", [])
      |> List.wrap()
      |> Kernel.++([follow_up_work_item.id])
      |> Enum.uniq()

    types =
      result_refs
      |> Kernel.||(%{})
      |> get_in(["follow_up_summary", "types"])
      |> List.wrap()
      |> Kernel.++([type])
      |> Enum.uniq()

    (result_refs || %{})
    |> Map.put("follow_up_work_item_ids", ids)
    |> Map.put("follow_up_summary", %{"count" => length(ids), "types" => types})
  end

  defp ensure_follow_up_work_item(%WorkItem{} = parent, task_type, matcher, attrs)
       when is_binary(task_type) and is_function(matcher, 1) and is_map(attrs) do
    case existing_follow_up_work_item(parent, task_type, matcher) do
      %WorkItem{} = work_item ->
        {:ok, work_item}

      nil ->
        save_work_item(attrs)
    end
  end

  defp existing_follow_up_work_item(%WorkItem{} = parent, task_type, matcher) do
    list_work_items(parent_work_item_id: parent.id, limit: 25, preload: false)
    |> Enum.filter(fn item ->
      get_in(item.metadata || %{}, ["task_type"]) == task_type and
        item.status not in ["canceled"]
    end)
    |> Enum.sort_by(fn item ->
      {follow_up_status_rank(item.status), sortable_datetime(item.inserted_at)}
    end)
    |> Enum.find(matcher)
  end

  defp follow_up_status_rank(status) when status in ["planned", "claimed", "running", "blocked"],
    do: 0

  defp follow_up_status_rank("replayed"), do: 1
  defp follow_up_status_rank("completed"), do: 2
  defp follow_up_status_rank("failed"), do: 3
  defp follow_up_status_rank(_status), do: 4

  defp sortable_datetime(%DateTime{} = datetime), do: DateTime.to_unix(datetime, :microsecond)
  defp sortable_datetime(_datetime), do: 0

  defp promoted_memory_ids(%WorkItem{} = work_item) do
    work_item.result_refs
    |> Map.get("promoted_memory_ids", [])
    |> List.wrap()
    |> Enum.filter(&is_integer/1)
    |> Enum.uniq()
  end

  defp promoted_memories_by_ids([]), do: []

  defp promoted_memories_by_ids(ids) do
    Entry
    |> where([entry], entry.id in ^ids)
    |> preload([:conversation])
    |> Repo.all()
    |> Enum.sort_by(fn entry ->
      Enum.find_index(ids, &(&1 == entry.id)) || length(ids)
    end)
  end

  defp maybe_filter_work_item_status(query, nil), do: query

  defp maybe_filter_work_item_status(query, status),
    do: where(query, [work_item], work_item.status == ^status)

  defp maybe_filter_work_item_statuses(query, nil), do: query

  defp maybe_filter_work_item_statuses(query, statuses) when is_list(statuses) do
    where(query, [work_item], work_item.status in ^statuses)
  end

  defp maybe_filter_work_item_kind(query, nil), do: query

  defp maybe_filter_work_item_kind(query, kind),
    do: where(query, [work_item], work_item.kind == ^kind)

  defp maybe_filter_work_item_role(query, nil), do: query

  defp maybe_filter_work_item_role(query, assigned_role) do
    where(query, [work_item], work_item.assigned_role == ^assigned_role)
  end

  defp maybe_filter_work_item_agent(query, nil), do: query

  defp maybe_filter_work_item_agent(query, agent_id) do
    where(query, [work_item], work_item.assigned_agent_id == ^agent_id)
  end

  defp maybe_filter_work_item_parent(query, nil), do: query

  defp maybe_filter_work_item_parent(query, parent_work_item_id) do
    where(query, [work_item], work_item.parent_work_item_id == ^parent_work_item_id)
  end

  defp maybe_filter_artifact_work_item(query, nil), do: query

  defp maybe_filter_artifact_work_item(query, work_item_id) do
    where(query, [artifact], artifact.work_item_id == ^work_item_id)
  end

  defp maybe_filter_artifact_type(query, nil), do: query

  defp maybe_filter_artifact_type(query, type),
    do: where(query, [artifact], artifact.type == ^type)

  defp maybe_filter_approval_subject(query, nil, _subject_id), do: query
  defp maybe_filter_approval_subject(query, _subject_type, nil), do: query

  defp maybe_filter_approval_subject(query, subject_type, subject_id) do
    where(
      query,
      [record],
      record.subject_type == ^subject_type and record.subject_id == ^subject_id
    )
  end

  defp maybe_filter_approval_work_item(query, nil), do: query

  defp maybe_filter_approval_work_item(query, work_item_id),
    do: where(query, [record], record.work_item_id == ^work_item_id)

  defp maybe_filter_approval_reviewer(query, nil), do: query

  defp maybe_filter_approval_reviewer(query, reviewer_agent_id) do
    where(query, [record], record.reviewer_agent_id == ^reviewer_agent_id)
  end

  defp maybe_filter_approval_decision(query, nil), do: query

  defp maybe_filter_approval_decision(query, decision),
    do: where(query, [record], record.decision == ^decision)
end
