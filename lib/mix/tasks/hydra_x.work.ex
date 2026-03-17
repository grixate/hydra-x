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
            item.goal
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
    Mix.shell().info("artifacts=#{length(artifacts)}")
    Mix.shell().info("approvals=#{length(approvals)}")

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

    case artifact_delivery_decision_kind(payload) do
      "review" ->
        payload
        |> Map.get("delivery_decision_context", [])
        |> List.wrap()

      "synthesis" ->
        payload
        |> Map.get("delivery_decisions", [])
        |> List.wrap()

      _ ->
        []
    end
  end

  defp artifact_delivery_decision_kind(%{"decision_type" => "delegation_synthesis"}),
    do: "synthesis"

  defp artifact_delivery_decision_kind(%{"delivery_decision_context" => context})
       when is_list(context) and context != [],
       do: "review"

  defp artifact_delivery_decision_kind(_payload), do: "artifact"
end
