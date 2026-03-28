defmodule HydraXWeb.GraphHealthAPIController do
  use HydraXWeb, :controller

  alias HydraX.Product.Graph
  alias HydraXWeb.ProductPayload

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def show(conn, %{"project_id" => project_id}) do
    project_id = parse_int(project_id)
    density = Graph.density_report(project_id)
    flags = Graph.open_flags(project_id)
    orphans = Graph.orphaned_nodes(project_id)
    stale = Graph.stale_nodes(project_id)

    json(conn, %{
      data: %{
        density: density,
        open_flags: Enum.map(flags, &ProductPayload.graph_flag_json/1),
        open_flag_count: length(flags),
        orphaned_nodes: orphans,
        orphan_count: length(orphans),
        stale_nodes: stale,
        stale_count: length(stale)
      }
    })
  end

  defp parse_int(value) when is_integer(value), do: value
  defp parse_int(value) when is_binary(value), do: String.to_integer(value)
end
