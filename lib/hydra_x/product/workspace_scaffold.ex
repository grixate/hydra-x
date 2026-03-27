defmodule HydraX.Product.WorkspaceScaffold do
  @moduledoc false

  alias HydraX.Workspace

  @base_template_root Path.expand("../../../workspace_template", __DIR__)
  @product_template_root Path.expand("../../../product_workspace_templates", __DIR__)

  def scaffold!(destination_root, persona, project_name, project_slug) do
    Workspace.ensure_paths(destination_root)

    assigns = %{
      "project_name" => project_name,
      "project_slug" => project_slug,
      "persona" => to_string(persona)
    }

    copy_tree!(@base_template_root, destination_root, assigns)
    copy_tree!(Path.join(@product_template_root, to_string(persona)), destination_root, assigns)
    destination_root
  end

  defp copy_tree!(source_root, destination_root, assigns) do
    source_root
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.reject(&File.dir?/1)
    |> Enum.each(fn source ->
      relative = Path.relative_to(source, source_root)
      destination = Path.join(destination_root, relative)

      File.mkdir_p!(Path.dirname(destination))

      content =
        source
        |> File.read!()
        |> render_template(assigns)

      File.write!(destination, content)
    end)
  end

  defp render_template(content, assigns) do
    Enum.reduce(assigns, content, fn {key, value}, acc ->
      String.replace(acc, "{{#{key}}}", value)
    end)
  end
end
