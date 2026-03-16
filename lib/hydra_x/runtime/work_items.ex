defmodule HydraX.Runtime.WorkItems do
  @moduledoc """
  Persisted autonomy work graph and minimal orchestration loop.
  """

  import Ecto.Query

  alias HydraX.Budget
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

    with {:ok, _lease} <-
           Coordination.claim_lease(lease_name(work_item.id),
             ttl_seconds: Keyword.get(opts, :ttl_seconds, @claim_ttl_seconds),
             metadata:
               Map.merge(metadata, %{
                 "work_item_id" => work_item.id,
                 "assigned_role" => work_item.assigned_role
               })
           ) do
      save_work_item(work_item, %{
        "status" => "claimed",
        "runtime_state" =>
          append_history(work_item.runtime_state, "claimed", %{
            "claimed_at" => DateTime.utc_now(),
            "lease_name" => lease_name(work_item.id)
          })
      })
    end
  end

  def run_autonomy_cycle(agent_id, opts \\ []) when is_integer(agent_id) do
    agent = Agents.get_agent!(agent_id)

    if agent.status != "active" do
      {:ok, %{agent: agent, status: "skipped", processed_count: 0, reason: "agent_inactive"}}
    else
      with {:idle, nil} <- maybe_finalize_blocked_parent(agent, opts),
           {:idle, nil} <- maybe_run_next_work_item(agent, opts) do
        {:ok, %{agent: agent, status: "idle", processed_count: 0, artifacts: []}}
      else
        {:processed, summary} -> {:ok, Map.put(summary, :agent, agent)}
      end
    end
  end

  def autonomy_status do
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
      list_work_items(limit: 500, preload: false)
      |> Enum.count(&(not is_nil(get_in(&1.result_refs || %{}, ["policy_failure", "type"]))))

    budget_blocked_count =
      list_work_items(limit: 500, preload: false)
      |> Enum.count(&budget_policy_failure?(&1.result_refs || %{}))

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
      autonomy_agent_count: length(autonomy_agents),
      active_roles: autonomy_agents |> Enum.map(& &1.role) |> Enum.frequencies(),
      capability_drifts: capability_drifts,
      recent_work_items: list_work_items(limit: 6, preload: false),
      recent_approvals: list_approval_records(limit: 6)
    }
  end

  def capability_profile(%AgentProfile{} = agent) do
    Autonomy.ensure_capability_profile(agent.role, agent.capability_profile || %{})
  end

  defp maybe_finalize_blocked_parent(agent, _opts) do
    blocked_parent =
      WorkItem
      |> where(
        [work_item],
        work_item.status == "blocked" and
          (work_item.assigned_agent_id == ^agent.id or work_item.assigned_role == ^agent.role)
      )
      |> order_by([work_item], desc: work_item.priority, asc: work_item.inserted_at)
      |> limit(10)
      |> Repo.all()
      |> Enum.find(&blocked_parent_ready?/1)

    case blocked_parent do
      nil ->
        {:idle, nil}

      %WorkItem{} = work_item ->
        case claim_work_item(work_item, metadata: %{"phase" => "finalize"}) do
          {:ok, claimed} ->
            children =
              list_work_items(
                parent_work_item_id: claimed.id,
                statuses: @terminal_work_item_statuses,
                limit: 10
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

            {:ok, summary_artifact} =
              create_artifact(%{
                "work_item_id" => claimed.id,
                "type" => "decision_ledger",
                "title" => "Delegation synthesis",
                "summary" => delegation_summary_line(claimed, children, supporting_memories),
                "body" => delegation_summary_body(claimed, children, supporting_memories),
                "payload" => %{
                  "child_work_item_ids" => Enum.map(children, & &1.id),
                  "result_artifact_ids" => artifact_ids,
                  "promoted_findings" => supporting_memories,
                  "constraint_findings" => constraint_findings
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

          {:error, {:taken, _lease}} ->
            {:idle, nil}

          {:error, reason} ->
            {:processed,
             %{status: "failed", processed_count: 0, action: "finalize_failed", error: reason}}
        end
    end
  end

  defp blocked_parent_ready?(%WorkItem{} = work_item) do
    children = list_work_items(parent_work_item_id: work_item.id, limit: 20, preload: false)
    children != [] and Enum.all?(children, &terminal_work_item?/1)
  end

  defp terminal_work_item?(%WorkItem{status: status}), do: status in @terminal_work_item_statuses

  defp maybe_run_next_work_item(agent, opts) do
    case next_work_item_for_agent(agent) do
      nil ->
        {:idle, nil}

      %WorkItem{} = work_item ->
        case claim_work_item(work_item, metadata: %{"phase" => "run"}) do
          {:ok, claimed} ->
            case authorize_work_item(agent, claimed) do
              :ok ->
                process_work_item(agent, claimed, opts)

              {:error, failure} ->
                block_work_item_for_policy(claimed, failure)
            end

          {:error, {:taken, _lease}} ->
            {:idle, nil}

          {:error, reason} ->
            {:processed,
             %{status: "failed", processed_count: 0, action: "claim_failed", error: reason}}
        end
    end
  end

  defp process_work_item(agent, %WorkItem{execution_mode: "delegate"} = work_item, _opts) do
    child_role = work_item.metadata["delegate_role"] || Autonomy.role_for_kind(work_item.kind)
    child_goal = work_item.metadata["delegate_goal"] || work_item.goal

    delegation_context =
      merge_delegation_context(
        delegation_context_snapshot(agent.id, child_goal),
        delegation_override_context(work_item)
      )

    {:ok, child} =
      save_work_item(%{
        "kind" => work_item.kind,
        "goal" => child_goal,
        "status" => "planned",
        "execution_mode" => "execute",
        "assigned_role" => child_role,
        "delegated_by_agent_id" => agent.id,
        "parent_work_item_id" => work_item.id,
        "priority" => max(work_item.priority, 1),
        "autonomy_level" => work_item.autonomy_level,
        "approval_stage" => work_item.approval_stage,
        "review_required" => work_item.review_required,
        "budget" => work_item.budget,
        "required_outputs" => work_item.required_outputs,
        "metadata" =>
          %{
            "delegated_from_role" => agent.role,
            "delegated_from_work_item_id" => work_item.id
          }
          |> maybe_put_delegation_context(delegation_context, agent.id, child_goal)
      })

    {:ok, plan_artifact} =
      create_artifact(%{
        "work_item_id" => work_item.id,
        "type" => "plan",
        "title" => "Delegation plan",
        "summary" => "Delegated #{work_item.kind} to #{child_role}",
        "body" => delegation_plan_body(work_item, child, delegation_context),
        "payload" => %{
          "delegated_work_item_id" => child.id,
          "assigned_role" => child_role,
          "required_outputs" => work_item.required_outputs,
          "delegation_context" => delegation_context
        },
        "provenance" => %{"source" => "autonomy", "phase" => "delegate"},
        "confidence" => 0.78
      })

    {:ok, updated} =
      save_work_item(work_item, %{
        "status" => "blocked",
        "result_refs" => %{
          "artifact_ids" => [plan_artifact.id],
          "child_work_item_ids" => [child.id]
        },
        "runtime_state" =>
          append_history(work_item.runtime_state, "blocked", %{
            "blocked_at" => DateTime.utc_now(),
            "reason" => "delegated",
            "child_work_item_id" => child.id
          })
      })

    {:processed,
     %{
       status: "blocked",
       processed_count: 1,
       work_item: updated,
       artifacts: [plan_artifact],
       action: "delegated",
       delegated_work_item: child
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
        """
        |> String.trim(),
      "decision" => decision,
      "findings" => findings,
      "target_goal" => target && target.goal,
      "delegated_context" => delegated_context,
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
      "claims" =>
        delegated_context
        |> Enum.take(2)
        |> Enum.map(& &1["content"]),
      "confidence" => review_payload["confidence"],
      "memory_origin_role" => "reviewer",
      "scope" => "autonomous review"
    }
  end

  defp build_delivery_brief(agent, work_item, summary_artifact, follow_up_context, delivery) do
    delivery_mode = delivery["mode"] || "report"
    delivery_channel = delivery["channel"]
    delivery_target = delivery["target"]
    summary_payload = (summary_artifact && summary_artifact.payload) || %{}
    follow_up_metadata = get_in(work_item.metadata || %{}, ["follow_up_context"]) || %{}
    findings = Enum.take(follow_up_context, 4)
    degraded? = degraded_delivery_brief?(follow_up_metadata, summary_payload, findings)

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
        Constraint strategy: #{constraint_strategy || "none"}

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
        Constraint strategy: #{constraint_strategy || "none"}

        Summary ready for publication:
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
      "constraint_strategy" => constraint_strategy,
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
          if(
            degraded?,
            do: "Review the degraded publish-ready summary before any external delivery.",
            else: "Review the publish-ready summary before external delivery."
          ),
          delivery_target &&
            "Deliver to #{delivery_target} via #{delivery_channel || delivery_mode}."
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

  defp maybe_deliver_publish_summary(agent, work_item, payload) do
    delivery = payload["delivery"] || %{}
    enabled? = Map.get(delivery, "enabled", false)
    channel = delivery["channel"]
    target = delivery["target"]

    result =
      cond do
        enabled? != true ->
          %{"status" => "draft", "degraded" => payload["degraded"] == true}

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

    maybe_record_work_item_budget_usage(agent, work_item, "autonomy_delivery", 0, 0)
    result
  end

  defp maybe_enqueue_publish_review_follow_up(
         %WorkItem{} = publish_item,
         %Artifact{} = delivery_brief,
         delivery,
         payload
       ) do
    cond do
      payload["degraded"] != true ->
        {:ok, publish_item, nil}

      Map.get(delivery || %{}, "enabled", false) != true ->
        {:ok, publish_item, nil}

      true ->
        {:ok, review_item} =
          save_work_item(%{
            "kind" => "task",
            "goal" =>
              "Approve degraded delivery for #{Map.get(delivery || %{}, "channel", "report")} #{Map.get(delivery || %{}, "target", "control-plane")}",
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
              "delivery" => delivery || %{},
              "degraded_execution" => true,
              "requested_action" => "publish_review_report",
              "follow_up_context" => get_in(publish_item.metadata || %{}, ["follow_up_context"])
            }
          })

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

  defp delegation_plan_body(parent, child, delegation_context) do
    """
    Parent goal: #{parent.goal}
    Delegated role: #{child.assigned_role}
    Child work item: ##{child.id}
    Execution mode: #{child.execution_mode}
    Delegated context:
    #{Enum.map_join(delegation_context, "\n", fn memory -> "- #{memory["type"]}: #{memory["content"]}" end)}
    """
    |> String.trim()
  end

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
    findings_block =
      case supporting_memories do
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

    """
    Parent goal: #{parent.goal}

    Delegated work outcomes:
    #{Enum.map_join(children, "\n", &delegated_child_summary/1)}

    Promoted findings shaping this synthesis:
    #{findings_block}
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
    work_item.metadata
    |> case do
      metadata when is_map(metadata) -> Map.get(metadata, "follow_up_context", %{})
      _ -> %{}
    end
    |> Map.get("promoted_findings", [])
    |> List.wrap()
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

    constraint_findings ++ strategy
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

  defp merge_delegation_context(base_context, extra_context, limit \\ 3) do
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
        (work_item.assigned_agent_id == ^agent.id or work_item.assigned_role == ^agent.role)
    )
    |> order_by([work_item], desc: work_item.priority, asc: work_item.inserted_at)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> nil
      work_item -> get_work_item!(work_item.id)
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

  defp complete_publish_review!(%WorkItem{} = review_item, approval_record) do
    publish_item = get_work_item!(review_item.metadata["publish_work_item_id"])
    delivery_brief = get_artifact!(review_item.metadata["delivery_brief_artifact_id"])
    delivery = review_item.metadata["delivery"] || %{}
    agent_id = review_item.assigned_agent_id || publish_item.assigned_agent_id
    agent = Agents.get_agent!(agent_id)

    delivery_result =
      execute_publish_delivery(
        agent,
        delivery["channel"],
        delivery["target"],
        delivery_brief.body
      )

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
        "payload" => Map.put(updated_brief.payload || %{}, "delivery", delivery_result)
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
      present_text?(summary_payload["constraint_strategy"]) or
      List.wrap(summary_payload["constraint_findings"]) != [] or
      Enum.any?(List.wrap(findings), &((&1["type"] || &1[:type]) == "Constraint"))
  end

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

    summary_finding ++ claim_findings ++ action_findings
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

  defp inferred_artifact_finding_type("decision_ledger"), do: "Decision"
  defp inferred_artifact_finding_type("review_report"), do: "Decision"
  defp inferred_artifact_finding_type("research_report"), do: "Finding"
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
      goal =
        deliverables["goal"] ||
          "Publish the finalized summary for #{parent.goal}"

      {:ok, follow_up_work_item} =
        save_work_item(%{
          "kind" => "task",
          "goal" => goal,
          "status" => "planned",
          "execution_mode" => "execute",
          "assigned_role" => deliverables["assigned_role"] || "operator",
          "assigned_agent_id" => deliverables["assigned_agent_id"],
          "delegated_by_agent_id" => parent.assigned_agent_id || parent.delegated_by_agent_id,
          "parent_work_item_id" => parent.id,
          "priority" => max(parent.priority - 1, 0),
          "autonomy_level" => parent.autonomy_level,
          "approval_stage" => "validated",
          "deliverables" => deliverables,
          "input_artifact_refs" => %{"summary_artifact_id" => summary_artifact.id},
          "required_outputs" => %{"artifact_types" => ["delivery_brief"]},
          "metadata" => %{
            "task_type" => "publish_summary",
            "summary_artifact_id" => summary_artifact.id,
            "delivery" => %{
              "enabled" => deliverables["enabled"] == true,
              "mode" => deliverables["mode"] || "report",
              "channel" => deliverables["channel"],
              "target" => deliverables["target"]
            },
            "follow_up_context" =>
              build_follow_up_context(parent, supporting_memories, summary_artifact)
          }
        })

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

      {:ok, follow_up_work_item} =
        save_work_item(%{
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
          "deliverables" => parent.deliverables,
          "input_artifact_refs" => %{"summary_artifact_id" => summary_artifact.id},
          "required_outputs" => parent.required_outputs,
          "review_required" => parent.review_required,
          "metadata" => %{
            "task_type" => "constraint_replan",
            "delegate_goal" => parent.goal,
            "summary_artifact_id" => summary_artifact.id,
            "constraint_findings" => Enum.take(constraint_findings, 5),
            "constraint_strategy" => constraint_strategy,
            "follow_up_context" =>
              build_follow_up_context(
                parent,
                supporting_memories,
                summary_artifact,
                constraint_findings,
                constraint_strategy
              )
          }
        })

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
         constraint_strategy \\ nil
       ) do
    %{
      "query" => parent.goal,
      "captured_at" => DateTime.utc_now(),
      "summary_artifact_id" => summary_artifact.id,
      "promoted_findings" => Enum.take(supporting_memories, 5),
      "constraint_findings" => Enum.take(constraint_findings, 5),
      "constraint_strategy" => constraint_strategy,
      "needs_replan" => constraint_findings != []
    }
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
