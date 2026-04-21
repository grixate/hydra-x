defmodule HydraXWeb.OnboardingAPIController do
  use HydraXWeb, :controller

  alias HydraX.Product
  alias HydraX.Product.OnboardingFlow

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def show(conn, %{"project_id" => project_id}) do
    project = Product.get_project!(project_id)
    json(conn, %{data: serialize(project, OnboardingFlow.status(project))})
  end

  def start(conn, %{"project_id" => project_id}) do
    project = Product.get_project!(project_id)

    with {:ok, updated} <- OnboardingFlow.start(project) do
      json(conn, %{data: serialize(updated, OnboardingFlow.status(updated))})
    end
  end

  def skip(conn, %{"project_id" => project_id}) do
    project = Product.get_project!(project_id)

    with {:ok, updated} <- OnboardingFlow.skip(project) do
      json(conn, %{data: serialize(updated, OnboardingFlow.status(updated))})
    end
  end

  def reset(conn, %{"project_id" => project_id}) do
    project = Product.get_project!(project_id)

    with {:ok, updated} <- OnboardingFlow.reset(project) do
      json(conn, %{data: serialize(updated, OnboardingFlow.status(updated))})
    end
  end

  defp serialize(project, status) do
    %{
      project_id: project.id,
      state: status.state,
      vision_set: status.vision_set,
      bets_count: status.bets_count,
      hint: status.hint,
      onboarded_at: project.onboarded_at,
      onboarding_skipped_at: project.onboarding_skipped_at
    }
  end
end
