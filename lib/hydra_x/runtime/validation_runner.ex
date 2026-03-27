defmodule HydraX.Runtime.ValidationRunner do
  @moduledoc false

  alias HydraX.Runtime.WorkItem

  @default_command_timeout_ms 60_000
  @max_output_chars 2_000
  @validation_allowlist ~w(mix elixir)

  def run_validation_pipeline(%WorkItem{} = work_item, opts \\ []) do
    runner = Keyword.get(opts, :runner, &default_runner/3)
    workspace_root = extract_workspace_root(work_item)
    test_commands = extract_test_commands(work_item)
    changed_files = extract_changed_files(work_item)

    {results, skipped} =
      Enum.reduce(test_commands, {[], []}, fn command, {results_acc, skipped_acc} ->
        case validate_command(command) do
          :ok ->
            result = run_validation_command(command, workspace_root, runner, opts)
            {results_acc ++ [result], skipped_acc}

          {:skip, reason} ->
            {results_acc, skipped_acc ++ [%{"command" => command, "reason" => reason}]}
        end
      end)

    record = build_validation_record(results, skipped, changed_files)

    if record["overall_status"] == "passed" do
      {:ok, record}
    else
      {:error, record}
    end
  end

  defp run_validation_command(command, workspace_root, runner, opts) do
    timeout = Keyword.get(opts, :timeout, @default_command_timeout_ms)
    started_at = System.monotonic_time(:millisecond)

    result = runner.(command, workspace_root, timeout)

    duration_ms = System.monotonic_time(:millisecond) - started_at

    case result do
      {:ok, output, exit_code} ->
        %{
          "command" => command,
          "status" => if(exit_code == 0, do: "passed", else: "failed"),
          "exit_code" => exit_code,
          "output_excerpt" => String.slice(output || "", 0, @max_output_chars),
          "duration_ms" => duration_ms,
          "executed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

      {:error, :timeout} ->
        %{
          "command" => command,
          "status" => "timeout",
          "exit_code" => nil,
          "output_excerpt" => "",
          "duration_ms" => duration_ms,
          "executed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

      {:error, reason} ->
        %{
          "command" => command,
          "status" => "failed",
          "exit_code" => nil,
          "output_excerpt" => inspect(reason),
          "duration_ms" => duration_ms,
          "executed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }
    end
  end

  defp build_validation_record(results, skipped, changed_files) do
    passed = Enum.count(results, &(&1["status"] == "passed"))
    total = length(results)

    overall_status =
      cond do
        total == 0 -> "skipped"
        passed == total -> "passed"
        passed > 0 -> "partial"
        true -> "failed"
      end

    summary =
      cond do
        total == 0 and skipped != [] ->
          "All #{length(skipped)} checks skipped"

        total == 0 ->
          "No validation commands configured"

        true ->
          skipped_note = if skipped != [], do: "; #{length(skipped)} skipped", else: ""

          scope_note =
            if changed_files != [], do: "; #{length(changed_files)} files in scope", else: ""

          "#{passed}/#{total} checks passed#{skipped_note}#{scope_note}"
      end

    %{
      "overall_status" => overall_status,
      "commands_run" => results,
      "commands_skipped" => skipped,
      "changed_scope_validated" => changed_files != [] and overall_status == "passed",
      "validated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "summary" => summary
    }
  end

  defp validate_command(command) when is_binary(command) do
    case command |> String.split() |> List.first() do
      cmd when cmd in @validation_allowlist -> :ok
      nil -> {:skip, "empty_command"}
      cmd -> {:skip, "command_not_in_validation_allowlist: #{cmd}"}
    end
  end

  defp validate_command(_command), do: {:skip, "invalid_command_format"}

  defp extract_workspace_root(%WorkItem{} = work_item) do
    get_in(work_item.metadata || %{}, ["engineering_contract", "repo_context", "workspace_root"])
  end

  defp extract_test_commands(%WorkItem{} = work_item) do
    get_in(work_item.metadata || %{}, ["engineering_contract", "required_checks"]) ||
      extract_test_commands_from_artifacts(work_item)
  end

  defp extract_test_commands_from_artifacts(%WorkItem{} = work_item) do
    get_in(work_item.result_refs || %{}, ["validation_commands"]) || []
  end

  defp extract_changed_files(%WorkItem{} = work_item) do
    get_in(work_item.metadata || %{}, ["engineering_contract", "target_files"]) || []
  end

  defp default_runner(command, workspace_root, timeout) do
    args = ["-c", command]
    dir = workspace_root || "."

    task =
      Task.async(fn ->
        try do
          {output, exit_code} =
            System.cmd("sh", args,
              cd: dir,
              stderr_to_stdout: true,
              env: [{"MIX_ENV", "test"}]
            )

          {:ok, output, exit_code}
        rescue
          e -> {:error, Exception.message(e)}
        end
      end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, result} -> result
      nil -> {:error, :timeout}
    end
  end
end
