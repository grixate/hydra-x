defmodule HydraX.Product.ResearcherAutoProcess do
  @moduledoc """
  Stream A1.3 — automatically enqueue Researcher analysis when a source
  is added to the Library.

  Creates an `AgentTask` so the work is visible in CC Zone 2 and the user
  can observe/cancel/redirect it. The actual LLM prompt is submitted via
  `AgentBridge`, matching the existing manual-analyze path.

  Controlled by `project.metadata["auto_process_sources"]` — defaults to
  `true` when unset (matches the spec's "default true" contract).
  """

  require Logger

  alias HydraX.Product
  alias HydraX.Product.AgentBridge
  alias HydraX.Product.AgentTasks
  alias HydraX.Product.Source

  @doc """
  Enqueue researcher analysis for a newly-created source. Respects the
  per-project `metadata.auto_process_sources` flag; returns `:disabled`
  if the user has opted out.
  """
  def maybe_enqueue(%Source{} = source) do
    project = Product.get_project!(source.project_id)

    if auto_process_enabled?(project) do
      enqueue(source)
    else
      :disabled
    end
  end

  def enqueue(%Source{} = source) do
    case AgentTasks.create_task(%{
           project_id: source.project_id,
           agent_id: "researcher",
           title: "Analysing: #{source.title}",
           description: "Auto-triggered on source ingest.",
           state: "running",
           priority: "normal",
           assigned_by: "system",
           context_type: "library_source",
           context_id: source.id
         }) do
      {:ok, task} ->
        # Run the LLM analysis asynchronously under the TaskSupervisor so
        # the HTTP response returns quickly. Completion transitions the
        # AgentTask, which broadcasts to CC/Stream + emits a StreamEntry.
        {:ok, _pid} =
          Task.Supervisor.start_child(HydraX.TaskSupervisor, fn ->
            run_analysis(source, task)
          end)

        {:ok, task}

      {:error, changeset} ->
        Logger.warning(
          "[ResearcherAutoProcess] failed to enqueue task for source=#{source.id}: " <>
            inspect(changeset.errors)
        )

        {:error, changeset}
    end
  end

  defp auto_process_enabled?(project) do
    case Map.get(project.metadata || %{}, "auto_process_sources") do
      false -> false
      "false" -> false
      _ -> true
    end
  end

  defp run_analysis(source, task) do
    prompt = """
    Analyse this newly-added source and extract key insights.

    Title: #{source.title}
    Type: #{source.source_type}

    Content (first 3000 chars):
    #{String.slice(source.content || "", 0, 3000)}

    Create insights for any significant findings. Each insight should have:
    - A clear, specific title
    - A body explaining the finding with evidence
    - A confidence level (high/medium/low)

    Connect each insight to this source via lineage.
    """

    metadata = %{
      "channel" => "source_processing",
      "external_ref" => "source_analysis_#{source.id}",
      "title" => "Analysing: #{source.title}",
      "metadata" => %{
        "source_id" => source.id,
        "agent_task_id" => task.id
      }
    }

    {:ok, conversation} =
      AgentBridge.ensure_project_conversation(source.project_id, "researcher", metadata)

    _ =
      AgentBridge.submit_message(conversation, prompt, %{
        "source_id" => source.id,
        "agent_task_id" => task.id,
        "auto_processing" => true
      })

    AgentTasks.transition(task, "completed", reason: "source analysis complete")
  rescue
    err ->
      Logger.warning(
        "[ResearcherAutoProcess] analysis raised for source=#{source.id}: #{inspect(err)}"
      )

      # Best-effort transition to `failed` so CC reflects reality.
      try do
        AgentTasks.transition(task, "failed", reason: "exception during analysis")
      rescue
        _ -> :ok
      end
  end
end
