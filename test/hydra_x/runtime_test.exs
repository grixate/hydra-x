defmodule HydraX.RuntimeTest do
  use HydraX.DataCase

  alias HydraX.Agent.Channel
  alias HydraX.Memory
  alias HydraX.Runtime

  test "chat flow persists turns and memory recall works" do
    agent = Runtime.ensure_default_agent!()
    {:ok, _pid} = HydraX.Agent.ensure_started(agent)

    {:ok, write_conversation} =
      Runtime.start_conversation(agent, %{channel: "cli", title: "memory-write"})

    write_response =
      Channel.submit(
        agent,
        write_conversation,
        "Remember that the operator prefers terse answers and decisive summaries.",
        %{source: "test"}
      )

    assert write_response =~ "Saved memory"
    assert [%{type: "Preference"} | _] = Memory.search(agent.id, "terse answers", 5)

    {:ok, recall_conversation} =
      Runtime.start_conversation(agent, %{channel: "cli", title: "memory-read"})

    recall_response =
      Channel.submit(
        agent,
        recall_conversation,
        "What do you remember about terse answers?",
        %{source: "test"}
      )

    assert recall_response =~ "Relevant memory"
    assert recall_response =~ "terse answers"
    assert length(Runtime.list_turns(recall_conversation.id)) == 2
  end
end
