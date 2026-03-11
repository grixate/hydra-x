defmodule HydraX.GatewayTest do
  use HydraX.DataCase

  alias HydraX.Gateway.Adapters.{Discord, Telegram}
  alias HydraX.Runtime

  test "telegram updates are routed into conversations and answered" do
    agent = create_agent()
    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    {:ok, _telegram} =
      Runtime.save_telegram_config(%{
        bot_token: "test-token",
        bot_username: "hydrax_bot",
        enabled: true,
        default_agent_id: agent.id
      })

    deliver = fn payload ->
      send(self(), {:telegram_reply, payload})
      :ok
    end

    assert :ok =
             HydraX.Gateway.dispatch_telegram_update(
               %{
                 "message" => %{
                   "chat" => %{"id" => 42},
                   "message_id" => 501,
                   "text" => "Remember that Telegram ingress is now routed."
                 }
               },
               %{deliver: deliver}
             )

    assert_receive {:telegram_reply, %{chat_id: "42", text: content, reply_to_message_id: 501}}
    assert content =~ "Mock response"

    [conversation] = Runtime.list_conversations(agent_id: agent.id, limit: 10)
    assert conversation.channel == "telegram"
    assert Runtime.list_turns(conversation.id) |> length() == 2

    refreshed = Runtime.get_conversation!(conversation.id)
    assert refreshed.metadata["last_delivery"]["status"] == "delivered"
    assert refreshed.metadata["last_delivery"]["external_ref"] == "42"
    assert refreshed.metadata["last_delivery"]["reply_context"]["reply_to_message_id"] == 501
    assert refreshed.metadata["last_delivery"]["formatted_payload"]["chat_id"] == "42"
    assert refreshed.metadata["last_delivery"]["formatted_payload"]["reply_to_message_id"] == 501
  end

  test "telegram updates defer delivery when conversation ownership is remote" do
    previous_adapter = Application.get_env(:hydra_x, :repo_adapter)
    Application.put_env(:hydra_x, :repo_adapter, Ecto.Adapters.Postgres)

    on_exit(fn ->
      if previous_adapter do
        Application.put_env(:hydra_x, :repo_adapter, previous_adapter)
      else
        Application.delete_env(:hydra_x, :repo_adapter)
      end
    end)

    agent = create_agent()
    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    {:ok, _telegram} =
      Runtime.save_telegram_config(%{
        bot_token: "test-token",
        bot_username: "hydrax_bot",
        enabled: true,
        default_agent_id: agent.id
      })

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{
        channel: "telegram",
        external_ref: "4242",
        title: "Telegram Remote 4242"
      })

    assert {:ok, _lease} =
             Runtime.claim_lease("conversation:#{conversation.id}",
               owner: "node:remote",
               ttl_seconds: 60
             )

    assert :ok =
             HydraX.Gateway.dispatch_telegram_update(
               %{
                 "message" => %{
                   "chat" => %{"id" => 4242},
                   "message_id" => 901,
                   "text" => "Route this to the owning node."
                 }
               },
               %{
                 deliver: fn payload ->
                   send(self(), {:telegram_reply, payload})
                   :ok
                 end
               }
             )

    refute_receive {:telegram_reply, _payload}

    refreshed = Runtime.get_conversation!(conversation.id)
    assert refreshed.metadata["last_delivery"]["status"] == "deferred"
    assert refreshed.metadata["last_delivery"]["metadata"]["ownership_deferred"]
    assert refreshed.metadata["last_delivery"]["reason"] =~ "node:remote"
    assert refreshed.metadata["last_delivery"]["reply_context"]["reply_to_message_id"] == 901

    [turn] = Runtime.list_turns(conversation.id)
    assert turn.role == "user"
    assert turn.content == "Route this to the owning node."
  end

  test "telegram adapter chunks long outbound replies and reports chunk metadata" do
    {:ok, state} =
      Telegram.connect(%{
        "bot_token" => "test-token",
        "deliver" => fn payload ->
          send(self(), {:telegram_chunk, payload})
          {:ok, %{provider_message_id: "msg-#{String.length(payload.text)}"}}
        end
      })

    long_content = String.duplicate("a", 4_500)

    preview =
      Telegram.format_message(
        %{content: long_content, external_ref: "42", metadata: %{"reply_to_message_id" => 501}},
        state
      )

    assert preview.chat_id == "42"
    assert preview.reply_to_message_id == 501
    assert preview.chunk_count == 2
    assert preview.truncated
    assert String.length(preview.text) == 4_096

    assert {:ok, metadata} =
             Telegram.deliver(
               %{
                 content: long_content,
                 external_ref: "42",
                 metadata: %{"reply_to_message_id" => 501}
               },
               state
             )

    assert metadata.channel == "telegram"
    assert metadata.chunk_count == 2
    assert length(metadata.provider_message_ids) == 2

    assert_receive {:telegram_chunk, %{chat_id: "42", reply_to_message_id: 501, text: first}}
    assert String.length(first) == 4_096
    assert_receive {:telegram_chunk, %{chat_id: "42", reply_to_message_id: nil, text: second}}
    assert String.length(second) == 404
  end

  test "telegram delivery failures are logged and persisted on the conversation" do
    agent = create_agent()
    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    {:ok, _telegram} =
      Runtime.save_telegram_config(%{
        bot_token: "test-token",
        bot_username: "hydrax_bot",
        enabled: true,
        default_agent_id: agent.id
      })

    deliver = fn _payload ->
      {:error, :timeout}
    end

    assert :ok =
             HydraX.Gateway.dispatch_telegram_update(
               %{
                 "message" => %{
                   "chat" => %{"id" => 77},
                   "text" => "Record the failed Telegram delivery state."
                 }
               },
               %{deliver: deliver}
             )

    [conversation] = Runtime.list_conversations(agent_id: agent.id, limit: 10)
    refreshed = Runtime.get_conversation!(conversation.id)
    assert refreshed.metadata["last_delivery"]["status"] == "failed"
    assert refreshed.metadata["last_delivery"]["reason"] =~ ":timeout"
    assert refreshed.metadata["last_delivery"]["retry_limit"] == 3
    assert refreshed.metadata["last_delivery"]["next_retry_in_ms"] == 5_000
    assert is_binary(refreshed.metadata["last_delivery"]["next_retry_at"])
    assert [%{"status" => "failed"}] = refreshed.metadata["last_delivery"]["attempt_history"]

    [event | _] = HydraX.Safety.recent_events(agent.id, 5)
    assert event.category == "gateway"
    assert event.message == "Telegram delivery failed"
  end

  test "failed Telegram deliveries can be retried later" do
    agent = create_agent()
    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    {:ok, _telegram} =
      Runtime.save_telegram_config(%{
        bot_token: "test-token",
        bot_username: "hydrax_bot",
        enabled: true,
        default_agent_id: agent.id
      })

    assert :ok =
             HydraX.Gateway.dispatch_telegram_update(
               %{
                 "message" => %{
                   "chat" => %{"id" => 88},
                   "message_id" => 601,
                   "text" => "Retry the Telegram delivery after failure."
                 }
               },
               %{deliver: fn _payload -> {:error, :timeout} end}
             )

    [conversation] = Runtime.list_conversations(agent_id: agent.id, limit: 10)

    previous = Application.get_env(:hydra_x, :telegram_deliver)

    Application.put_env(:hydra_x, :telegram_deliver, fn payload ->
      send(self(), {:telegram_retry, payload})
      {:ok, %{provider_message_id: 99}}
    end)

    on_exit(fn ->
      if previous do
        Application.put_env(:hydra_x, :telegram_deliver, previous)
      else
        Application.delete_env(:hydra_x, :telegram_deliver)
      end
    end)

    assert {:ok, _updated} = HydraX.Gateway.retry_conversation_delivery(conversation)
    assert_receive {:telegram_retry, %{chat_id: "88", text: content, reply_to_message_id: 601}}
    assert content =~ "Mock response:"
    assert content =~ "Retry the Telegram delivery after failure."

    refreshed = Runtime.get_conversation!(conversation.id)
    assert refreshed.metadata["last_delivery"]["status"] == "delivered"
    assert refreshed.metadata["last_delivery"]["retry_count"] == 1
    assert refreshed.metadata["last_delivery"]["metadata"]["provider_message_id"] == 99
    assert length(refreshed.metadata["last_delivery"]["attempt_history"]) >= 2
  end

  test "telegram attachment messages preserve attachment metadata" do
    agent = create_agent()
    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    {:ok, _telegram} =
      Runtime.save_telegram_config(%{
        bot_token: "test-token",
        bot_username: "hydrax_bot",
        enabled: true,
        default_agent_id: agent.id
      })

    assert :ok =
             HydraX.Gateway.dispatch_telegram_update(
               %{
                 "message" => %{
                   "chat" => %{"id" => 91},
                   "caption" => "See attached",
                   "document" => %{
                     "file_id" => "doc-1",
                     "file_unique_id" => "doc-uniq",
                     "file_name" => "spec.pdf",
                     "mime_type" => "application/pdf",
                     "file_size" => 1024
                   }
                 }
               },
               %{deliver: fn _payload -> :ok end}
             )

    [conversation] = Runtime.list_conversations(agent_id: agent.id, limit: 10)
    [user_turn | _] = Runtime.list_turns(conversation.id)

    assert user_turn.role == "user"
    assert user_turn.content == "See attached"

    assert [%{"kind" => "document", "file_name" => "spec.pdf"}] =
             user_turn.metadata["attachments"]
  end

  test "discord updates are routed into conversations and answered" do
    agent = create_agent()
    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    {:ok, _discord} =
      Runtime.save_discord_config(%{
        bot_token: "discord-test-token",
        application_id: "discord-app",
        enabled: true,
        default_agent_id: agent.id
      })

    deliver = fn payload ->
      send(self(), {:discord_reply, payload})
      {:ok, %{provider_message_id: "discord-message-1"}}
    end

    assert :ok =
             HydraX.Gateway.dispatch_discord_update(
               %{
                 "d" => %{
                   "id" => "discord-source-1",
                   "content" => "Discord ingress should reach the agent runtime.",
                   "channel_id" => "chan-42",
                   "author" => %{"id" => "user-1", "username" => "discord-user"}
                 }
               },
               %{deliver: deliver}
             )

    assert_receive {:discord_reply,
                    %{channel_id: "chan-42", content: content, reply_to_message_id: metadata}}

    assert content =~ "Mock response"
    assert metadata == "discord-source-1"

    [conversation] = Runtime.list_conversations(agent_id: agent.id, limit: 10)
    assert conversation.channel == "discord"

    refreshed = Runtime.get_conversation!(conversation.id)
    assert refreshed.metadata["last_delivery"]["status"] == "delivered"
    assert refreshed.metadata["last_delivery"]["formatted_payload"]["channel_id"] == "chan-42"

    assert refreshed.metadata["last_delivery"]["formatted_payload"]["reply_to_message_id"] ==
             "discord-source-1"

    assert refreshed.metadata["last_delivery"]["metadata"]["provider_message_id"] ==
             "discord-message-1"
  end

  test "discord attachment messages preserve attachment metadata" do
    agent = create_agent()
    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    {:ok, _discord} =
      Runtime.save_discord_config(%{
        bot_token: "discord-test-token",
        application_id: "discord-app",
        enabled: true,
        default_agent_id: agent.id
      })

    assert :ok =
             HydraX.Gateway.dispatch_discord_update(
               %{
                 "d" => %{
                   "id" => "discord-source-attachment",
                   "channel_id" => "chan-77",
                   "author" => %{"id" => "user-1", "username" => "discord-user"},
                   "attachments" => [
                     %{
                       "id" => "att-1",
                       "filename" => "diagram.png",
                       "content_type" => "image/png",
                       "url" => "https://cdn.discord.test/diagram.png",
                       "proxy_url" => "https://proxy.discord.test/diagram.png",
                       "size" => 2048
                     }
                   ]
                 }
               },
               %{deliver: fn _payload -> :ok end}
             )

    [conversation] = Runtime.list_conversations(agent_id: agent.id, limit: 10)
    [user_turn | _] = Runtime.list_turns(conversation.id)

    assert user_turn.role == "user"
    assert user_turn.content == "[Discord attachments: image/png]"

    assert [
             %{
               "file_name" => "diagram.png",
               "content_type" => "image/png",
               "download_ref" => "https://cdn.discord.test/diagram.png",
               "source_url" => "https://cdn.discord.test/diagram.png"
             }
           ] =
             user_turn.metadata["attachments"]
  end

  test "discord formatted payload preview includes chunk metadata for long replies" do
    preview =
      Discord.format_message(
        %{
          content: String.duplicate("b", 2_500),
          external_ref: "chan-99",
          metadata: %{"reply_to_message_id" => "source-99"}
        },
        %{}
      )

    assert preview.channel_id == "chan-99"
    assert preview.reply_to_message_id == "source-99"
    assert preview.chunk_count == 2
    assert preview.truncated
    assert String.length(preview.content) == 2_000
  end

  test "discord adapter chunks long outbound replies and reports chunk metadata" do
    {:ok, state} =
      Discord.connect(%{
        "bot_token" => "discord-token",
        "deliver" => fn payload ->
          send(self(), {:discord_chunk, payload})
          {:ok, %{provider_message_id: "discord-#{String.length(payload.content)}"}}
        end
      })

    long_content = String.duplicate("b", 2_500)

    assert {:ok, metadata} =
             Discord.deliver(
               %{
                 content: long_content,
                 external_ref: "chan-99",
                 metadata: %{"reply_to_message_id" => "source-99"}
               },
               state
             )

    assert metadata.channel == "discord"
    assert metadata.chunk_count == 2
    assert length(metadata.provider_message_ids) == 2

    assert_receive {:discord_chunk,
                    %{channel_id: "chan-99", reply_to_message_id: "source-99", content: first}}

    assert String.length(first) == 2_000

    assert_receive {:discord_chunk,
                    %{channel_id: "chan-99", reply_to_message_id: "source-99", content: second}}

    assert String.length(second) == 500
  end

  test "slack updates are routed into conversations and answered" do
    agent = create_agent()
    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    {:ok, _slack} =
      Runtime.save_slack_config(%{
        bot_token: "slack-test-token",
        signing_secret: "slack-signing-secret",
        enabled: true,
        default_agent_id: agent.id
      })

    deliver = fn payload ->
      send(self(), {:slack_reply, payload})
      {:ok, %{provider_message_id: "slack-ts"}}
    end

    assert :ok =
             HydraX.Gateway.dispatch_slack_update(
               %{
                 "type" => "event_callback",
                 "team_id" => "team-1",
                 "event" => %{
                   "type" => "message",
                   "channel" => "C123",
                   "text" => "Slack ingress should reach the agent runtime.",
                   "user" => "U123",
                   "ts" => "123.456"
                 }
               },
               %{deliver: deliver}
             )

    assert_receive {:slack_reply, %{channel: "C123", text: content, thread_ts: metadata}}
    assert content =~ "Mock response"
    assert metadata == "123.456"

    [conversation] = Runtime.list_conversations(agent_id: agent.id, limit: 10)
    assert conversation.channel == "slack"

    refreshed = Runtime.get_conversation!(conversation.id)
    assert refreshed.metadata["last_delivery"]["status"] == "delivered"
    assert refreshed.metadata["last_delivery"]["metadata"]["provider_message_id"] == "slack-ts"
    assert refreshed.metadata["last_delivery"]["metadata"]["provider_message_ids"] == ["slack-ts"]
    assert refreshed.metadata["last_delivery"]["metadata"]["chunk_count"] == 1
    assert refreshed.metadata["last_delivery"]["reply_context"]["thread_ts"] == "123.456"
    assert refreshed.metadata["last_delivery"]["formatted_payload"]["channel"] == "C123"
    assert refreshed.metadata["last_delivery"]["formatted_payload"]["thread_ts"] == "123.456"
    assert refreshed.metadata["last_delivery"]["formatted_payload"]["chunk_count"] == 1
  end

  test "slack attachment messages preserve attachment metadata" do
    agent = create_agent()
    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    {:ok, _slack} =
      Runtime.save_slack_config(%{
        bot_token: "slack-test-token",
        signing_secret: "slack-signing-secret",
        enabled: true,
        default_agent_id: agent.id
      })

    assert :ok =
             HydraX.Gateway.dispatch_slack_update(
               %{
                 "type" => "event_callback",
                 "team_id" => "team-1",
                 "event" => %{
                   "type" => "message",
                   "channel" => "C777",
                   "user" => "U123",
                   "ts" => "999.111",
                   "files" => [
                     %{
                       "id" => "F123",
                       "name" => "runbook.pdf",
                       "mimetype" => "application/pdf",
                       "url_private" => "https://slack.test/runbook.pdf",
                       "size" => 4096
                     }
                   ]
                 }
               },
               %{deliver: fn _payload -> :ok end}
             )

    [conversation] = Runtime.list_conversations(agent_id: agent.id, limit: 10)
    [user_turn | _] = Runtime.list_turns(conversation.id)

    assert user_turn.role == "user"
    assert user_turn.content == "[Slack attachments: application/pdf]"

    assert [
             %{
               "file_name" => "runbook.pdf",
               "content_type" => "application/pdf",
               "download_ref" => "https://slack.test/runbook.pdf",
               "source_url" => "https://slack.test/runbook.pdf"
             }
           ] =
             user_turn.metadata["attachments"]
  end

  test "slack formatted payload preview includes chunk metadata for long replies" do
    preview =
      HydraX.Gateway.Adapters.Slack.format_message(
        %{
          content: String.duplicate("c", 4_200),
          external_ref: "C999",
          metadata: %{"thread_ts" => "thread-999"}
        },
        %{}
      )

    assert preview.channel == "C999"
    assert preview.thread_ts == "thread-999"
    assert preview.chunk_count == 2
    assert preview.truncated
    assert String.length(preview.text) == 3_500
  end

  test "slack adapter chunks long outbound replies and reports chunk metadata" do
    {:ok, state} =
      HydraX.Gateway.Adapters.Slack.connect(%{
        "bot_token" => "slack-token",
        "deliver" => fn payload ->
          send(self(), {:slack_chunk, payload})
          {:ok, %{provider_message_id: "slack-#{String.length(payload.text)}"}}
        end
      })

    long_content = String.duplicate("c", 4_200)

    assert {:ok, metadata} =
             HydraX.Gateway.Adapters.Slack.deliver(
               %{
                 content: long_content,
                 external_ref: "C999",
                 metadata: %{"thread_ts" => "thread-999"}
               },
               state
             )

    assert metadata.channel == "slack"
    assert metadata.chunk_count == 2
    assert length(metadata.provider_message_ids) == 2

    assert_receive {:slack_chunk, %{channel: "C999", thread_ts: "thread-999", text: first}}
    assert String.length(first) == 3_500

    assert_receive {:slack_chunk, %{channel: "C999", thread_ts: "thread-999", text: second}}
    assert String.length(second) == 700
  end

  test "webchat messages are routed into conversations and answered" do
    agent = create_agent()
    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    {:ok, _webchat} =
      Runtime.save_webchat_config(%{
        title: "Hydra-X Browser",
        subtitle: "Public runtime ingress",
        welcome_prompt: "Welcome to Hydra-X.",
        composer_placeholder: "Ask a question",
        enabled: true,
        default_agent_id: agent.id
      })

    assert :ok =
             HydraX.Gateway.dispatch_webchat_message(%{
               "session_id" => "webchat-session-42",
               "content" => "Webchat should reach the runtime."
             })

    [conversation] = Runtime.list_conversations(agent_id: agent.id, limit: 10)
    assert conversation.channel == "webchat"
    assert Runtime.list_turns(conversation.id) |> length() == 2

    refreshed = Runtime.get_conversation!(conversation.id)
    assert refreshed.metadata["last_delivery"]["status"] == "delivered"
    assert refreshed.metadata["last_delivery"]["external_ref"] == "webchat-session-42"
    assert refreshed.metadata["last_delivery"]["metadata"]["streaming"] == true
  end

  test "webchat attachment messages preserve attachment metadata and display name" do
    agent = create_agent()
    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    {:ok, _webchat} =
      Runtime.save_webchat_config(%{
        title: "Hydra-X Browser",
        enabled: true,
        allow_anonymous_messages: false,
        attachments_enabled: true,
        max_attachment_count: 2,
        max_attachment_size_kb: 512,
        default_agent_id: agent.id
      })

    assert :ok =
             HydraX.Gateway.dispatch_webchat_message(%{
               "session_id" => "webchat-session-attachments",
               "content" => "",
               "display_name" => "Operator Visitor",
               "attachments" => [
                 %{
                   "kind" => "upload",
                   "file_name" => "notes.txt",
                   "content_type" => "text/plain",
                   "size" => 120,
                   "upload_ref" => "upload-1"
                 }
               ]
             })

    [conversation] = Runtime.list_conversations(agent_id: agent.id, limit: 10)
    [user_turn | _] = Runtime.list_turns(conversation.id)

    assert user_turn.content == "[Webchat attachments: text/plain]"
    assert user_turn.metadata["display_name"] == "Operator Visitor"

    assert [
             %{
               "file_name" => "notes.txt",
               "content_type" => "text/plain",
               "upload_ref" => "upload-1"
             }
           ] = user_turn.metadata["attachments"]
  end

  test "webchat rejects anonymous messages when identity is required" do
    agent = create_agent()

    {:ok, _webchat} =
      Runtime.save_webchat_config(%{
        title: "Hydra-X Browser",
        enabled: true,
        allow_anonymous_messages: false,
        default_agent_id: agent.id
      })

    assert {:error, :webchat_identity_required} =
             HydraX.Gateway.dispatch_webchat_message(%{
               "session_id" => "webchat-session-anon",
               "content" => "Anonymous message"
             })
  end

  defp create_agent do
    unique = System.unique_integer([:positive])

    {:ok, agent} =
      Runtime.save_agent(%{
        name: "Gateway Agent #{unique}",
        slug: "gateway-agent-#{unique}",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-gateway-#{unique}"),
        description: "gateway test agent",
        is_default: false
      })

    HydraX.Budget.ensure_policy!(agent.id)
    agent
  end
end
