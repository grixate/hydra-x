defmodule HydraX.Safety.PathGuard do
  @moduledoc """
  Resolves workspace-relative paths while preventing traversal outside the workspace.
  """

  def resolve_workspace_path(workspace_root, candidate_path)
      when is_binary(workspace_root) and is_binary(candidate_path) do
    workspace_root = Path.expand(workspace_root)
    candidate_path = String.trim(candidate_path)

    if candidate_path in ["", ".", ".."] do
      {:error, :invalid_path}
    else
      resolved = Path.expand(candidate_path, workspace_root)
      prefix = workspace_root <> "/"

      cond do
        resolved == workspace_root -> {:ok, resolved}
        String.starts_with?(resolved, prefix) -> {:ok, resolved}
        true -> {:error, :path_outside_workspace}
      end
    end
  end

  def resolve_workspace_path(_workspace_root, _candidate_path), do: {:error, :invalid_path}
end
