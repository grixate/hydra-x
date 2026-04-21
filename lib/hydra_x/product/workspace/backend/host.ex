defmodule HydraX.Product.Workspace.Backend.Host do
  @moduledoc """
  Host-mode workspace backend: reads/writes files directly under the
  workspace's `fs_path`, and runs commands with `System.cmd/3` rooted at
  the workspace directory.

  Safety guarantees:

    * Every `relative_path` is canonicalized via `safe_join/2` and rejected
      if it escapes the workspace root via `..`.
    * `safe_join/2` also resolves any symbolic links present in the parent
      chain of the candidate path and re-verifies the resolved target is
      still inside the workspace root, so a symlink pointing outside cannot
      be used to read or write files outside the sandbox.
    * `exec/4` only accepts commands whose program name appears in
      `default_allowlist/0` (extensions per agent come later). No shell
      interpolation — arguments are passed as a list to `System.cmd/3`.
    * `exec/4` enforces a timeout (default 60s) by running the command in
      a `Task` and shutting it down on overrun.
  """

  @behaviour HydraX.Product.Workspace.Backend

  alias HydraX.Product.Workspace
  alias HydraX.Product.WorkspaceEvents

  @default_timeout_ms 60_000
  @max_timeout_ms 600_000
  @max_symlink_follows 40

  @default_allowlist ~w(
    git ls cat mkdir rm node npm pnpm yarn mix elixir echo pwd grep find
    rg head tail wc which python python3
  )

  @doc "Default command allowlist for the host backend."
  def default_allowlist, do: @default_allowlist

  @impl true
  def ensure_root(%Workspace{fs_path: fs_path} = ws) do
    result =
      case File.mkdir_p(fs_path) do
        :ok -> :ok
        {:error, reason} -> {:error, {:mkdir_failed, reason}}
      end

    audit(ws, :ensure_root, result, %{path: fs_path})
    result
  end

  @impl true
  def destroy(%Workspace{fs_path: fs_path} = ws) do
    result =
      case File.rm_rf(fs_path) do
        {:ok, _} -> :ok
        {:error, reason, file} -> {:error, {:rm_failed, reason, file}}
      end

    audit(ws, :destroy, result, %{path: fs_path})
    result
  end

  @impl true
  def read_file(%Workspace{} = ws, relative_path) do
    result =
      with {:ok, abs_path} <- safe_join(ws, relative_path),
           {:ok, content} <- File.read(abs_path) do
        {:ok, content}
      else
        {:error, reason} -> {:error, reason}
      end

    audit(ws, :read, result, %{path: relative_path})
    result
  end

  @impl true
  def write_file(%Workspace{} = ws, relative_path, content) when is_binary(content) do
    result =
      with {:ok, abs_path} <- safe_join(ws, relative_path),
           :ok <- File.mkdir_p(Path.dirname(abs_path)),
           :ok <- File.write(abs_path, content) do
        :ok
      else
        {:error, reason} -> {:error, reason}
      end

    audit(ws, :write, result, %{path: relative_path, bytes: byte_size(content)})
    result
  end

  @impl true
  def list_dir(%Workspace{} = ws, relative_path) do
    result =
      with {:ok, abs_path} <- safe_join(ws, relative_path),
           {:ok, names} <- File.ls(abs_path) do
        entries =
          names
          |> Enum.sort()
          |> Enum.map(fn name ->
            full = Path.join(abs_path, name)

            case File.stat(full) do
              {:ok, %File.Stat{type: type, size: size}} ->
                %{name: name, type: normalize_type(type), size: size}

              {:error, _} ->
                %{name: name, type: :other, size: 0}
            end
          end)

        {:ok, entries}
      else
        {:error, reason} -> {:error, reason}
      end

    audit(ws, :list, result, %{path: relative_path})
    result
  end

  @impl true
  def exec(%Workspace{} = ws, [program | args], opts) when is_binary(program) do
    cond do
      not allowed?(program) ->
        result = {:error, {:command_not_allowed, program}}
        audit(ws, :exec, result, %{command: %{"program" => program, "args" => args}})
        result

      not Enum.all?(args, &is_binary/1) ->
        result = {:error, :invalid_arguments}
        audit(ws, :exec, result, %{command: %{"program" => program}})
        result

      true ->
        result = run_with_timeout(ws, program, args, opts)

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

  # --- Path safety ---

  @doc """
  Joins `relative_path` onto the workspace root and verifies the resolved
  absolute path stays inside it. Returns `{:error, :path_escapes_workspace}`
  if any part of the path (including resolved symlinks) escapes the root.
  """
  def safe_join(%Workspace{fs_path: fs_path}, relative_path)
      when is_binary(relative_path) do
    lexical_root = Path.expand(fs_path)
    lexical_candidate = Path.expand(relative_path, lexical_root)

    # First do a cheap lexical check — catches .. traversal.
    if lexical_candidate == lexical_root or
         String.starts_with?(lexical_candidate, lexical_root <> "/") do
      # Now resolve symlinks on BOTH root and candidate so that a root
      # which sits under a symlinked ancestor (e.g. /var → /private/var
      # on macOS) matches a candidate resolved through the same ancestor.
      with {:ok, real_root} <- realpath(lexical_root),
           {:ok, real_candidate} <- realpath(lexical_candidate) do
        if real_candidate == real_root or String.starts_with?(real_candidate, real_root <> "/") do
          {:ok, real_candidate}
        else
          {:error, :path_escapes_workspace}
        end
      else
        {:error, _} -> {:error, :path_escapes_workspace}
      end
    else
      {:error, :path_escapes_workspace}
    end
  end

  def safe_join(_ws, _other), do: {:error, :invalid_path}

  # Walks an absolute path and resolves symbolic links in-place, component
  # by component. Missing trailing segments (write case) are kept literal.
  # Returns `{:ok, resolved_absolute_path}` or `{:error, reason}`.
  # `follows_remaining` caps total symlink follows to prevent cycles.
  defp realpath(abs_path, follows_remaining \\ @max_symlink_follows)

  defp realpath(_abs_path, 0), do: {:error, :too_many_symlinks}

  defp realpath(abs_path, follows_remaining) when is_binary(abs_path) do
    abs_path
    |> Path.split()
    |> Enum.reduce_while({:ok, "/", follows_remaining}, fn part, {:ok, acc, follows} ->
      joined = if acc == "/" and part == "/", do: "/", else: Path.join(acc, part)

      case File.lstat(joined) do
        {:ok, %File.Stat{type: :symlink}} ->
          if follows <= 0 do
            {:halt, {:error, :too_many_symlinks}}
          else
            case File.read_link(joined) do
              {:ok, target} ->
                resolved =
                  if String.starts_with?(target, "/") do
                    target
                  else
                    Path.expand(target, Path.dirname(joined))
                  end

                # Recursively resolve in case the target itself contains
                # symlinked ancestors. Decrement the follow budget.
                case realpath(resolved, follows - 1) do
                  {:ok, deeper} -> {:cont, {:ok, deeper, follows - 1}}
                  {:error, reason} -> {:halt, {:error, reason}}
                end

              {:error, reason} ->
                {:halt, {:error, reason}}
            end
          end

        {:ok, %File.Stat{}} ->
          {:cont, {:ok, joined, follows}}

        {:error, :enoent} ->
          {:cont, {:ok, joined, follows}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, path, _follows} -> {:ok, path}
      {:error, _} = err -> err
    end
  end

  # --- Internals ---

  @doc """
  Returns true if the program name is in the allowlist and contains no
  path separators. Public so the Docker backend can reuse the same gate.
  """
  def allowed?(program) when is_binary(program) do
    base = Path.basename(program)
    base in @default_allowlist and not String.contains?(program, "/")
  end

  def allowed?(_), do: false

  defp normalize_type(:regular), do: :file
  defp normalize_type(:directory), do: :dir
  defp normalize_type(_), do: :other

  defp run_with_timeout(%Workspace{fs_path: fs_path}, program, args, opts) do
    timeout =
      opts
      |> Keyword.get(:timeout_ms, @default_timeout_ms)
      |> min(@max_timeout_ms)
      |> max(1)

    env = Keyword.get(opts, :env, [])

    task =
      Task.async(fn ->
        try do
          # stderr_to_stdout combines both streams into the returned binary.
          # We don't get separate stderr but we also never lose error output —
          # which matters for code_test failures and tooling diagnostics.
          {output, exit_code} =
            System.cmd(program, args,
              cd: fs_path,
              env: env,
              stderr_to_stdout: true,
              parallelism: true
            )

          {:ok, %{stdout: output, stderr: "", exit_code: exit_code}}
        rescue
          e in ErlangError -> {:error, {:exec_failed, Exception.message(e)}}
          e -> {:error, {:exec_failed, Exception.message(e)}}
        end
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      nil -> {:error, :timeout}
      {:exit, reason} -> {:error, {:task_exit, reason}}
    end
  end

  # --- Audit ---

  defp audit(%Workspace{id: nil}, _kind, _result, _extra), do: :ok

  defp audit(%Workspace{} = ws, kind, result, extra) do
    {outcome, error} =
      case result do
        :ok -> {"ok", nil}
        {:ok, _} -> {"ok", nil}
        {:error, reason} -> {"error", inspect(reason)}
      end

    attrs =
      %{
        kind: Atom.to_string(kind),
        outcome: outcome,
        error: error,
        path: extra[:path],
        command: extra[:command],
        exit_code: extra[:exit_code],
        metadata: extra[:metadata] || %{}
      }

    _ = WorkspaceEvents.log(ws, attrs)
    :ok
  end
end
