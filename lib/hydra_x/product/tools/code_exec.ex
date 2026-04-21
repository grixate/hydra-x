defmodule HydraX.Product.Tools.CodeExec do
  @behaviour HydraX.Tool

  alias HydraX.Product.Tools.CodeWorkspaceHelpers

  @max_output 16_000
  @default_timeout_ms 60_000

  @impl true
  def name, do: "code_exec"

  @impl true
  def description,
    do: "Run an allowlisted command in the project workspace and return its output."

  @impl true
  def safety_classification, do: "workspace_exec"

  @impl true
  def tool_schema do
    %{
      name: "code_exec",
      description:
        "Run an allowlisted shell command in the project workspace. Pass the program and arguments as a list. No shell interpolation. Default timeout 60s.",
      input_schema: %{
        type: "object",
        properties: %{
          command: %{
            type: "array",
            items: %{type: "string"},
            description: "Program followed by its arguments, e.g. [\"git\", \"status\"]."
          },
          timeout_ms: %{
            type: "integer",
            description: "Timeout in milliseconds (default 60000, max 600000)."
          }
        },
        required: ["command"]
      }
    }
  end

  @impl true
  def execute(params, context) do
    with {:ok, command} <- fetch_command(params),
         {:ok, timeout} <- fetch_timeout(params) do
      CodeWorkspaceHelpers.with_workspace(context, fn backend, workspace ->
        case backend.exec(workspace, command, timeout_ms: timeout) do
          {:ok, result} ->
            {:ok,
             %{
               command: command,
               exit_code: result.exit_code,
               stdout: truncate(result.stdout),
               stderr: truncate(result.stderr),
               truncated: byte_size(result.stdout) > @max_output
             }}

          {:error, reason} ->
            {:error, reason}
        end
      end)
    end
  end

  defp fetch_command(params) do
    case params[:command] || params["command"] do
      [program | _] = cmd when is_binary(program) -> {:ok, cmd}
      _ -> {:error, :invalid_command}
    end
  end

  defp fetch_timeout(params) do
    case params[:timeout_ms] || params["timeout_ms"] do
      nil -> {:ok, @default_timeout_ms}
      n when is_integer(n) and n > 0 -> {:ok, n}
      s when is_binary(s) ->
        case Integer.parse(s) do
          {n, ""} when n > 0 -> {:ok, n}
          _ -> {:error, :invalid_timeout}
        end
      _ -> {:error, :invalid_timeout}
    end
  end

  defp truncate(str) when is_binary(str), do: String.slice(str, 0, @max_output)
  defp truncate(_), do: ""

  @impl true
  def result_summary(%{command: [prog | _], exit_code: code}),
    do: "exec #{prog} → exit #{code}"

  def result_summary(%{error: error}) when is_binary(error), do: error
  def result_summary(payload), do: inspect(payload, limit: 8, printable_limit: 120)
end
