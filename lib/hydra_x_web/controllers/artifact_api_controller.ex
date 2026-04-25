defmodule HydraXWeb.ArtifactAPIController do
  use HydraXWeb, :controller

  alias HydraX.Graph.Node, as: GraphNode
  alias HydraX.Product
  alias HydraXWeb.ProductPayload

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def index(conn, %{"project_id" => project_id} = params) do
    opts =
      []
      |> then(fn o -> if params["status"], do: [{:status, params["status"]} | o], else: o end)
      |> then(fn o ->
        if params["artifact_type"], do: [{:artifact_type, params["artifact_type"]} | o], else: o
      end)
      |> then(fn o -> if params["search"], do: [{:search, params["search"]} | o], else: o end)

    artifacts =
      Product.list_artifacts(project_id, opts)
      |> Enum.map(&ProductPayload.artifact_json/1)

    json(conn, %{data: artifacts})
  end

  def show(conn, %{"project_id" => project_id, "id" => id}) do
    artifact = ProductPayload.artifact_json(Product.get_artifact!(project_id, id))
    json(conn, %{data: artifact})
  end

  def create(conn, %{"project_id" => project_id, "artifact" => params}) do
    with {:ok, %GraphNode{} = artifact} <- Product.create_artifact(project_id, params) do
      conn
      |> put_status(:created)
      |> json(%{data: ProductPayload.artifact_json(artifact)})
    end
  end

  def update(conn, %{"project_id" => project_id, "id" => id, "artifact" => params}) do
    with {:ok, %GraphNode{} = updated} <- Product.update_artifact(project_id, id, params) do
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
