defmodule HydraXWeb.ProjectExportAPIController do
  use HydraXWeb, :controller

  alias HydraX.Product

  def create(conn, %{"project_id" => project_id}) do
    export = Product.export_project_snapshot(project_id)

    json(conn, %{
      data: %{
        project_id: export.project.id,
        markdown_path: export.markdown_path,
        json_path: export.json_path,
        bundle_dir: export.bundle_dir,
        counts: %{
          sources: length(export.snapshot.sources),
          insights: length(export.snapshot.insights),
          requirements: length(export.snapshot.requirements),
          conversations: length(export.snapshot.conversations)
        }
      }
    })
  end
end
