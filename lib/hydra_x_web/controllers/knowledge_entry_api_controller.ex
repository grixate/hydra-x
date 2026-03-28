defmodule HydraXWeb.KnowledgeEntryAPIController do
  use HydraXWeb, :controller

  alias HydraX.Product
  alias HydraX.Product.KnowledgeEntry
  alias HydraXWeb.ProductPayload

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def index(conn, %{"project_id" => project_id}) do
    entries =
      Product.list_knowledge_entries(project_id,
        status: conn.params["status"],
        persona: conn.params["persona"]
      )
      |> Enum.map(&ProductPayload.knowledge_entry_json/1)

    json(conn, %{data: entries})
  end

  def show(conn, %{"project_id" => project_id, "id" => id}) do
    entry = project_id |> Product.get_project_knowledge_entry!(id) |> ProductPayload.knowledge_entry_json()
    json(conn, %{data: entry})
  end

  def create(conn, %{"project_id" => project_id, "knowledge_entry" => params}) do
    with {:ok, %KnowledgeEntry{} = entry} <- Product.create_knowledge_entry(project_id, params) do
      conn |> put_status(:created) |> json(%{data: ProductPayload.knowledge_entry_json(entry)})
    end
  end

  def update(conn, %{"project_id" => project_id, "id" => id, "knowledge_entry" => params}) do
    entry = Product.get_project_knowledge_entry!(project_id, id)
    with {:ok, %KnowledgeEntry{} = updated} <- Product.update_knowledge_entry(entry, params) do
      json(conn, %{data: ProductPayload.knowledge_entry_json(updated)})
    end
  end

  def delete(conn, %{"project_id" => project_id, "id" => id}) do
    entry = Product.get_project_knowledge_entry!(project_id, id)
    with {:ok, %KnowledgeEntry{}} <- Product.delete_knowledge_entry(entry) do
      send_resp(conn, :no_content, "")
    end
  end
end
