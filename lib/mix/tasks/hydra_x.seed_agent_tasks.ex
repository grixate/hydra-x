defmodule Mix.Tasks.HydraX.SeedAgentTasks do
  @moduledoc """
  Seed a project with sample agent tasks covering every state so the
  Command Center UI can be developed without live agent integration.

  Usage:

      mix hydra_x.seed_agent_tasks PROJECT_ID

  Clears existing agent_tasks for the project first.
  """

  use Mix.Task

  alias HydraX.Product.AgentTask
  alias HydraX.Product.AgentTasks
  alias HydraX.Repo

  import Ecto.Query

  @shortdoc "Seed sample agent tasks for the Command Center"

  @samples [
    %{
      agent_id: "researcher",
      title: "Processing Q3 interview transcripts",
      description: "Extracting insights from 12 new customer interviews.",
      state: "running",
      priority: "high",
      progress_current: 8,
      progress_total: 12,
      progress_label: "interviews"
    },
    %{
      agent_id: "researcher",
      title: "Analysing competitor pricing pages",
      description: "Scraping and summarising pricing tiers across 6 competitors.",
      state: "running",
      priority: "normal",
      progress_current: 3,
      progress_total: 6,
      progress_label: "competitors"
    },
    %{
      agent_id: "strategist",
      title: "Waiting on your decision: pricing bet prioritisation",
      description: "Which of the 3 pricing bets should we move forward with?",
      state: "waiting_for_input",
      priority: "high"
    },
    %{
      agent_id: "strategist",
      title: "Consolidating bets into themes",
      state: "proposing",
      priority: "normal",
      proposal_payload: %{
        "summary" => "Strategist suggests consolidating 9 bets into 3 themes",
        "preview" => "Theme A (enterprise), Theme B (self-serve), Theme C (platform)",
        "type" => "restructure",
        "items" => []
      }
    },
    %{
      agent_id: "architect",
      title: "Mapping auth subsystem dependencies",
      state: "blocked",
      state_reason: "Missing source access to legacy repo",
      priority: "normal"
    },
    %{
      agent_id: "designer",
      title: "Drafting Command Center mocks",
      state: "paused",
      priority: "low"
    },
    %{
      agent_id: "memory_agent",
      title: "Indexing recently-added sources",
      state: "running",
      priority: "normal",
      progress_current: 47,
      progress_total: 60,
      progress_label: "chunks"
    },
    %{
      agent_id: "coherence",
      title: "Found 2 contradictions in pricing bets",
      state: "proposing",
      priority: "high",
      proposal_payload: %{
        "summary" => "Coherence found 2 contradictions in pricing bets",
        "preview" => "Bet #4 contradicts Bet #7 on pricing floor",
        "type" => "contradiction",
        "items" => []
      }
    },
    %{
      agent_id: "continuous_research",
      title: "Monitoring competitor changelogs",
      state: "running",
      priority: "low"
    },
    %{
      agent_id: "researcher",
      title: "Initial literature scan",
      state: "completed",
      priority: "normal"
    },
    %{
      agent_id: "architect",
      title: "Provider integration draft",
      state: "failed",
      state_reason: "Upstream API returned 503 after 3 retries",
      priority: "normal",
      error_payload: %{"error_type" => "upstream_unavailable", "retryable" => true}
    }
  ]

  @impl Mix.Task
  def run([project_id_str]) do
    Mix.Task.run("app.start")
    project_id = String.to_integer(project_id_str)

    Mix.shell().info("Clearing existing agent_tasks for project #{project_id}...")

    Repo.delete_all(from t in AgentTask, where: t.project_id == ^project_id)

    Mix.shell().info("Seeding #{length(@samples)} agent tasks...")

    Enum.each(@samples, fn attrs ->
      attrs =
        attrs
        |> Map.put(:project_id, project_id)
        |> Map.put_new(:assigned_by, "system")

      case AgentTasks.create_task(attrs) do
        {:ok, task} -> Mix.shell().info("  [#{task.state}] #{task.agent_id}: #{task.title}")
        {:error, changeset} -> Mix.shell().error("  FAILED: #{inspect(changeset.errors)}")
      end
    end)

    Mix.shell().info("Done.")
  end

  def run(_) do
    Mix.shell().error("Usage: mix hydra_x.seed_agent_tasks PROJECT_ID")
    exit({:shutdown, 1})
  end
end
