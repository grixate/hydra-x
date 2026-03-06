defmodule HydraX.Workspace do
  @moduledoc """
  Access to the Hydra-X workspace contract files.
  """

  @contract_files ~w(SOUL.md IDENTITY.md USER.md TOOLS.md HEARTBEAT.md)

  def contract_files, do: @contract_files

  def load_context(workspace_root) do
    @contract_files
    |> Enum.map(fn file ->
      path = Path.join(workspace_root, file)
      {file, if(File.exists?(path), do: File.read!(path), else: "")}
    end)
    |> Enum.into(%{})
  end

  def ensure_paths(workspace_root) do
    for path <- [
          workspace_root,
          Path.join(workspace_root, "memory"),
          Path.join(workspace_root, "memory/daily"),
          Path.join(workspace_root, "skills"),
          Path.join(workspace_root, "ingest")
        ] do
      File.mkdir_p!(path)
    end

    :ok
  end
end
