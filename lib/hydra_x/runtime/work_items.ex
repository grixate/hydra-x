defmodule HydraX.Runtime.WorkItems do
  @moduledoc """
  Persisted autonomy work graph and minimal orchestration loop.
  """

  import Ecto.Query

  alias HydraX.Budget
  alias HydraX.LLM.Router
  alias HydraX.Memory
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
    WorkItem
  }

  @claim_ttl_seconds 180

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

  def work_item_artifacts(work_item_id) when is_integer(work_item_id) do
    list_artifacts(work_item_id: work_item_id, limit: 100)
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

    {:ok, record} =
      create_approval_record(%{
        "subject_type" => "work_item",
        "subject_id" => work_item.id,
        "requested_action" => attrs["requested_action"] || "promote_work_item",
        "decision" => "approved",
        "rationale" => attrs["rationale"] || "Approved for promotion.",
        "promoted_at" => attrs["promoted_at"] || DateTime.utc_now(),
        "reviewer_agent_id" => attrs["reviewer_agent_id"],
        "work_item_id" => attrs["work_item_id"],
        "metadata" => attrs["metadata"] || %{}
      })

    {:ok, updated} =
      save_work_item(work_item, %{
        "approval_stage" => "operator_approved",
        "runtime_state" =>
          append_history(work_item.runtime_state, "approved", %{
            "approved_at" => DateTime.utc_now(),
            "approval_record_id" => record.id
          })
      })

    {updated, record}
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

    approval_decisions =
      ApprovalRecord
      |> group_by([record], record.decision)
      |> select([record], {record.decision, count(record.id)})
      |> Repo.all()
      |> Map.new()

    autonomy_agents =
      Agents.list_agents()
      |> Enum.filter(&(Map.get(capability_profile(&1), "max_autonomy_level") != "observe"))

    %{
      counts: counts,
      overdue_count: overdue_count,
      pending_review_count: pending_review_count,
      approval_decisions: approval_decisions,
      autonomy_agent_count: length(autonomy_agents),
      active_roles: autonomy_agents |> Enum.map(& &1.role) |> Enum.frequencies(),
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
      |> join(:inner, [work_item], child in WorkItem,
        on: child.parent_work_item_id == work_item.id
      )
      |> where([_work_item, child], child.status == "completed")
      |> order_by([work_item, _child], desc: work_item.priority, asc: work_item.inserted_at)
      |> limit(1)
      |> select([work_item, _child], work_item)
      |> Repo.one()

    case blocked_parent do
      nil ->
        {:idle, nil}

      %WorkItem{} = work_item ->
        case claim_work_item(work_item, metadata: %{"phase" => "finalize"}) do
          {:ok, claimed} ->
            children =
              list_work_items(parent_work_item_id: claimed.id, status: "completed", limit: 10)

            artifact_ids =
              children
              |> Enum.flat_map(fn child ->
                child.result_refs
                |> Map.get("artifact_ids", [])
                |> List.wrap()
              end)

            {:ok, summary_artifact} =
              create_artifact(%{
                "work_item_id" => claimed.id,
                "type" => "decision_ledger",
                "title" => "Delegation synthesis",
                "summary" => "Planner synthesized #{length(children)} delegated results",
                "body" => delegation_summary_body(claimed, children),
                "payload" => %{
                  "child_work_item_ids" => Enum.map(children, & &1.id),
                  "result_artifact_ids" => artifact_ids
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
                finalize_parent_attrs(claimed, children, summary_artifact, artifact_ids)
              )

            {:processed,
             %{
               status: "completed",
               processed_count: 1,
               work_item: updated,
               artifacts: [summary_artifact],
               action: "finalized_blocked_parent"
             }}

          {:error, {:taken, _lease}} ->
            {:idle, nil}

          {:error, reason} ->
            {:processed,
             %{status: "failed", processed_count: 0, action: "finalize_failed", error: reason}}
        end
    end
  end

  defp maybe_run_next_work_item(agent, opts) do
    case next_work_item_for_agent(agent) do
      nil ->
        {:idle, nil}

      %WorkItem{} = work_item ->
        case claim_work_item(work_item, metadata: %{"phase" => "run"}) do
          {:ok, claimed} ->
            process_work_item(agent, claimed, opts)

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
        "metadata" => %{
          "delegated_from_role" => agent.role,
          "delegated_from_work_item_id" => work_item.id
        }
      })

    {:ok, plan_artifact} =
      create_artifact(%{
        "work_item_id" => work_item.id,
        "type" => "plan",
        "title" => "Delegation plan",
        "summary" => "Delegated #{work_item.kind} to #{child_role}",
        "body" => delegation_plan_body(work_item, child),
        "payload" => %{
          "delegated_work_item_id" => child.id,
          "assigned_role" => child_role,
          "required_outputs" => work_item.required_outputs
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
        "review_status" => if(running.review_required, do: "proposed", else: "validated")
      })

    {:ok, completed} =
      save_work_item(running, %{
        "status" => "completed",
        "result_refs" => %{"artifact_ids" => [plan_artifact.id, report_artifact.id]},
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
       artifacts: [plan_artifact, report_artifact],
       action: "researched"
     }}
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

  defp process_work_item(agent, %WorkItem{} = work_item, _opts) do
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
    evidence_lines =
      evidence
      |> Enum.map(fn ranked ->
        source = source_label(ranked)
        score = Float.round(ranked.score, 2)
        "- [#{score}] #{ranked.entry.content}#{if(source, do: " (#{source})", else: "")}"
      end)

    prompt =
      [
        "You are Hydra-X's research worker.",
        "Produce a concise structured research report.",
        "Question: #{work_item.goal}",
        "Return short claims, open questions, and recommended actions grounded in the evidence.",
        "Evidence:",
        Enum.join(evidence_lines, "\n")
      ]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join("\n\n")

    messages = [%{role: "user", content: prompt}]
    estimated_tokens = Budget.estimate_prompt_tokens(messages)

    llm_body =
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
                metadata: %{provider: response.provider, purpose: "autonomy_research"}
              )

              response.content || fallback_research_body(work_item, evidence)

            {:error, _reason} ->
              fallback_research_body(work_item, evidence)
          end

        {:error, _details} ->
          fallback_research_body(work_item, evidence)
      end

    %{
      "question" => work_item.goal,
      "scope" => work_item.metadata["scope"] || "autonomous research",
      "sources" => Enum.map(evidence, &source_snapshot/1),
      "evidence" => Enum.map(evidence, &evidence_snapshot/1),
      "claims" => derive_claims(evidence),
      "open_questions" => derive_open_questions(work_item, evidence),
      "recommended_actions" => derive_recommended_actions(work_item, evidence),
      "confidence" => derive_confidence(evidence),
      "body" => llm_body
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
        save_work_item(%{
          "kind" => "review",
          "goal" => "Review #{running.kind} work item ##{running.id}: #{running.goal}",
          "status" => "planned",
          "execution_mode" => "review",
          "assigned_role" => "reviewer",
          "parent_work_item_id" => running.id,
          "priority" => max(running.priority, 1),
          "autonomy_level" => "execute_with_review",
          "approval_stage" => "patch_ready",
          "required_outputs" => %{"artifact_types" => ["review_report"]},
          "metadata" => %{
            "review_target_work_item_id" => running.id,
            "change_artifact_id" => change_artifact.id,
            "proposal_artifact_id" => proposal_artifact.id,
            "requested_action" => requested_action
          }
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

  defp do_review_work_item(agent, work_item) do
    target_id = work_item.metadata["review_target_work_item_id"]
    target = if is_integer(target_id), do: get_work_item!(target_id), else: nil

    change_artifact =
      if target && is_integer(work_item.metadata["change_artifact_id"]) do
        list_artifacts(work_item_id: target.id, limit: 20)
        |> Enum.find(&(&1.id == work_item.metadata["change_artifact_id"]))
      end

    review_payload = build_review_report(work_item, target, change_artifact)
    decision = review_payload["decision"]

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

    {:ok, updated} =
      save_work_item(work_item, %{
        "status" => "completed",
        "approval_stage" => if(decision == "approved", do: "validated", else: "proposal_only"),
        "result_refs" => %{
          "artifact_ids" => [review_artifact.id],
          "approval_record_ids" => [approval_record.id]
        },
        "runtime_state" =>
          append_history(work_item.runtime_state, "completed", %{
            "completed_at" => DateTime.utc_now(),
            "phase" => "review",
            "approval_record_id" => approval_record.id
          })
      })

    {:processed,
     %{
       status: "completed",
       processed_count: 1,
       work_item: updated,
       artifacts: [review_artifact],
       action: "review_completed"
     }}
  end

  defp fallback_research_body(work_item, evidence) do
    """
    Research question: #{work_item.goal}

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

    prompt =
      [
        "You are Hydra-X's builder agent.",
        "Create a concise engineering proposal.",
        "Goal: #{work_item.goal}",
        "Role: #{agent.role}",
        "Workspace focus: #{focus_files}",
        "Respond with a short proposal that includes likely changes, validation, risks, and rollback notes."
      ]
      |> Enum.join("\n\n")

    body =
      llm_body_for(agent, prompt, "autonomy_engineering") ||
        """
        Goal: #{work_item.goal}
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

    %{
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
  end

  defp build_review_report(work_item, target, change_artifact) do
    change_payload = (change_artifact && change_artifact.payload) || %{}
    changed_files = List.wrap(change_payload["changed_files"])
    test_commands = List.wrap(change_payload["test_commands"])
    requested_action = work_item.metadata["requested_action"] || "promote_work_item"
    decision = if(changed_files == [], do: "rejected", else: "approved")

    %{
      "summary" =>
        if(
          decision == "approved",
          do: "Validated #{requested_action} across #{length(changed_files)} candidate files",
          else: "Rejected review because no candidate files were prepared"
        ),
      "body" =>
        """
        Target work item: ##{target && target.id}
        Decision: #{decision}
        Candidate files: #{if(changed_files == [], do: "none", else: Enum.join(changed_files, ", "))}
        Validation commands: #{if(test_commands == [], do: "none", else: Enum.join(test_commands, ", "))}
        """
        |> String.trim(),
      "decision" => decision,
      "findings" => review_findings(changed_files, test_commands),
      "confidence" => if(decision == "approved", do: 0.74, else: 0.41)
    }
  end

  defp llm_body_for(agent, prompt, purpose) do
    messages = [%{role: "user", content: prompt}]
    estimated_tokens = Budget.estimate_prompt_tokens(messages)

    case Budget.preflight(agent.id, nil, estimated_tokens) do
      {:ok, _} ->
        case Router.complete(%{
               messages: messages,
               agent_id: agent.id,
               process_type: "autonomy"
             }) do
          {:ok, response} ->
            Budget.record_usage(agent.id, nil,
              tokens_in: estimated_tokens,
              tokens_out: Budget.estimate_tokens(response.content || ""),
              metadata: %{provider: response.provider, purpose: purpose}
            )

            response.content

          {:error, _reason} ->
            nil
        end

      {:error, _} ->
        nil
    end
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
    tokens =
      goal
      |> String.downcase()
      |> String.split(~r/[^a-z0-9]+/, trim: true)

    downcased = String.downcase(path)
    Enum.count(tokens, &String.contains?(downcased, &1))
  end

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

  defp review_findings(changed_files, test_commands) do
    []
    |> maybe_add_finding(
      changed_files == [],
      "No candidate changed files were prepared for review."
    )
    |> maybe_add_finding(
      test_commands == [],
      "No validation commands were attached to the change set."
    )
  end

  defp maybe_add_finding(list, false, _message), do: list
  defp maybe_add_finding(list, true, message), do: list ++ [message]

  defp delegation_plan_body(parent, child) do
    """
    Parent goal: #{parent.goal}
    Delegated role: #{child.assigned_role}
    Child work item: ##{child.id}
    Execution mode: #{child.execution_mode}
    """
    |> String.trim()
  end

  defp delegation_summary_body(parent, children) do
    """
    Parent goal: #{parent.goal}

    Completed delegated work:
    #{Enum.map_join(children, "\n", fn child -> "- ##{child.id} #{child.goal}" end)}
    """
    |> String.trim()
  end

  defp research_plan_body(work_item, evidence) do
    """
    Question: #{work_item.goal}

    Evidence candidates:
    #{Enum.map_join(evidence, "\n", fn ranked -> "- #{ranked.entry.type}: #{ranked.entry.content}" end)}
    """
    |> String.trim()
  end

  defp derive_claims(evidence) do
    evidence
    |> Enum.take(3)
    |> Enum.map(fn ranked -> ranked.entry.content end)
  end

  defp derive_open_questions(work_item, evidence) do
    cond do
      evidence == [] ->
        ["No supporting memory evidence was found for #{work_item.goal}."]

      true ->
        ["What new external evidence should be gathered to validate the current findings?"]
    end
  end

  defp derive_recommended_actions(work_item, evidence) do
    cond do
      evidence == [] ->
        ["Gather fresh sources for #{work_item.goal} before acting on it."]

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
    |> Map.put_new("metadata", work_item.metadata || %{})
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

  defp default_required_outputs("review"), do: %{"artifact_types" => ["review_report"]}

  defp default_required_outputs(_kind), do: %{"artifact_types" => ["note"]}

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

  defp side_effect_class_for_kind("engineering"), do: "repo_write"
  defp side_effect_class_for_kind("extension"), do: "plugin_install"
  defp side_effect_class_for_kind(_kind), do: "read_only"

  defp finalize_parent_attrs(claimed, children, summary_artifact, artifact_ids) do
    approval_records = approval_records_for_subject("work_item", claimed.id)
    latest_decision = approval_records |> List.first() |> then(&(&1 && &1.decision))

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
        "approval_record_ids" => Enum.map(approval_records, & &1.id)
      },
      "runtime_state" =>
        append_history(claimed.runtime_state, status, %{
          "completed_at" => DateTime.utc_now(),
          "phase" => "finalize",
          "summary_artifact_id" => summary_artifact.id,
          "approval_decision" => latest_decision
        })
    }
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
