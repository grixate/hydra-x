defmodule Mix.Tasks.HydraX.Work do
  use Mix.Task

  @shortdoc "Lists, inspects, and approves autonomy work items and artifacts"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      ["show", id] ->
        show_work_item(id)

      ["approve", id | rest] ->
        approve_work_item(id, rest)

      ["reject", id | rest] ->
        reject_work_item(id, rest)

      ["show-artifact", id] ->
        show_artifact(id)

      ["approve-artifact", id | rest] ->
        approve_artifact(id, rest)

      ["reject-artifact", id | rest] ->
        reject_artifact(id, rest)

      _ ->
        list_work_items(args)
    end
  end

  defp list_work_items(args) do
    {opts, _positional, _invalid} =
      OptionParser.parse(args,
        strict: [status: :string, kind: :string, role: :string, limit: :integer]
      )

    HydraX.Runtime.list_work_items(
      status: opts[:status],
      kind: opts[:kind],
      assigned_role: opts[:role],
      limit: opts[:limit] || 25
    )
    |> Enum.each(fn item ->
      Mix.shell().info(
        Enum.join(
          [
            to_string(item.id),
            item.kind,
            item.status,
            item.assigned_role,
            item.approval_stage,
            item.goal,
            work_item_list_detail(item)
          ],
          "\t"
        )
      )
    end)
  end

  defp show_work_item(id) do
    work_item = HydraX.Runtime.get_work_item!(String.to_integer(id))
    artifacts = HydraX.Runtime.work_item_artifacts(work_item.id)
    approvals = HydraX.Runtime.approval_records_for_subject("work_item", work_item.id)

    Mix.shell().info("work_item=#{work_item.id}")
    Mix.shell().info("kind=#{work_item.kind}")
    Mix.shell().info("status=#{work_item.status}")
    Mix.shell().info("role=#{work_item.assigned_role}")
    Mix.shell().info("approval_stage=#{work_item.approval_stage}")
    Mix.shell().info("execution_mode=#{work_item.execution_mode}")
    Mix.shell().info("goal=#{work_item.goal}")
    maybe_print_recovery_lines(work_item)
    Mix.shell().info("artifacts=#{length(artifacts)}")
    Mix.shell().info("approvals=#{length(approvals)}")

    work_item_follow_up_lines(work_item)
    |> Enum.each(fn line -> Mix.shell().info(line) end)

    Enum.each(artifacts, fn artifact ->
      Mix.shell().info(
        Enum.join(
          [
            "artifact",
            artifact.type,
            artifact.review_status,
            artifact.title || "untitled",
            artifact.summary || ""
          ],
          "\t"
        )
      )

      artifact_delivery_decision_lines(artifact)
      |> Enum.each(fn line -> Mix.shell().info(line) end)

      HydraX.Runtime.artifact_approval_records(artifact.id)
      |> Enum.each(fn record ->
        Mix.shell().info(
          Enum.join(
            [
              "artifact_approval",
              to_string(artifact.id),
              record.requested_action,
              record.decision,
              record.rationale || ""
            ],
            "\t"
          )
        )
      end)
    end)

    Enum.each(approvals, fn record ->
      Mix.shell().info(
        Enum.join(
          [
            "approval",
            record.requested_action,
            record.decision,
            record.rationale || ""
          ],
          "\t"
        )
      )
    end)
  end

  defp approve_work_item(id, rest) do
    {opts, _positional, _invalid} =
      OptionParser.parse(rest, strict: [action: :string, reason: :string])

    action = opts[:action] || "promote_work_item"
    reason = opts[:reason] || "Approved from mix hydra_x.work."

    {work_item, record} =
      HydraX.Runtime.approve_work_item!(String.to_integer(id), %{
        "requested_action" => action,
        "rationale" => reason
      })

    Mix.shell().info("work_item=#{work_item.id}")
    Mix.shell().info("status=#{work_item.status}")
    Mix.shell().info("approval_stage=#{work_item.approval_stage}")
    Mix.shell().info("decision=#{record.decision}")
    Mix.shell().info("action=#{record.requested_action}")
  end

  defp reject_work_item(id, rest) do
    {opts, _positional, _invalid} =
      OptionParser.parse(rest, strict: [action: :string, reason: :string])

    action = opts[:action] || "promote_work_item"
    reason = opts[:reason] || "Rejected from mix hydra_x.work."

    {work_item, record} =
      HydraX.Runtime.reject_work_item!(String.to_integer(id), %{
        "requested_action" => action,
        "rationale" => reason
      })

    Mix.shell().info("work_item=#{work_item.id}")
    Mix.shell().info("status=#{work_item.status}")
    Mix.shell().info("approval_stage=#{work_item.approval_stage}")
    Mix.shell().info("decision=#{record.decision}")
    Mix.shell().info("action=#{record.requested_action}")
  end

  defp show_artifact(id) do
    artifact = HydraX.Runtime.get_artifact!(String.to_integer(id))
    approvals = HydraX.Runtime.artifact_approval_records(artifact.id)

    Mix.shell().info("artifact=#{artifact.id}")
    Mix.shell().info("work_item=#{artifact.work_item_id}")
    Mix.shell().info("type=#{artifact.type}")
    Mix.shell().info("review_status=#{artifact.review_status}")
    Mix.shell().info("title=#{artifact.title || "untitled"}")
    Mix.shell().info("summary=#{artifact.summary || ""}")
    Mix.shell().info("approvals=#{length(approvals)}")

    artifact_delivery_decision_lines(artifact)
    |> Enum.each(fn line -> Mix.shell().info(line) end)

    Enum.each(approvals, fn record ->
      Mix.shell().info(
        Enum.join(
          [
            "approval",
            record.requested_action,
            record.decision,
            record.rationale || ""
          ],
          "\t"
        )
      )
    end)
  end

  defp approve_artifact(id, rest) do
    {opts, _positional, _invalid} =
      OptionParser.parse(rest, strict: [action: :string, reason: :string])

    action = opts[:action] || "promote_artifact"
    reason = opts[:reason] || "Approved from mix hydra_x.work."

    {artifact, record} =
      HydraX.Runtime.approve_artifact!(String.to_integer(id), %{
        "requested_action" => action,
        "rationale" => reason
      })

    Mix.shell().info("artifact=#{artifact.id}")
    Mix.shell().info("review_status=#{artifact.review_status}")
    Mix.shell().info("decision=#{record.decision}")
    Mix.shell().info("action=#{record.requested_action}")
  end

  defp reject_artifact(id, rest) do
    {opts, _positional, _invalid} =
      OptionParser.parse(rest, strict: [action: :string, reason: :string])

    action = opts[:action] || "promote_artifact"
    reason = opts[:reason] || "Rejected from mix hydra_x.work."

    {artifact, record} =
      HydraX.Runtime.reject_artifact!(String.to_integer(id), %{
        "requested_action" => action,
        "rationale" => reason
      })

    Mix.shell().info("artifact=#{artifact.id}")
    Mix.shell().info("review_status=#{artifact.review_status}")
    Mix.shell().info("decision=#{record.decision}")
    Mix.shell().info("action=#{record.requested_action}")
  end

  defp artifact_delivery_decision_lines(artifact) do
    payload = artifact.payload || %{}
    decision_snapshot = Map.get(payload, "delivery_decision_snapshot", %{})

    entry_lines =
      artifact
      |> artifact_delivery_decision_entries()
      |> Enum.take(2)
      |> Enum.with_index(1)
      |> Enum.map(fn {entry, index} ->
        summary =
          case entry["content"] do
            value when is_binary(value) -> value
            _ -> inspect(entry)
          end

        "artifact_detail\t#{artifact.id}\t#{artifact_delivery_decision_kind(payload)}_delivery_decision_#{index}\t#{summary}"
      end)

    snapshot_lines =
      [
        decision_snapshot["prior_summary"] &&
          "artifact_detail\t#{artifact.id}\tdecision_prior\t#{decision_snapshot["prior_summary"]}",
        decision_snapshot["comparison_summary"] &&
          "artifact_detail\t#{artifact.id}\tdecision_comparison\t#{decision_snapshot["comparison_summary"]}"
      ]
      |> Enum.reject(&is_nil/1)

    entry_lines ++ snapshot_lines
  end

  defp artifact_delivery_decision_entries(artifact) do
    payload = artifact.payload || %{}
    decision_snapshot = payload["delivery_decision_snapshot"] || %{}

    case artifact_delivery_decision_kind(payload) do
      "review" ->
        payload
        |> Map.get("delivery_decision_context", [])
        |> List.wrap()

      "synthesis" ->
        payload
        |> Map.get("delivery_decisions", [])
        |> List.wrap()

      "publish" ->
        case decision_snapshot["current_summary"] do
          value when is_binary(value) and value != "" ->
            [%{"content" => value}]

          _ ->
            []
        end

      _ ->
        []
    end
  end

  defp artifact_delivery_decision_kind(%{
         "delivery_decision_snapshot" => %{"decision_scope" => "publish"}
       }),
       do: "publish"

  defp artifact_delivery_decision_kind(%{"decision_type" => "delegation_synthesis"}),
    do: "synthesis"

  defp artifact_delivery_decision_kind(%{"delivery_decision_context" => context})
       when is_list(context) and context != [],
       do: "review"

  defp artifact_delivery_decision_kind(_payload), do: "artifact"

  defp work_item_follow_up_lines(work_item) do
    summary = get_in(work_item.result_refs || %{}, ["follow_up_summary"]) || %{}

    types =
      summary
      |> Map.get("types", [])
      |> List.wrap()

    strategies =
      summary
      |> Map.get("strategies", [])
      |> List.wrap()

    summaries =
      summary
      |> Map.get("summaries", [])
      |> List.wrap()
      |> case do
        [] ->
          summary
          |> Map.get("strategies", [])
          |> List.wrap()
          |> Enum.map(&humanize_follow_up_strategy_summary/1)

        entries ->
          entries
      end

    alternative_strategies =
      summary
      |> Map.get("alternative_strategies", [])
      |> List.wrap()

    alternative_summaries =
      summary
      |> Map.get("alternative_summaries", [])
      |> List.wrap()
      |> case do
        [] ->
          summary
          |> Map.get("alternative_strategies", [])
          |> List.wrap()
          |> Enum.map(&humanize_follow_up_strategy_summary/1)

        entries ->
          entries
      end

    count =
      summary
      |> Map.get("count")
      |> case do
        value when is_integer(value) and value > 0 -> value
        _ -> nil
      end

    base_lines =
      []
      |> maybe_prepend_follow_up_line("follow_up_count", count)
      |> maybe_prepend_follow_up_line("follow_up_types", Enum.join(types, ","))
      |> maybe_prepend_follow_up_line("follow_up_strategies", Enum.join(strategies, ","))
      |> maybe_prepend_follow_up_line("follow_up_summaries", Enum.join(summaries, ","))
      |> maybe_prepend_follow_up_line(
        "follow_up_priority_boosts",
        follow_up_priority_boosts(summary) |> Enum.map(&to_string/1) |> Enum.join(",")
      )
      |> maybe_prepend_follow_up_line(
        "follow_up_alternative_strategies",
        Enum.join(alternative_strategies, ",")
      )
      |> maybe_prepend_follow_up_line(
        "follow_up_alternative_summaries",
        Enum.join(alternative_summaries, ",")
      )

    detail_lines =
      summaries
      |> Enum.with_index(1)
      |> Enum.map(fn {summary, index} ->
        "follow_up_detail\t#{work_item.id}\trecovery_summary_#{index}\t#{summary}"
      end)
      |> Kernel.++(
        follow_up_priority_boosts(summary)
        |> Enum.with_index(1)
        |> Enum.map(fn {boost, index} ->
          "follow_up_detail\t#{work_item.id}\trecovery_priority_#{index}\t+#{boost}"
        end)
      )
      |> Kernel.++(
        alternative_summaries
        |> Enum.with_index(1)
        |> Enum.map(fn {summary, index} ->
          "follow_up_detail\t#{work_item.id}\trecovery_alternative_#{index}\t#{summary}"
        end)
      )

    base_lines ++ detail_lines
  end

  defp maybe_prepend_follow_up_line(lines, _label, nil), do: lines
  defp maybe_prepend_follow_up_line(lines, _label, ""), do: lines

  defp maybe_prepend_follow_up_line(lines, label, value) do
    lines ++ ["#{label}=#{value}"]
  end

  defp follow_up_priority_boosts(summary) do
    summary
    |> Map.get("priority_boosts", [])
    |> List.wrap()
    |> Enum.filter(&is_integer/1)
  end

  defp work_item_list_detail(work_item) do
    [
      derived_recovery_strategy_summary_with_priority(work_item.metadata || %{}),
      follow_up_list_detail(work_item),
      work_item
      |> then(&get_in(&1.result_refs || %{}, ["follow_up_summary", "summaries"]))
      |> List.wrap()
      |> List.first()
    ]
    |> Enum.find("", fn
      value when is_binary(value) -> value != ""
      _ -> false
    end)
  end

  defp follow_up_list_detail(work_item) do
    summary =
      work_item
      |> then(&get_in(&1.result_refs || %{}, ["follow_up_summary", "summaries"]))
      |> List.wrap()
      |> case do
        [] ->
          work_item
          |> then(&get_in(&1.result_refs || %{}, ["follow_up_summary", "strategies"]))
          |> List.wrap()
          |> Enum.map(&humanize_follow_up_strategy_summary/1)

        entries ->
          entries
      end
      |> List.first()

    alternatives =
      work_item
      |> then(&get_in(&1.result_refs || %{}, ["follow_up_summary", "alternative_summaries"]))
      |> List.wrap()
      |> Enum.reject(&(&1 in [nil, ""]))

    case {summary, alternatives} do
      {value, []} when is_binary(value) and value != "" ->
        value

      {value, entries} when is_binary(value) and value != "" and entries != [] ->
        "#{value}; alternatives #{Enum.join(entries, ", ")}"

      _ ->
        nil
    end
  end

  defp derived_recovery_strategy_summary(metadata) do
    case metadata["recovery_strategy_summary"] do
      value when is_binary(value) and value != "" ->
        value

      _ ->
        strategy = metadata["preferred_recovery_strategy"]

        with value when is_binary(value) and value != "" <-
               base_recovery_strategy_summary(strategy) do
          if narrowed_delegation_recovery_alternative?(metadata, strategy) do
            "#{value} with narrowed delegation fallback"
          else
            value
          end
        end
    end
  end

  defp derived_recovery_strategy_summary_with_priority(metadata) do
    summary = derived_recovery_strategy_summary(metadata)
    priority_boost = metadata["recovery_strategy_priority_boost"]

    cond do
      not is_binary(summary) or summary == "" ->
        nil

      is_integer(priority_boost) and priority_boost > 0 ->
        "#{summary} (+#{priority_boost})"

      true ->
        summary
    end
  end

  defp maybe_print_recovery_lines(work_item) do
    metadata = work_item.metadata || %{}

    case derived_recovery_strategy_summary(metadata) do
      value when is_binary(value) and value != "" ->
        Mix.shell().info("recovery_summary=#{value}")

      _ ->
        :ok
    end

    case metadata["recovery_strategy_priority_boost"] do
      value when is_integer(value) and value > 0 ->
        Mix.shell().info("recovery_strategy_priority_boost=#{value}")

      _ ->
        :ok
    end
  end

  defp base_recovery_strategy_summary("review_guided_replan"), do: "Reviewer-guided recovery"
  defp base_recovery_strategy_summary("operator_guided_replan"), do: "Operator-guided recovery"
  defp base_recovery_strategy_summary("request_review"), do: "Review-requested recovery"
  defp base_recovery_strategy_summary("constraint_replan"), do: "Constraint-first recovery"
  defp base_recovery_strategy_summary("narrow_delegate_batch"), do: "Narrowed delegation batch"
  defp base_recovery_strategy_summary(_strategy), do: nil

  defp humanize_follow_up_strategy_summary("review_guided_replan"),
    do: "Reviewer-guided recovery"

  defp humanize_follow_up_strategy_summary("operator_guided_replan"),
    do: "Operator-guided recovery"

  defp humanize_follow_up_strategy_summary("narrow_delegate_batch"),
    do: "Narrowed delegation batch"

  defp humanize_follow_up_strategy_summary("request_review"),
    do: "Review-requested recovery"

  defp humanize_follow_up_strategy_summary("constraint_replan"),
    do: "Constraint-first recovery"

  defp humanize_follow_up_strategy_summary(strategy) when is_binary(strategy), do: strategy
  defp humanize_follow_up_strategy_summary(_strategy), do: nil

  defp narrowed_delegation_recovery_alternative?(metadata, strategy) do
    strategy != "narrow_delegate_batch" and
      ("narrow_delegate_batch" in List.wrap(metadata["recovery_strategy_alternatives"]) or
         "Narrowed delegation batch" in List.wrap(
           metadata["recovery_strategy_alternative_summaries"]
         ))
  end
end
