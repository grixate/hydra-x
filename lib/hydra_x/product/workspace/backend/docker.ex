defmodule HydraX.Product.Workspace.Backend.Docker do
  @moduledoc """
  Docker-mode workspace backend. Each project gets a long-running container
  with the workspace's `fs_path` bind-mounted at `/workspace`. Commands run
  inside the container via `docker exec`; file operations bypass the
  container and operate directly on the bind-mounted host path (with the
  same `safe_join/2` symlink-resolving guards as the host backend).

  ## Container model

    * One container per project, named `hydra_x_ws_<project_id>`.
    * Started lazily on `ensure_root/1`.
    * Long-running via `tail -f /dev/null` so we can `docker exec` into
      it for many subsequent commands without paying startup cost each
      time.
    * Torn down on `destroy/1`.
    * Default image: `alpine:latest` (override via
      `config :hydra_x, :workspace_docker_image`).
    * `--network none` by default for maximum isolation; the workspace is
      meant for code execution, not network calls.

  ## Safety

    * `safe_join/2` (delegated to `Backend.Host`) prevents path traversal
      and rejects symlinks whose targets escape the workspace root.
    * `exec/4` enforces the same allowlist as the host backend.
    * The mounted volume is the only writable path in the container by
      default; the rest of the rootfs is left writable since alpine is
      small enough that we don't bother with `--read-only`. Future work:
      tighten with `--read-only --tmpfs /tmp`.

  ## Testability

    * The actual docker CLI invocation goes through the
      `:docker_runner` application env, defaulting to `&System.cmd/3`.
      Tests inject a fake runner that returns canned `{output, exit_code}`
      tuples without needing a docker daemon installed.
  """

  @behaviour HydraX.Product.Workspace.Backend

  alias HydraX.Product.Workspace
  alias HydraX.Product.Workspace.Backend.Host
  alias HydraX.Product.WorkspaceEvents
  alias HydraX.Product.Workspaces

  @default_image "alpine:latest"
  @default_timeout_ms 60_000
  @max_timeout_ms 600_000

  @doc "Returns the docker image used for new workspace containers."
  def default_image do
    Application.get_env(:hydra_x, :workspace_docker_image, @default_image)
  end

  @doc """
  Returns the runner function used to invoke the `docker` CLI. Tests
  override this via `Application.put_env(:hydra_x, :docker_runner, fn ... end)`.
  Default uses `System.cmd/3`.

  The runner is called as `runner.(["docker", arg1, arg2, ...], opts)` and
  must return `{output_binary, exit_code_integer}`.
  """
  def runner do
    Application.get_env(:hydra_x, :docker_runner, &__MODULE__.default_runner/2)
  end

  @doc false
  def default_runner(args, opts) when is_list(args) do
    [program | rest] = args
    System.cmd(program, rest, Keyword.put(opts, :stderr_to_stdout, true))
  end

  @impl true
  def ensure_root(%Workspace{} = ws) do
    with :ok <- Host.ensure_root(ws),
         {:ok, ws} <- ensure_container(ws) do
      audit(ws, :ensure_root, :ok, %{path: ws.fs_path})
      :ok
    else
      {:error, reason} = err ->
        audit(ws, :ensure_root, err, %{path: ws.fs_path})
        {:error, reason}
    end
  end

  @impl true
  def destroy(%Workspace{} = ws) do
    _ = stop_container(ws)
    result = Host.destroy(ws)
    audit(ws, :destroy, result, %{path: ws.fs_path})
    result
  end

  @impl true
  def read_file(%Workspace{} = ws, relative_path) do
    Host.read_file(ws, relative_path)
  end

  @impl true
  def write_file(%Workspace{} = ws, relative_path, content) do
    Host.write_file(ws, relative_path, content)
  end

  @impl true
  def list_dir(%Workspace{} = ws, relative_path) do
    Host.list_dir(ws, relative_path)
  end

  @impl true
  def exec(%Workspace{} = ws, [program | args] = command, opts) when is_binary(program) do
    cond do
      not Host.allowed?(program) ->
        result = {:error, {:command_not_allowed, program}}

        audit(ws, :exec, result, %{
          command: %{"program" => program, "args" => args}
        })

        result

      not Enum.all?(args, &is_binary/1) ->
        result = {:error, :invalid_arguments}
        audit(ws, :exec, result, %{command: %{"program" => program}})
        result

      ws.container_id in [nil, ""] ->
        result = {:error, :container_not_started}
        audit(ws, :exec, result, %{command: %{"program" => program, "args" => args}})
        result

      true ->
        result = run_in_container(ws, command, opts)

        exit_code =
          case result do
            {:ok, %{exit_code: code}} -> code
            _ -> nil
          end

        audit(ws, :exec, result, %{
          command: %{"program" => program, "args" => args},
          exit_code: exit_code
        })

        result
    end
  end

  def exec(%Workspace{} = ws, _command, _opts) do
    result = {:error, :invalid_command}
    audit(ws, :exec, result, %{})
    result
  end

  # ---------------------------------------------------------------------------
  # Container lifecycle
  # ---------------------------------------------------------------------------

  @doc false
  def container_name(%Workspace{project_id: project_id}),
    do: "hydra_x_ws_#{project_id}"

  defp ensure_container(%Workspace{container_id: id} = ws) when is_binary(id) and id != "" do
    case container_running?(id) do
      true ->
        {:ok, ws}

      false ->
        # Stale id (container was killed externally) — start fresh.
        start_container(%Workspace{ws | container_id: nil})
    end
  end

  defp ensure_container(%Workspace{} = ws), do: start_container(ws)

  defp start_container(%Workspace{} = ws) do
    name = container_name(ws)
    image = default_image()

    args = [
      "docker",
      "run",
      "-d",
      "--rm",
      "--name",
      name,
      "--network",
      "none",
      "--workdir",
      "/workspace",
      "-v",
      "#{ws.fs_path}:/workspace",
      image,
      "tail",
      "-f",
      "/dev/null"
    ]

    case runner().(args, []) do
      {output, 0} ->
        container_id = String.trim(output)

        case Workspaces.update(ws, %{container_id: container_id, sandbox_mode: "docker"}) do
          {:ok, updated} -> {:ok, updated}
          {:error, _} -> {:error, :failed_to_persist_container_id}
        end

      {output, code} ->
        {:error, {:docker_run_failed, code, String.slice(output, 0, 500)}}
    end
  end

  defp stop_container(%Workspace{container_id: id}) when is_binary(id) and id != "" do
    case runner().(["docker", "rm", "-f", id], []) do
      {_, 0} -> :ok
      {output, code} -> {:error, {:docker_rm_failed, code, String.slice(output, 0, 200)}}
    end
  end

  defp stop_container(_ws), do: :ok

  defp container_running?(container_id) do
    case runner().(["docker", "inspect", "-f", "{{.State.Running}}", container_id], []) do
      {output, 0} -> String.trim(output) == "true"
      _ -> false
    end
  end

  # ---------------------------------------------------------------------------
  # Exec inside container
  # ---------------------------------------------------------------------------

  defp run_in_container(%Workspace{container_id: container_id}, [program | args], opts) do
    timeout =
      opts
      |> Keyword.get(:timeout_ms, @default_timeout_ms)
      |> min(@max_timeout_ms)
      |> max(1)

    full_args = ["docker", "exec", container_id, program] ++ args

    task =
      Task.async(fn ->
        try do
          {output, exit_code} = runner().(full_args, [])
          {:ok, %{stdout: output, stderr: "", exit_code: exit_code}}
        rescue
          e -> {:error, {:exec_failed, Exception.message(e)}}
        end
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      nil -> {:error, :timeout}
      {:exit, reason} -> {:error, {:task_exit, reason}}
    end
  end

  # ---------------------------------------------------------------------------
  # Audit (mirrors Host backend)
  # ---------------------------------------------------------------------------

  defp audit(%Workspace{id: nil}, _kind, _result, _extra), do: :ok

  defp audit(%Workspace{} = ws, kind, result, extra) do
    {outcome, error} =
      case result do
        :ok -> {"ok", nil}
        {:ok, _} -> {"ok", nil}
        {:error, reason} -> {"error", inspect(reason)}
      end

    attrs = %{
      kind: Atom.to_string(kind),
      outcome: outcome,
      error: error,
      path: extra[:path],
      command: extra[:command],
      exit_code: extra[:exit_code],
      metadata: Map.put(extra[:metadata] || %{}, "backend", "docker")
    }

    _ = WorkspaceEvents.log(ws, attrs)
    :ok
  end
end
