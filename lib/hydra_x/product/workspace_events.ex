defmodule HydraX.Product.WorkspaceEvents do
  @moduledoc """
  Context for `HydraX.Product.WorkspaceEvent`. Provides an asynchronous
  fire-and-forget `log/1` that persists workspace operations for later
  inspection by Phase 1 (branching) and Phase 2 (code-aware compaction).
  """

  import Ecto.Query, only: [from: 2]

  alias HydraX.Product.Workspace
  alias HydraX.Product.WorkspaceEvent
  alias HydraX.Repo

  @doc """
  Persist a workspace event row. Called from inside `Backend.Host` after
  every operation. Writes are best-effort: if the audit insert fails we log
  and swallow rather than fail the underlying op.
  """
  def log(%Workspace{id: ws_id, project_id: project_id}, attrs) when is_map(attrs) do
    base = %{workspace_id: ws_id, project_id: project_id}

    %WorkspaceEvent{}
    |> WorkspaceEvent.changeset(Map.merge(base, attrs))
    |> Repo.insert()
    |> case do
      {:ok, event} ->
        {:ok, event}

      {:error, changeset} ->
        require Logger
        Logger.warning("workspace_event audit insert failed: #{inspect(changeset.errors)}")
        :error
    end
  end

  @doc "List events for a workspace, newest first."
  def list_for_workspace(workspace_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 200)

    from(e in WorkspaceEvent,
      where: e.workspace_id == ^workspace_id,
      order_by: [desc: e.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc "List events for a project, newest first."
  def list_for_project(project_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 200)

    from(e in WorkspaceEvent,
      where: e.project_id == ^project_id,
      order_by: [desc: e.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end
end
