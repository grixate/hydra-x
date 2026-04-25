defmodule HydraX.Product.Workspaces do
  @moduledoc """
  Context module for `HydraX.Product.Workspace` rows: lookup, create, update,
  and resolve the on-disk root path.
  """

  import Ecto.Query, only: [where: 3, order_by: 3]

  alias HydraX.Product.Project
  alias HydraX.Product.Workspace
  alias HydraX.Product.Workspace.Backend
  alias HydraX.Repo

  @doc """
  Returns the absolute filesystem root under which all per-project workspace
  directories live. Configurable via `config :hydra_x, :workspace_root`;
  defaults to `~/.hydra_x/workspaces`.
  """
  def root_path do
    case Application.get_env(:hydra_x, :workspace_root) do
      nil -> Path.join([System.user_home!(), ".hydra_x", "workspaces"])
      path when is_binary(path) -> Path.expand(path)
    end
  end

  @doc "Returns the absolute path for a given project's workspace directory."
  def project_path(project_id) when is_integer(project_id) do
    Path.join(root_path(), Integer.to_string(project_id))
  end

  @doc "Fetch the workspace row for a project, or `nil` if none."
  def get_for_project(project_id) when is_integer(project_id) do
    Repo.get_by(Workspace, project_id: project_id)
  end

  @doc "Fetch by id, raising if missing."
  def get!(id), do: Repo.get!(Workspace, id)

  @doc "Insert a workspace row."
  def create(attrs) do
    %Workspace{}
    |> Workspace.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Update an existing workspace row."
  def update(%Workspace{} = workspace, attrs) do
    workspace
    |> Workspace.changeset(attrs)
    |> Repo.update()
  end

  @doc "Delete a workspace row. Does not touch the filesystem."
  def delete(%Workspace{} = workspace), do: Repo.delete(workspace)

  @doc "List all workspaces, optionally filtered by status."
  def list(opts \\ []) do
    status = Keyword.get(opts, :status)

    Workspace
    |> maybe_filter_status(status)
    |> order_by([w], desc: w.last_used_at)
    |> Repo.all()
  end

  @doc """
  Stamp the `last_used_at` field to now via a single-column UPDATE so we
  don't risk clobbering other fields with a stale in-memory copy.
  Always returns `:ok` (touch is fire-and-forget).
  """
  def touch(%Workspace{id: id}) when is_integer(id) do
    now = DateTime.utc_now()

    Workspace
    |> where([w], w.id == ^id)
    |> Repo.update_all(set: [last_used_at: now, updated_at: now])

    :ok
  end

  def touch(_), do: :ok

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: where(query, [w], w.status == ^status)

  # ---------------------------------------------------------------------------
  # Lifecycle
  # ---------------------------------------------------------------------------

  @doc """
  Provision a workspace for a project. Creates the row if missing, materializes
  the on-disk root directory via the configured backend, writes a default
  `HYDRA.md` template if none exists, and marks the row `"ready"`.

  Idempotent: calling on an existing workspace re-runs `ensure_ready/1`.
  """
  def provision(%Project{id: project_id}, opts \\ []) do
    git_origin = Keyword.get(opts, :git_origin)
    sandbox_mode = Keyword.get(opts, :sandbox_mode, "host")

    case get_for_project(project_id) do
      nil ->
        attrs = %{
          project_id: project_id,
          fs_path: project_path(project_id),
          sandbox_mode: sandbox_mode,
          status: "provisioning",
          git_origin: git_origin
        }

        with {:ok, workspace} <- create(attrs),
             {:ok, ready} <- materialize(workspace) do
          {:ok, ready}
        end

      %Workspace{} = existing ->
        ensure_ready(existing)
    end
  end

  @doc """
  Ensures the on-disk root exists for an already-rowed workspace, writes the
  default `HYDRA.md` template if absent, and stamps `status: "ready"`.
  """
  def ensure_ready(%Workspace{} = workspace) do
    materialize(workspace)
  end

  @doc "Mark the workspace stopped. Does not touch the filesystem."
  def stop(%Workspace{} = workspace) do
    update(workspace, %{status: "stopped"})
  end

  @doc """
  Tear down: removes the on-disk root via the backend, then deletes the row.
  Returns `:ok` on success.
  """
  def destroy(%Workspace{} = workspace) do
    backend = Backend.for_workspace(workspace)

    with :ok <- backend.destroy(workspace),
         {:ok, _} <- delete(workspace) do
      :ok
    else
      {:error, reason} ->
        _ = update(workspace, %{status: "error", metadata: %{"destroy_error" => inspect(reason)}})
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Internals
  # ---------------------------------------------------------------------------

  defp materialize(%Workspace{} = workspace) do
    backend = Backend.for_workspace(workspace)

    with :ok <- backend.ensure_root(workspace),
         # Re-load: backend.ensure_root may have persisted side effects
         # like a docker container_id that aren't on our in-memory copy.
         %Workspace{} = refreshed <- Repo.get(Workspace, workspace.id),
         :ok <- maybe_write_hydra_md(backend, refreshed),
         {:ok, ready} <- update(refreshed, %{status: "ready"}) do
      {:ok, ready}
    else
      nil ->
        # Workspace row vanished between ensure_root and re-load — racy
        # delete or an aggressive cleanup. Surface as an explicit error
        # rather than crashing in the `with` else.
        {:error, :workspace_disappeared}

      {:error, reason} ->
        _ = update(workspace, %{status: "error"})
        {:error, reason}
    end
  end

  defp maybe_write_hydra_md(backend, %Workspace{fs_path: fs_path} = workspace) do
    # Probe via plain File.exists? so we don't emit a noisy audit row when the
    # file is legitimately absent on first provisioning.
    if File.exists?(Path.join(fs_path, "HYDRA.md")) do
      :ok
    else
      backend.write_file(workspace, "HYDRA.md", default_hydra_md(workspace))
    end
  end

  defp default_hydra_md(%Workspace{project_id: project_id, fs_path: fs_path}) do
    project = Repo.get(Project, project_id)

    description =
      case project && project.description do
        nil -> "(Describe the project in one or two sentences.)"
        "" -> "(Describe the project in one or two sentences.)"
        text -> text
      end

    stack_section = render_stack_section(detect_stack(fs_path))
    files_section = render_files_section(list_top_level_files(fs_path))

    """
    # Project Instructions

    These instructions are loaded by Hydra coding agents when they work in
    this project's workspace. Edit freely — this file is yours.

    ## What this project is

    #{description}

    ## Technical stack

    #{stack_section}

    ## Conventions

    - (Coding conventions, naming patterns, formatting rules.)

    ## Important files

    #{files_section}

    <!-- project_id: #{project_id} -->
    """
  end

  # Detect the technology stack from well-known manifest files in the
  # workspace root. Returns a list of short labels like ["elixir", "node"].
  defp detect_stack(fs_path) when is_binary(fs_path) do
    checks = [
      {"mix.exs", "elixir"},
      {"package.json", "node"},
      {"Cargo.toml", "rust"},
      {"pyproject.toml", "python"},
      {"requirements.txt", "python"},
      {"go.mod", "go"},
      {"Gemfile", "ruby"},
      {"pom.xml", "java (maven)"},
      {"build.gradle", "java (gradle)"},
      {"build.gradle.kts", "kotlin (gradle)"}
    ]

    checks
    |> Enum.filter(fn {file, _label} -> File.exists?(Path.join(fs_path, file)) end)
    |> Enum.map(fn {_file, label} -> label end)
    |> Enum.uniq()
  end

  defp detect_stack(_), do: []

  defp render_stack_section([]),
    do: "- (No manifest files detected. Add a note about the language/framework.)"

  defp render_stack_section(stack) do
    Enum.map_join(stack, "\n", fn label -> "- #{label}" end)
  end

  # Top-level files/dirs worth surfacing. Ignore dotfiles and common build
  # artefacts; keep the list short so HYDRA.md stays scannable.
  @important_tops ~w(README.md LICENSE mix.exs package.json Cargo.toml pyproject.toml
                     requirements.txt go.mod Gemfile lib src test tests spec)
  defp list_top_level_files(fs_path) when is_binary(fs_path) do
    case File.ls(fs_path) do
      {:ok, entries} ->
        entries
        |> Enum.filter(&(&1 in @important_tops))
        |> Enum.sort()

      _ ->
        []
    end
  end

  defp list_top_level_files(_), do: []

  defp render_files_section([]), do: "- (Key files an agent should know about.)"

  defp render_files_section(files) do
    Enum.map_join(files, "\n", fn name -> "- `#{name}`" end)
  end
end
