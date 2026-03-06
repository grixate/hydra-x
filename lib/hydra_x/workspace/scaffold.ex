defmodule HydraX.Workspace.Scaffold do
  @moduledoc """
  Copies the repository workspace template into a target directory without overwriting user edits.
  """

  alias HydraX.Workspace

  @template_root Path.expand("../../../workspace_template", __DIR__)

  def copy_template!(destination_root) do
    Workspace.ensure_paths(destination_root)

    @template_root
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.reject(&File.dir?/1)
    |> Enum.each(fn source ->
      relative = Path.relative_to(source, @template_root)
      destination = Path.join(destination_root, relative)

      File.mkdir_p!(Path.dirname(destination))

      if not File.exists?(destination) do
        File.cp!(source, destination)
      end
    end)

    destination_root
  end
end
