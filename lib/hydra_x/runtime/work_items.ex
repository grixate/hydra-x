defmodule HydraX.Runtime.WorkItems do
  @moduledoc """
  Persisted autonomy work graph and minimal orchestration loop.
  """

  import Ecto.Query

  alias HydraX.Budget
  alias HydraX.LLM.Router
  alias HydraX.Memory
  alias HydraX.Repo

  alias HydraX.Runtime.{
    AgentProfile,
    Agents,
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
        preload(WorkItem, [:assigned_agent, :delegated_by_agent, :artifacts, :child_work_items])
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
    |> Repo.preload([:assigned_agent, :delegated_by_agent, :artifacts, :child_work_items])
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

    autonomy_agents =
      Agents.list_agents()
      |> Enum.filter(&(Map.get(capability_profile(&1), "max_autonomy_level") != "observe"))

    %{
      counts: counts,
      overdue_count: overdue_count,
      pending_review_count: pending_review_count,
      autonomy_agent_count: length(autonomy_agents),
      active_roles: autonomy_agents |> Enum.map(& &1.role) |> Enum.frequencies(),
      recent_work_items: list_work_items(limit: 6, preload: false)
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
              save_work_item(claimed, %{
                "status" => "completed",
                "result_refs" => %{
                  "artifact_ids" => Enum.uniq([summary_artifact.id | artifact_ids]),
                  "child_work_item_ids" => Enum.map(children, & &1.id)
                },
                "runtime_state" =>
                  append_history(claimed.runtime_state, "completed", %{
                    "completed_at" => DateTime.utc_now(),
                    "phase" => "finalize",
                    "summary_artifact_id" => summary_artifact.id
                  })
              })

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

  defp fallback_research_body(work_item, evidence) do
    """
    Research question: #{work_item.goal}

    Evidence summary:
    #{Enum.map_join(evidence, "\n", fn ranked -> "- #{ranked.entry.content}" end)}
    """
    |> String.trim()
  end

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
end
