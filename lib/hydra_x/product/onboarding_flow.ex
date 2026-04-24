defmodule HydraX.Product.OnboardingFlow do
  @moduledoc """
  Onboarding state machine for the Hydra first-project experience
  (spec: `onboarding-spec.md`).

  Distinct from `HydraX.Product.Onboarding`, which seeds the initial
  "Getting started" board session at project creation. This module owns
  the *user-facing progression* through states:

    * `pending`      — fresh project; Vision not set, chat not yet begun.
                       Frontend shows the onboarding banner.
    * `in_progress`  — user has started the Strategist conversation, set
                       a Vision, or created nodes manually. Banner stays
                       visible with adaptive copy.
    * `completed`    — Vision text set (`project.description`) AND at
                       least one Strategy node exists (the first Strategic
                       Bet). Banner hidden.
    * `skipped`      — user explicitly clicked "Skip for now". Banner
                       collapses; surfaces still offer a resume CTA.

  Transitions are driven by explicit user actions (start / skip / reset)
  OR automatically when `auto_progress/1` observes the project meeting
  the `in_progress` / `completed` criteria.
  """

  import Ecto.Query

  alias HydraX.Repo
  alias HydraX.Product.Project

  @type status_result :: %{
          state: String.t(),
          vision_set: boolean(),
          bets_count: non_neg_integer(),
          hint: String.t() | nil
        }

  ## Status / derived hints

  def status(%Project{} = project) do
    %{
      state: project.onboarding_state,
      vision_set: vision_set?(project),
      bets_count: count_strategies(project.id),
      hint: hint_for(project)
    }
  end

  def status(project_id) when is_integer(project_id) or is_binary(project_id) do
    project_id |> load_project!() |> status()
  end

  ## Explicit transitions

  def start(%Project{onboarding_state: "pending"} = project) do
    update_state(project, "in_progress", %{})
  end

  def start(%Project{} = project), do: {:ok, project}

  def skip(%Project{} = project) do
    update_state(project, "skipped", %{onboarding_skipped_at: DateTime.utc_now()})
  end

  def complete(%Project{} = project) do
    update_state(project, "completed", %{onboarded_at: DateTime.utc_now()})
  end

  def reset(%Project{} = project) do
    update_state(project, "pending", %{onboarded_at: nil, onboarding_skipped_at: nil})
  end

  @doc """
  Re-evaluate a project against the completion criteria and transition if
  appropriate. Idempotent — call any time project state might have changed
  (Vision text set, Strategy node created, etc.).
  """
  def auto_progress(%Project{onboarding_state: "completed"} = project), do: {:ok, project}
  def auto_progress(%Project{onboarding_state: "skipped"} = project), do: {:ok, project}

  def auto_progress(%Project{} = project) do
    cond do
      vision_set?(project) and count_strategies(project.id) >= 1 ->
        complete(project)

      project.onboarding_state == "pending" and
          (vision_set?(project) or has_any_node?(project.id)) ->
        update_state(project, "in_progress", %{})

      true ->
        {:ok, project}
    end
  end

  def auto_progress(project_id) when is_integer(project_id) or is_binary(project_id) do
    project_id |> load_project!() |> auto_progress()
  end

  ## Private

  defp update_state(%Project{} = project, next_state, extra) do
    attrs =
      extra
      |> Map.put(:onboarding_state, next_state)
      |> Map.new(fn {k, v} -> {to_string(k), v} end)

    project
    |> Project.changeset(attrs)
    |> Repo.update()
  end

  defp vision_set?(%Project{} = project) do
    case HydraX.Product.Visions.get_for_project(project.id) do
      %HydraX.Graph.Node{type_key: "vision", body: body} when is_binary(body) ->
        String.trim(body) != ""

      _ ->
        description_set?(project)
    end
  end

  defp vision_set?(_), do: false

  defp description_set?(%Project{description: desc}) when is_binary(desc),
    do: String.trim(desc) != ""

  defp description_set?(_), do: false

  defp count_strategies(project_id) do
    HydraX.Graph.Node
    |> where([s], s.project_id == ^project_id and s.type_key == "strategy")
    |> Repo.aggregate(:count, :id)
  end

  defp has_any_node?(project_id) do
    count_strategies(project_id) > 0 or
      Repo.exists?(
        from n in HydraX.Graph.Node,
          where:
            n.project_id == ^project_id and n.type_key in ["insight", "decision", "requirement"]
      )
  end

  defp hint_for(%Project{onboarding_state: "pending"}),
    do: "Hi — I'm the Strategist. Let's figure out what you're trying to do."

  defp hint_for(%Project{onboarding_state: "in_progress"} = project) do
    cond do
      vision_set?(project) and count_strategies(project.id) == 0 ->
        "Vision is set. Want to talk through what bets you're placing on it?"

      vision_set?(project) ->
        "You're underway. Keep developing the strategy, or explore the graph."

      true ->
        "Welcome back. Want to continue where we left off, or start fresh?"
    end
  end

  defp hint_for(%Project{onboarding_state: "skipped"}),
    do: "You can start the Strategist conversation any time."

  defp hint_for(%Project{onboarding_state: "completed"}), do: nil

  defp load_project!(id), do: Repo.get!(Project, to_int(id))

  defp to_int(v) when is_integer(v), do: v
  defp to_int(v) when is_binary(v), do: String.to_integer(v)
end
