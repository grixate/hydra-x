defmodule HydraXWeb.OnboardingAPIController do
  @moduledoc """
  Per the Hydra Onboarding spec, the only persistent onboarding state is
  a per-project boolean: `has_completed_first_session`. This controller
  exposes its read and mark-completed endpoints. The fork-screen flow
  lives entirely in the frontend; the backend's only job is to suppress
  the fork screen on subsequent project entries.
  """
  use HydraXWeb, :controller

  alias HydraX.Product

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def show(conn, %{"project_id" => project_id}) do
    project = Product.get_project!(project_id)
    json(conn, %{data: serialize(project)})
  end

  def mark_completed(conn, %{"project_id" => project_id}) do
    project = Product.get_project!(project_id)

    with {:ok, updated} <- Product.mark_first_session_completed(project) do
      json(conn, %{data: serialize(updated)})
    end
  end

  @doc """
  Apply the built-in `product_development` pretrained schema to this
  project. Per the Part 1 amendment, projects start blank; scenarios
  that need the substrate (e.g. materials ingestion) call this first.
  Idempotent — re-applying is a no-op for already-defined types.
  """
  def apply_pretrained(conn, %{"project_id" => project_id}) do
    project = Product.get_project!(project_id)
    :ok = HydraX.PretrainedProjects.ProductDevelopment.apply_to_project(project.id)
    json(conn, %{data: %{project_id: project.id, applied: "product_development"}})
  end

  defp serialize(project) do
    %{
      project_id: project.id,
      has_completed_first_session: project.has_completed_first_session
    }
  end
end
