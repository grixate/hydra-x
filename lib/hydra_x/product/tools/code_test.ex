defmodule HydraX.Product.Tools.CodeTest do
  @behaviour HydraX.Tool

  alias HydraX.Product.Tools.CodeWorkspaceHelpers

  @max_output 16_000
  @default_timeout_ms 300_000

  @impl true
  def name, do: "code_test"

  @impl true
  def description,
    do: "Run the project's test suite via an allowlisted runner and return the result."

  @impl true
  def safety_classification, do: "workspace_exec"

  @impl true
  def tool_schema do
    %{
      name: "code_test",
      description:
        "Run the project's test suite. Provide the test command as an array. Default timeout is 5 minutes.",
      input_schema: %{
        type: "object",
        properties: %{
          command: %{
            type: "array",
            items: %{type: "string"},
            description: "Test runner command, e.g. [\"npm\", \"test\"] or [\"mix\", \"test\"]."
          },
          timeout_ms: %{type: "integer", description: "Timeout in milliseconds (default 300000)."}
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
               passed: result.exit_code == 0,
               stdout: String.slice(result.stdout, 0, @max_output),
               stderr: String.slice(result.stderr, 0, @max_output)
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
      nil ->
        {:ok, @default_timeout_ms}

      n when is_integer(n) and n > 0 ->
        {:ok, n}

      s when is_binary(s) ->
        case Integer.parse(s) do
          {n, ""} when n > 0 -> {:ok, n}
          _ -> {:error, :invalid_timeout}
        end

      _ ->
        {:error, :invalid_timeout}
    end
  end

  @impl true
  def result_summary(%{command: [prog | _], passed: true}), do: "tests passed (#{prog})"

  def result_summary(%{command: [prog | _], passed: false, exit_code: code}),
    do: "tests failed (#{prog}, exit #{code})"

  def result_summary(%{error: error}) when is_binary(error), do: error
  def result_summary(payload), do: inspect(payload, limit: 8, printable_limit: 120)
end
