defmodule Mix.Tasks.HydraX.Work do
  use Mix.Task

  @shortdoc "Lists, inspects, approves, and rejects autonomy work items"

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
end
