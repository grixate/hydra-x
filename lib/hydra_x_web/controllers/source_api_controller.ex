defmodule HydraXWeb.SourceAPIController do
  use HydraXWeb, :controller

  alias HydraX.Product
  alias HydraX.Product.Source
  alias HydraXWeb.ProductPayload

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def index(conn, %{"project_id" => project_id}) do
    sources =
      Product.list_sources(project_id,
        processing_status: conn.params["processing_status"],
        source_type: conn.params["source_type"],
        search: conn.params["search"]
      )
      |> Enum.map(&ProductPayload.source_json(&1, false))

    json(conn, %{data: sources})
  end

  def show(conn, %{"project_id" => project_id, "id" => id}) do
    source =
      project_id
      |> Product.get_project_source!(parse_integer(id))
      |> ProductPayload.source_json(true)

    json(conn, %{data: source})
  end

  def create(conn, %{"project_id" => project_id, "source" => params}) do
    with {:ok, %Source{} = source} <- Product.create_source(project_id, params) do
      conn
      |> put_status(:created)
      |> json(%{data: ProductPayload.source_json(source, true)})
    end
  end

  def delete(conn, %{"project_id" => project_id, "id" => id}) do
    source = Product.get_project_source!(project_id, parse_integer(id))

    with {:ok, %Source{}} <- Product.delete_source(source) do
      send_resp(conn, :no_content, "")
    end
  end

  defp parse_integer(value) do
    value
    |> to_string()
    |> String.to_integer()
  end
end
