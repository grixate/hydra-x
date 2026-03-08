defmodule HydraX.Tools.ShellCommand do
  @behaviour HydraX.Tool

  alias HydraX.Safety.ShellGuard

  @max_output 4_000
  @timeout_ms 5_000

  @impl true
  def name, do: "shell_command"

  @impl true
  def description, do: "Run a small allowlisted command inside the agent workspace"

  @impl true
  def tool_schema do
    %{
      name: "shell_command",
      description:
        "Run an allowlisted shell command in the agent workspace. Only specific commands are permitted (e.g. ls, cat, head, rg, git status). Use this when the user asks to run a command, list files, search code, or check git status.",
      input_schema: %{
        type: "object",
        properties: %{
          command: %{
            type: "string",
            description:
              "The shell command to run (e.g. \"ls\", \"cat README.md\", \"rg TODO\", \"git status\")"
          }
        },
        required: ["command"]
      }
    }
  end

  @impl true
  def execute(params, context) do
    runner = context[:runner] || (&System.cmd/3)
    allowlist = Map.get(context, :shell_allowlist, HydraX.Config.shell_allowlist())

    with workspace_root when is_binary(workspace_root) <- context[:workspace_root],
         command_text when is_binary(command_text) <- params[:command] || params["command"],
         {:ok, %{command: command, args: args}} <-
           ShellGuard.validate(command_text, workspace_root, allowlist: allowlist),
         {:ok, {output, exit_status}} <- run_command(runner, command, args, workspace_root) do
      {:ok,
       %{
         command: Enum.join([command | args], " "),
         output: String.slice(output, 0, @max_output),
         truncated: String.length(output) > @max_output,
         exit_status: exit_status
       }}
    else
      nil -> {:error, :missing_workspace_root}
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_command(runner, command, args, workspace_root) do
    task =
      Task.async(fn ->
        runner.(command, args, cd: workspace_root, stderr_to_stdout: true)
      end)

    case Task.yield(task, @timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> {:ok, result}
      nil -> {:error, :timeout}
    end
  end
end
