defmodule HydraXWeb.ArtifactAPIController do
  use HydraXWeb, :controller

  alias HydraX.Product
  alias HydraX.Product.Artifact
  alias HydraXWeb.ProductPayload

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def index(conn, %{"project_id" => project_id}) do
    artifacts =
      Product.list_artifacts(project_id, status: conn.params["status"])
      |> Enum.map(&ProductPayload.artifact_json/1)

    json(conn, %{data: artifacts})
  end

  def show(conn, %{"project_id" => project_id, "id" => id}) do
    artifact = ProductPayload.artifact_json(Product.get_artifact!(project_id, id))
    json(conn, %{data: artifact})
  end

  def create(conn, %{"project_id" => project_id, "artifact" => params}) do
    with {:ok, %Artifact{} = artifact} <- Product.create_artifact(project_id, params) do
      conn
      |> put_status(:created)
      |> json(%{data: ProductPayload.artifact_json(artifact)})
    end
  end

  def update(conn, %{"project_id" => project_id, "id" => id, "artifact" => params}) do
    with {:ok, %Artifact{} = updated} <- Product.update_artifact(project_id, id, params) do
      json(conn, %{data: ProductPayload.artifact_json(updated)})
    end
  end

  def versions(conn, %{"project_id" => project_id, "id" => id}) do
    versions =
      Product.list_artifact_versions(project_id, id)
      |> Enum.map(&ProductPayload.artifact_version_json/1)

    json(conn, %{data: versions})
  end
end
