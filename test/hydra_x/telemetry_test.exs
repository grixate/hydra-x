defmodule HydraX.TelemetryTest do
  use HydraX.DataCase

  alias HydraX.Agent.Channel
  alias HydraX.Runtime

  test "provider failures emit telemetry" do
    agent = create_agent()
    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    {:ok, _provider} =
      Runtime.save_provider_config(%{
        name: "Broken Provider",
        kind: "openai_compatible",
        base_url: "http://127.0.0.1:1",
        api_key: "secret",
        model: "gpt-test",
        enabled: true
      })

    handler_id = "provider-failure-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler_id,
      [:hydra_x, :provider, :request],
      fn _event, measurements, metadata, pid ->
        send(pid, {:provider_event, measurements, metadata})
      end,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{channel: "cli", title: "provider-telemetry"})

    _response =
      Channel.submit(
        agent,
        conversation,
        "Hello through a broken provider.",
        %{source: "test"}
      )

    assert_receive {:provider_event, %{count: 1}, %{status: :error}}

    snapshot = HydraX.Telemetry.Store.snapshot()
    assert get_in(snapshot, [:provider, "Broken Provider", "error"]) >= 1

    assert Enum.any?(snapshot.recent_events, fn event ->
             event.namespace == "provider" and event.bucket == "Broken Provider" and
               event.status == "error"
           end)
  end

  defp create_agent do
    unique = System.unique_integer([:positive])

    {:ok, agent} =
      Runtime.save_agent(%{
        name: "Telemetry Agent #{unique}",
        slug: "telemetry-agent-#{unique}",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-telemetry-#{unique}"),
        description: "telemetry test agent",
        is_default: false
      })

    HydraX.Budget.ensure_policy!(agent.id)
    agent
  end
end
