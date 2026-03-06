defmodule HydraX.Safety.ShellGuard do
  @moduledoc """
  Validates allowlisted shell commands before execution inside a workspace.
  """

  alias HydraX.Config
  alias HydraX.Safety.PathGuard

  @allowed_git_commands [
    ["status"],
    ["branch", "--show-current"],
    ["rev-parse", "--short", "HEAD"]
  ]

  def validate(command_text, workspace_root) when is_binary(command_text) do
    argv = OptionParser.split(command_text)

    with [command | args] <- argv,
         true <- command in Config.shell_allowlist() or {:error, :command_not_allowlisted},
         :ok <- validate_args(command, args, workspace_root) do
      {:ok, %{command: command, args: args}}
    else
      [] -> {:error, :empty_command}
      false -> {:error, :command_not_allowlisted}
      {:error, reason} -> {:error, reason}
    end
  end

  def validate(_command_text, _workspace_root), do: {:error, :invalid_command}

  defp validate_args("pwd", [], _workspace_root), do: :ok

  defp validate_args("ls", args, workspace_root),
    do: validate_paths(args, workspace_root, require_path: false)

  defp validate_args("cat", args, workspace_root),
    do: validate_paths(args, workspace_root, require_path: true)

  defp validate_args("head", args, workspace_root),
    do: validate_paths(args, workspace_root, require_path: true)

  defp validate_args("rg", args, workspace_root), do: validate_rg(args, workspace_root)

  defp validate_args("git", args, _workspace_root) do
    if args in @allowed_git_commands, do: :ok, else: {:error, :git_subcommand_not_allowed}
  end

  defp validate_args(_command, _args, _workspace_root), do: :ok

  defp validate_rg(args, workspace_root) do
    {paths, has_pattern?} =
      Enum.reduce(args, {[], false}, fn arg, {paths, has_pattern?} ->
        cond do
          String.starts_with?(arg, "-") ->
            {paths, has_pattern?}

          not has_pattern? ->
            {paths, true}

          true ->
            {[arg | paths], has_pattern?}
        end
      end)

    cond do
      not has_pattern? -> {:error, :missing_search_pattern}
      true -> validate_paths(Enum.reverse(paths), workspace_root, require_path: false)
    end
  end

  defp validate_paths(args, workspace_root, opts) do
    paths = Enum.reject(args, &String.starts_with?(&1, "-"))

    cond do
      opts[:require_path] && paths == [] ->
        {:error, :missing_path}

      true ->
        Enum.reduce_while(paths, :ok, fn path, :ok ->
          case PathGuard.resolve_workspace_path(workspace_root, path) do
            {:ok, _resolved} -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
    end
  end
end
