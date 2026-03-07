defmodule HydraX.BudgetTaskTest do
  use HydraX.DataCase

  import ExUnit.CaptureIO

  alias HydraX.Budget
  alias HydraX.Runtime

  test "budget task can inspect and update a policy" do
    Mix.Task.reenable("hydra_x.budget")
    agent = create_agent()
    Budget.ensure_policy!(agent.id)

    output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Budget.run([
          "--agent",
          agent.slug,
          "--daily-limit",
          "12345",
          "--conversation-limit",
          "456",
          "--hard-limit-action",
          "warn",
          "--enabled",
          "false"
        ])
      end)

    assert output =~ "agent=#{agent.slug}"
    assert output =~ "daily_limit=12345"
    assert output =~ "conversation_limit=456"
    assert output =~ "hard_limit_action=warn"
    assert output =~ "enabled=false"

    policy = Budget.get_policy(agent.id)
    assert policy.daily_limit == 12_345
    assert policy.conversation_limit == 456
    assert policy.hard_limit_action == "warn"
    refute policy.enabled
  end

  defp create_agent do
    unique = System.unique_integer([:positive])

    {:ok, agent} =
      Runtime.save_agent(%{
        name: "Budget Task Agent #{unique}",
        slug: "budget-task-agent-#{unique}",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-budget-task-#{unique}"),
        description: "budget task test",
        is_default: false
      })

    agent
  end
end
