defmodule HydraX.Agent.ChannelSteeringTest do
  use ExUnit.Case, async: true

  alias HydraX.Agent.Channel

  describe "drain_steering_into_messages/2" do
    test "is a no-op when the queue is empty" do
      data = %{steering_queue: []}
      messages = [%{role: "user", content: "hi"}]
      assert {^messages, ^data} = Channel.drain_steering_into_messages(messages, data)
    end

    test "is a no-op when the queue field is missing" do
      data = %{}
      messages = [%{role: "user", content: "hi"}]
      assert {^messages, _} = Channel.drain_steering_into_messages(messages, data)
    end

    test "appends each queued message as a [STEERING]-prefixed user turn" do
      data = %{steering_queue: ["use postgres", "skip the cache"]}
      messages = [%{role: "user", content: "ship it"}]
      {new_messages, _new_data} = Channel.drain_steering_into_messages(messages, data)

      assert length(new_messages) == 3
      assert Enum.at(new_messages, 0) == %{role: "user", content: "ship it"}
      assert Enum.at(new_messages, 1) == %{role: "user", content: "[STEERING] use postgres"}
      assert Enum.at(new_messages, 2) == %{role: "user", content: "[STEERING] skip the cache"}
    end

    test "clears the queue in the returned data" do
      data = %{steering_queue: ["one", "two"], other_field: :preserved}
      {_messages, new_data} = Channel.drain_steering_into_messages([], data)
      assert new_data.steering_queue == []
      assert new_data.other_field == :preserved
    end

    test "preserves messages list ordering — steering goes after existing messages" do
      data = %{steering_queue: ["c"]}
      messages = [%{role: "user", content: "a"}, %{role: "assistant", content: "b"}]
      {new_messages, _} = Channel.drain_steering_into_messages(messages, data)
      assert Enum.map(new_messages, & &1.content) == ["a", "b", "[STEERING] c"]
    end
  end
end
