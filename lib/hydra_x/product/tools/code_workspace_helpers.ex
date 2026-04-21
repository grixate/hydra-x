defmodule HydraX.Product.Tools.CodeWorkspaceHelpers do
  @moduledoc """
  Shared helpers for the `code_*` tool family. Resolves the project id from
  the tool execution context, ensures a workspace exists for it, and runs the
  given backend operation against it.
  """

  alias HydraX.Product.Project
  alias HydraX.Product.Workspace
  alias HydraX.Product.Workspace.Backend
  alias HydraX.Product.Workspaces
  alias HydraX.Repo

  @doc """
  Resolves a workspace from the tool execution `context`, ensures it is
  ready, then invokes `fun.(backend_module, workspace)`. Returns whatever
  `fun` returns, or `{:error, reason}` if the workspace can't be resolved.
  """
  def with_workspace(context, fun) when is_function(fun, 2) do
    with {:ok, project_id} <- fetch_project_id(context),
         {:ok, project} <- fetch_project(project_id),
         {:ok, workspace} <- ensure_workspace(project) do
      backend = Backend.for_workspace(workspace)
      _ = Workspaces.touch(workspace)
      fun.(backend, workspace)
    end
  end

  @doc "Pulls and validates the relative path argument from the tool params."
  def fetch_path(params) do
    case params[:path] || params["path"] do
      path when is_binary(path) and path != "" -> {:ok, path}
      _ -> {:error, :missing_path}
    end
  end

  defp fetch_project_id(context) do
    case context[:product_project_id] do
      id when is_integer(id) and id > 0 -> {:ok, id}
      id when is_binary(id) -> parse_int(id)
      _ -> {:error, :missing_project_id}
    end
  end

  defp parse_int(str) do
    case Integer.parse(str) do
      {n, ""} when n > 0 -> {:ok, n}
      _ -> {:error, :invalid_project_id}
    end
  end

  defp fetch_project(project_id) do
    case Repo.get(Project, project_id) do
      nil -> {:error, :project_not_found}
      %Project{} = project -> {:ok, project}
    end
  end

  defp ensure_workspace(%Project{} = project) do
    case Workspaces.get_for_project(project.id) do
      nil ->
        Workspaces.provision(project)

      %Workspace{status: "ready"} = ws ->
        {:ok, ws}

      %Workspace{} = ws ->
        Workspaces.ensure_ready(ws)
    end
  end
end
