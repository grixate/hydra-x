defmodule HydraX.Gateway do
  @moduledoc """
  Routes inbound adapter messages into agent conversations.
  """

  alias HydraX.Config
  alias HydraX.Gateway.Adapters.{Discord, Slack, Telegram, Webchat}
  alias HydraX.Runtime
  alias HydraX.Runtime.Conversation
  alias HydraX.Safety
  alias HydraX.Telemetry

  def channel_capabilities do
    %{
      "telegram" => Telegram.capabilities(),
      "discord" => Discord.capabilities(),
      "slack" => Slack.capabilities(),
      "webchat" => Webchat.capabilities()
    }
  end

  def dispatch_telegram_update(update, opts \\ %{}) do
    dispatch_channel_update(
      Runtime.enabled_telegram_config(),
      Telegram,
      adapter_config(Runtime.enabled_telegram_config(), opts),
      update,
      :telegram_not_configured
    )
  end

  def dispatch_discord_update(event, opts \\ %{}) do
    dispatch_channel_update(
      Runtime.enabled_discord_config(),
      Discord,
      discord_adapter_config(Runtime.enabled_discord_config(), opts),
      event,
      :discord_not_configured
    )
  end

  def dispatch_slack_update(event, opts \\ %{}) do
    dispatch_channel_update(
      Runtime.enabled_slack_config(),
      Slack,
      slack_adapter_config(Runtime.enabled_slack_config(), opts),
      event,
      :slack_not_configured
    )
  end

  def dispatch_webchat_message(payload, opts \\ %{}) do
    dispatch_channel_update(
      Runtime.enabled_webchat_config(),
      Webchat,
      webchat_adapter_config(Runtime.enabled_webchat_config(), opts),
      payload,
      :webchat_not_configured
    )
  end

  def retry_conversation_delivery(%Conversation{} = conversation, opts \\ %{}) do
    conversation = Runtime.get_conversation!(conversation.id)

    with delivery when is_map(delivery) <- last_delivery(conversation),
         {:ok, adapter_mod, _config, config_map} <- retry_adapter(delivery, opts),
         {:ok, state} <- adapter_mod.connect(config_map),
         %{content: content} <- latest_assistant_turn(conversation),
         true <-
           interactive_delivery_allowed?(
             conversation.agent_id,
             delivery_message(delivery).channel
           ) do
      external_ref = Map.get(delivery, "external_ref") || Map.get(delivery, :external_ref)

      payload = %{
        content: content,
        external_ref: external_ref,
        metadata: Map.get(delivery, "reply_context") || Map.get(delivery, :reply_context) || %{}
      }

      formatted_payload = adapter_format_message(adapter_mod, payload, state)
      result = adapter_deliver(adapter_mod, payload, state)

      record_delivery_result(
        conversation.agent_id,
        conversation,
        delivery_message(delivery),
        result,
        retry: true,
        formatted_payload: formatted_payload
      )
    else
      nil -> {:error, :missing_delivery}
      :no_assistant_turn -> {:error, :no_assistant_turn}
      false -> {:error, :delivery_channel_blocked_by_policy}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :channel_not_configured}
    end
  end

  def mark_streaming_delivery(%Conversation{} = conversation, opts \\ []) do
    conversation = Runtime.get_conversation!(conversation.id)

    with {:ok, adapter_mod, _config, config_map} <- channel_adapter(conversation.channel, []),
         true <- streaming_delivery_supported?(adapter_mod, conversation),
         {:ok, state} <- adapter_mod.connect(config_map) do
      previous = last_delivery(conversation) || %{}
      preview = Keyword.get(opts, :preview, "") || ""
      chunk_count = Keyword.get(opts, :chunk_count, 0) || 0

      payload = %{
        content: preview,
        external_ref: conversation.external_ref,
        chunk_count: chunk_count,
        metadata: streaming_reply_context(conversation, previous)
      }

      formatted_payload =
        adapter_format_message(adapter_mod, payload, state)
        |> maybe_put_stream_chunk_count(chunk_count)

      stream_dispatch =
        adapter_stream_delivery(adapter_mod, payload, state)

      stream_metadata =
        case stream_dispatch do
          {:ok, metadata} when is_map(metadata) -> stringify_keys(metadata)
          {:error, reason} -> %{"error" => inspect(reason)}
          _ -> %{}
        end

      delivery =
        conversation
        |> delivery_payload(streaming_message(conversation, previous),
          formatted_payload: formatted_payload
        )
        |> Map.merge(delivery_result_fields(stream_metadata))
        |> Map.put("status", "streaming")
        |> Map.put("attempted_at", DateTime.utc_now())
        |> Map.put("chunk_count", chunk_count)
        |> Map.put("metadata", %{
          "streaming" => true,
          "provider" => Keyword.get(opts, :provider),
          "preview_chars" => String.length(preview),
          "transport" => stream_metadata["transport"],
          "transport_topic" => stream_metadata["topic"],
          "transport_error" => stream_metadata["error"]
        })
        |> Map.put_new("streaming_started_at", DateTime.utc_now())
        |> Map.delete("delivered_at")
        |> Map.delete("dead_lettered_at")
        |> Map.delete("reason")
        |> Map.delete("next_retry_at")
        |> Map.delete("next_retry_in_ms")
        |> Map.delete("pending_retry_attempt")
        |> Map.delete("retry_backoff_ms")
        |> with_stream_reply_context()

      Runtime.update_conversation_metadata(conversation, %{"last_delivery" => delivery})
    else
      false -> {:error, :streaming_not_supported}
      {:error, reason} -> {:error, reason}
    end
  end

  def process_deferred_deliveries(opts \\ []) do
    owner = Keyword.get(opts, :owner, Runtime.coordination_status().owner)
    limit = Keyword.get(opts, :limit, 50)

    results =
      Runtime.list_owned_pending_deliveries(owner: owner, limit: limit)
      |> Enum.map(fn conversation ->
        case retry_conversation_delivery(conversation, Map.new(opts)) do
          {:ok, _updated} ->
            %{
              conversation_id: conversation.id,
              agent_id: conversation.agent_id,
              status: "delivered"
            }

          {:error, :no_assistant_turn} ->
            %{
              conversation_id: conversation.id,
              agent_id: conversation.agent_id,
              status: "skipped",
              reason: "no_assistant_turn"
            }

          {:error, reason} ->
            %{
              conversation_id: conversation.id,
              agent_id: conversation.agent_id,
              status: "error",
              reason: inspect(reason)
            }
        end
      end)

    summary = %{
      owner: owner,
      delivered_count: Enum.count(results, &(&1.status == "delivered")),
      skipped_count: Enum.count(results, &(&1.status == "skipped")),
      error_count: Enum.count(results, &(&1.status == "error")),
      results: results
    }

    _ = HydraX.Runtime.Jobs.record_scheduler_pass(:deferred_deliveries, summary)
    summary
  end

  def process_owned_ingress(opts \\ []) do
    owner = Keyword.get(opts, :owner, Runtime.coordination_status().owner)
    limit = Keyword.get(opts, :limit, 50)

    results =
      Runtime.list_owned_pending_ingress_conversations(owner: owner, limit: limit)
      |> Enum.map(&process_ingress_conversation(&1, opts))

    summary = %{
      owner: owner,
      processed_count: Enum.count(results, &(&1.status == "processed")),
      skipped_count: Enum.count(results, &(&1.status == "skipped")),
      error_count: Enum.count(results, &(&1.status == "error")),
      results: results
    }

    _ = HydraX.Runtime.Jobs.record_scheduler_pass(:pending_ingress, summary)
    summary
  end

  @max_retries 3
  @retry_backoffs [5_000, 30_000, 120_000]

  defp route_message(message, state, config, adapter_mod, opts \\ []) do
    agent = config.default_agent || Runtime.ensure_default_agent!()

    case maybe_queue_ingress(agent, message, opts) do
      {:queued, _conversation} ->
        :ok

      :route ->
        {:ok, _pid} = HydraX.Agent.ensure_started(agent)

        conversation =
          Runtime.find_conversation(agent.id, message.channel, message.external_ref) ||
            start_channel_conversation(agent, message)

        case HydraX.Agent.Channel.submit(
               agent,
               conversation,
               message.content,
               Map.merge(message.metadata || %{}, %{source: message.channel})
             ) do
          {:deferred, reason} ->
            Runtime.update_conversation_metadata(conversation, %{
              "last_delivery" => %{
                "channel" => message.channel,
                "status" => "deferred",
                "external_ref" => message.external_ref,
                "reason" => reason,
                "reply_context" => delivery_context(message),
                "metadata" => %{"ownership_deferred" => true}
              }
            })

            :ok

          response ->
            delivery_conversation = Runtime.get_conversation!(conversation.id)

            payload = %{
              content: response,
              external_ref: message.external_ref,
              metadata: delivery_context_for(delivery_conversation, message)
            }

            formatted_payload = adapter_format_message(adapter_mod, payload, state)

            delivery_result =
              if interactive_delivery_allowed?(agent.id, message.channel) do
                adapter_deliver(adapter_mod, payload, state)
              else
                {:error, :delivery_channel_blocked_by_policy}
              end

            record_delivery_result(
              agent.id,
              delivery_conversation,
              message,
              delivery_result,
              formatted_payload: formatted_payload
            )

            case delivery_result do
              {:error, :delivery_channel_blocked_by_policy} ->
                :ok

              {:error, _reason} ->
                schedule_retry(
                  agent.id,
                  delivery_conversation.id,
                  message,
                  adapter_mod,
                  config,
                  0
                )

              _ ->
                :ok
            end
        end
    end
  end

  defp schedule_retry(_agent_id, _conversation_id, _message, _adapter_mod, _config, attempt)
       when attempt >= @max_retries,
       do: :ok

  defp schedule_retry(agent_id, conversation_id, message, adapter_mod, config, attempt) do
    delay = Enum.at(@retry_backoffs, attempt, List.last(@retry_backoffs))
    conversation = Runtime.get_conversation!(conversation_id)

    mark_retry_scheduled(conversation, message, attempt + 1, delay)

    Task.Supervisor.start_child(HydraX.TaskSupervisor, fn ->
      Process.sleep(delay)
      execute_retry(agent_id, conversation_id, message, adapter_mod, config, attempt)
    end)
  end

  defp execute_retry(agent_id, conversation_id, message, adapter_mod, config, attempt) do
    conversation = Runtime.get_conversation!(conversation_id)

    with {:ok, state} <- adapter_mod.connect(retry_adapter_config(adapter_mod, config)),
         %{content: content} <- latest_assistant_turn(conversation) do
      payload = %{
        content: content,
        external_ref: message.external_ref,
        metadata: delivery_context_for(conversation, message)
      }

      formatted_payload = adapter_format_message(adapter_mod, payload, state)

      result =
        if interactive_delivery_allowed?(agent_id, message.channel) do
          adapter_deliver(adapter_mod, payload, state)
        else
          {:error, :delivery_channel_blocked_by_policy}
        end

      record_delivery_result(
        agent_id,
        conversation,
        message,
        result,
        retry: true,
        formatted_payload: formatted_payload
      )

      case result do
        {:error, :delivery_channel_blocked_by_policy} ->
          :ok

        {:error, _reason} ->
          next_attempt = attempt + 1

          if next_attempt >= @max_retries do
            mark_dead_letter(agent_id, conversation, message, adapter_mod)
          else
            schedule_retry(agent_id, conversation_id, message, adapter_mod, config, next_attempt)
          end

        _ ->
          :ok
      end
    end
  rescue
    _error -> :ok
  end

  defp mark_dead_letter(agent_id, conversation, message, adapter_mod) do
    Safety.log_event(%{
      agent_id: agent_id,
      conversation_id: conversation.id,
      category: "gateway",
      level: "error",
      message:
        "#{adapter_channel(adapter_mod)} delivery dead-lettered after #{@max_retries} retries",
      metadata: %{
        channel: message.channel,
        external_ref: message.external_ref
      }
    })

    delivery =
      conversation
      |> delivery_payload(message, retry: true)
      |> Map.put("status", "dead_letter")
      |> Map.put("dead_lettered_at", DateTime.utc_now())
      |> Map.delete("next_retry_at")
      |> Map.delete("next_retry_in_ms")
      |> Map.delete("pending_retry_attempt")
      |> Map.delete("retry_backoff_ms")
      |> Map.put("retry_limit", @max_retries)
      |> with_attempt_history(conversation)

    Runtime.update_conversation_metadata(conversation, %{"last_delivery" => delivery})
  end

  defp route_channel_message(message, state, config, adapter_mod) do
    route_message(message, state, config, adapter_mod)
  end

  defp maybe_queue_ingress(agent, message, opts) do
    external_ref = message.external_ref

    cond do
      opts[:skip_ingress_claim] ->
        :route

      not is_binary(external_ref) or external_ref == "" ->
        :route

      not Config.repo_multi_writer?() ->
        :route

      true ->
        case Runtime.claim_lease(
               ingress_lease_name(message.channel, message.external_ref),
               ttl_seconds: ingress_lease_ttl_seconds(),
               metadata: %{
                 "type" => "ingress",
                 "channel" => message.channel,
                 "external_ref" => message.external_ref
               }
             ) do
          {:ok, _lease} ->
            :route

          {:error, {:taken, lease}} ->
            {:queued, queue_ingress_message(agent, message, lease)}

          {:error, _reason} ->
            :route
        end
    end
  end

  defp start_channel_conversation(agent, message) do
    {:ok, conversation} =
      Runtime.start_conversation(agent, %{
        channel: message.channel,
        external_ref: message.external_ref,
        title: "#{String.capitalize(message.channel)} #{message.external_ref}",
        metadata: %{source: message.channel}
      })

    conversation
  end

  defp queue_ingress_message(agent, message, lease) do
    conversation =
      Runtime.find_conversation(agent.id, message.channel, message.external_ref) ||
        start_channel_conversation(agent, message)

    existing = Runtime.get_checkpoint(conversation.id, "ingress")
    state = (existing && existing.state) || %{}
    messages = state["messages"] || []

    Runtime.upsert_checkpoint(conversation.id, "ingress", %{
      "status" => "queued",
      "channel" => message.channel,
      "external_ref" => message.external_ref,
      "owner" => lease.owner,
      "owner_node" => lease.owner_node,
      "lease_name" => lease.name,
      "message_count" => length(messages) + 1,
      "messages" => messages ++ [ingress_message_entry(message)],
      "updated_at" => DateTime.utc_now()
    })

    conversation
  end

  defp adapter_config(config, opts) do
    %{
      "bot_token" => config && config.bot_token,
      "bot_username" => config && config.bot_username,
      "webhook_secret" => config && config.webhook_secret,
      "deliver" => Map.get(opts, :deliver) || Application.get_env(:hydra_x, :telegram_deliver),
      "deliver_stream" =>
        Map.get(opts, :deliver_stream) || Application.get_env(:hydra_x, :telegram_deliver_stream)
    }
  end

  defp discord_adapter_config(config, opts) do
    %{
      "bot_token" => config && config.bot_token,
      "application_id" => config && config.application_id,
      "webhook_secret" => config && config.webhook_secret,
      "deliver" => Map.get(opts, :deliver) || Application.get_env(:hydra_x, :discord_deliver)
    }
  end

  defp slack_adapter_config(config, opts) do
    %{
      "bot_token" => config && config.bot_token,
      "signing_secret" => config && config.signing_secret,
      "deliver" => Map.get(opts, :deliver) || Application.get_env(:hydra_x, :slack_deliver)
    }
  end

  defp webchat_adapter_config(config, _opts) do
    %{
      "enabled" => config && config.enabled,
      "title" => config && config.title,
      "subtitle" => config && config.subtitle,
      "welcome_prompt" => config && config.welcome_prompt,
      "composer_placeholder" => config && config.composer_placeholder,
      "allow_anonymous_messages" => config && config.allow_anonymous_messages,
      "session_max_age_minutes" => config && config.session_max_age_minutes,
      "session_idle_timeout_minutes" => config && config.session_idle_timeout_minutes,
      "attachments_enabled" => config && config.attachments_enabled,
      "max_attachment_count" => config && config.max_attachment_count,
      "max_attachment_size_kb" => config && config.max_attachment_size_kb
    }
  end

  defp process_ingress_conversation(conversation, opts) do
    with {:ok, adapter_mod, config, config_map} <- channel_adapter(conversation.channel, opts),
         {:ok, state} <- adapter_mod.connect(config_map),
         {:ok, entries} <- ingress_entries(conversation),
         {:ok, _results} <- replay_ingress_entries(entries, state, config, adapter_mod),
         {:ok, _checkpoint} <- clear_ingress_queue(conversation, entries) do
      %{
        conversation_id: conversation.id,
        agent_id: conversation.agent_id,
        status: "processed",
        message_count: length(entries)
      }
    else
      {:error, :empty_queue} ->
        %{
          conversation_id: conversation.id,
          agent_id: conversation.agent_id,
          status: "skipped",
          reason: "empty_queue"
        }

      {:error, reason} ->
        %{
          conversation_id: conversation.id,
          agent_id: conversation.agent_id,
          status: "error",
          reason: inspect(reason)
        }
    end
  end

  defp replay_ingress_entries(entries, state, config, adapter_mod) do
    Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, acc} ->
      message = ingress_entry_message(entry)

      case route_message(message, state, config, adapter_mod, skip_ingress_claim: true) do
        :ok -> {:cont, {:ok, [message | acc]}}
        other -> {:halt, {:error, other}}
      end
    end)
  end

  defp ingress_entries(conversation) do
    checkpoint = Runtime.get_checkpoint(conversation.id, "ingress")
    state = (checkpoint && checkpoint.state) || %{}

    case state["messages"] || [] do
      [] -> {:error, :empty_queue}
      entries -> {:ok, entries}
    end
  end

  defp clear_ingress_queue(conversation, processed_entries) do
    checkpoint = Runtime.get_checkpoint(conversation.id, "ingress")
    state = (checkpoint && checkpoint.state) || %{}
    remaining = Enum.drop(state["messages"] || [], length(processed_entries))

    Runtime.upsert_checkpoint(conversation.id, "ingress", %{
      "status" => if(remaining == [], do: "processed", else: "queued"),
      "channel" => state["channel"] || conversation.channel,
      "external_ref" => state["external_ref"] || conversation.external_ref,
      "owner" => state["owner"],
      "owner_node" => state["owner_node"],
      "lease_name" => state["lease_name"],
      "message_count" => length(remaining),
      "messages" => remaining,
      "processed_at" => DateTime.utc_now(),
      "updated_at" => DateTime.utc_now()
    })
  end

  defp record_delivery_result(agent_id, conversation, message, result, opts)

  defp record_delivery_result(_agent_id, conversation, message, {:ok, metadata}, opts)
       when is_map(metadata) do
    Telemetry.gateway_delivery(message.channel, :ok)

    stringified_metadata = stringify_keys(metadata)

    delivery =
      conversation
      |> delivery_payload(message, opts)
      |> Map.merge(delivery_result_fields(stringified_metadata))
      |> Map.put("metadata", stringified_metadata)
      |> Map.put("status", "delivered")
      |> Map.put("delivered_at", DateTime.utc_now())
      |> Map.delete("reason")
      |> Map.delete("next_retry_at")
      |> Map.delete("next_retry_in_ms")
      |> Map.delete("pending_retry_attempt")
      |> Map.delete("retry_backoff_ms")
      |> with_attempt_history(conversation)

    Runtime.update_conversation_metadata(conversation, %{
      "last_delivery" => delivery
    })
  end

  defp record_delivery_result(agent_id, conversation, message, :ok, opts) do
    record_delivery_result(agent_id, conversation, message, {:ok, %{}}, opts)
  end

  defp record_delivery_result(agent_id, conversation, message, {:error, reason}, opts) do
    reason_text = inspect(reason)
    Telemetry.gateway_delivery(message.channel, :error, %{reason: reason_text})

    Safety.log_event(%{
      agent_id: agent_id,
      conversation_id: conversation.id,
      category: "gateway",
      level: "error",
      message: "#{String.capitalize(message.channel)} delivery failed",
      metadata: %{
        channel: message.channel,
        external_ref: message.external_ref,
        reason: reason_text
      }
    })

    delivery =
      conversation
      |> delivery_payload(message, opts)
      |> Map.put("status", "failed")
      |> Map.put("attempted_at", DateTime.utc_now())
      |> Map.put("reason", reason_text)
      |> Map.put("retry_limit", @max_retries)
      |> with_attempt_history(conversation)

    Runtime.update_conversation_metadata(conversation, %{"last_delivery" => delivery})
  end

  defp stringify_keys(map) do
    Enum.reduce(map, %{}, fn
      {key, value}, acc when is_atom(key) -> Map.put(acc, Atom.to_string(key), value)
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end

  defp last_delivery(conversation) do
    metadata = conversation.metadata || %{}
    metadata["last_delivery"] || metadata[:last_delivery]
  end

  defp latest_assistant_turn(conversation) do
    conversation.turns
    |> Enum.reverse()
    |> Enum.find(:no_assistant_turn, &(&1.role == "assistant"))
  end

  defp delivery_message(delivery) do
    %{
      channel: Map.get(delivery, "channel") || Map.get(delivery, :channel) || "telegram",
      external_ref: Map.get(delivery, "external_ref") || Map.get(delivery, :external_ref),
      metadata: Map.get(delivery, "reply_context") || Map.get(delivery, :reply_context) || %{}
    }
  end

  defp validate_delivery(delivery) do
    channel = Map.get(delivery, "channel") || Map.get(delivery, :channel)
    external_ref = Map.get(delivery, "external_ref") || Map.get(delivery, :external_ref)

    cond do
      channel not in ~w(telegram discord slack webchat) ->
        {:error, {:unsupported_channel, channel}}

      not (is_binary(external_ref) and external_ref != "") ->
        {:error, :missing_external_ref}

      true ->
        :ok
    end
  end

  defp delivery_payload(conversation, message, opts) do
    previous = last_delivery(conversation) || %{}

    retries =
      case previous do
        %{"retry_count" => count} when is_integer(count) -> count
        %{retry_count: count} when is_integer(count) -> count
        _ -> 0
      end

    retry_count = if Keyword.get(opts, :retry, false), do: retries + 1, else: retries

    %{
      "channel" => message.channel,
      "external_ref" => message.external_ref,
      "retry_count" => retry_count,
      "reply_context" => stringify_keys(delivery_context(message)),
      "formatted_payload" =>
        opts
        |> Keyword.get(:formatted_payload, %{})
        |> stringify_keys()
    }
    |> maybe_put_existing("attempt_history", delivery_value(previous, "attempt_history"))
    |> maybe_put_existing("first_attempted_at", delivery_value(previous, "first_attempted_at"))
  end

  defp maybe_put_stream_chunk_count(payload, count)
       when is_map(payload) and is_integer(count) and count > 0,
       do: Map.put(payload, "chunk_count", count)

  defp maybe_put_stream_chunk_count(payload, _count), do: payload

  defp delivery_context(%{metadata: metadata}) when is_map(metadata) do
    metadata
    |> stringify_keys()
    |> Map.take(["reply_to_message_id", "thread_ts", "source_message_id", "stream_message_id"])
  end

  defp delivery_context(_message), do: %{}

  defp delivery_context_for(conversation, message) do
    message
    |> delivery_context()
    |> maybe_put_stream_message_id(
      conversation
      |> last_delivery()
      |> previous_stream_message_id()
    )
  end

  defp maybe_put_stream_message_id(context, nil), do: context

  defp maybe_put_stream_message_id(context, message_id),
    do: Map.put(context, "stream_message_id", message_id)

  defp with_stream_reply_context(delivery) do
    message_id = delivery["provider_message_id"] || delivery[:provider_message_id]

    if is_nil(message_id) do
      delivery
    else
      Map.update(delivery, "reply_context", %{"stream_message_id" => message_id}, fn context ->
        context
        |> stringify_keys()
        |> Map.put("stream_message_id", message_id)
      end)
    end
  end

  defp mark_retry_scheduled(conversation, message, pending_retry_attempt, delay_ms) do
    previous = last_delivery(conversation) || %{}
    next_retry_at = DateTime.add(DateTime.utc_now(), delay_ms, :millisecond)

    delivery =
      previous
      |> Map.merge(delivery_payload(conversation, message, retry: false))
      |> Map.put("next_retry_at", next_retry_at)
      |> Map.put("next_retry_in_ms", delay_ms)
      |> Map.put("pending_retry_attempt", pending_retry_attempt)
      |> Map.put("retry_backoff_ms", delay_ms)
      |> Map.put("retry_limit", @max_retries)

    Runtime.update_conversation_metadata(conversation, %{"last_delivery" => delivery})
  end

  defp with_attempt_history(delivery, conversation) do
    previous = last_delivery(conversation) || %{}

    history =
      previous
      |> delivery_value("attempt_history")
      |> List.wrap()
      |> Enum.take(-9)
      |> Kernel.++([delivery_attempt_entry(delivery)])

    delivery
    |> Map.put("attempt_history", history)
    |> Map.put_new(
      "first_attempted_at",
      delivery["attempted_at"] || delivery["delivered_at"] || delivery["dead_lettered_at"]
    )
  end

  defp delivery_attempt_entry(delivery) do
    %{
      "status" => delivery["status"],
      "recorded_at" =>
        delivery["delivered_at"] || delivery["attempted_at"] || delivery["dead_lettered_at"],
      "retry_count" => delivery["retry_count"] || 0,
      "reason" => delivery["reason"],
      "provider_message_id" => delivery["provider_message_id"],
      "provider_message_ids" => delivery["provider_message_ids"] || [],
      "chunk_count" => delivery["chunk_count"],
      "reply_context" => delivery["reply_context"] || %{}
    }
  end

  defp delivery_result_fields(metadata) do
    %{
      "provider_message_id" => Map.get(metadata, "provider_message_id"),
      "provider_message_ids" => Map.get(metadata, "provider_message_ids") || [],
      "chunk_count" => Map.get(metadata, "chunk_count"),
      "streaming" => Map.get(metadata, "streaming")
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp streaming_delivery_supported?(adapter_mod, %Conversation{
         channel: channel,
         external_ref: external_ref
       })
       when is_binary(channel) and is_binary(external_ref) and external_ref != "" do
    capabilities =
      if function_exported?(adapter_mod, :capabilities, 0),
        do: adapter_mod.capabilities(),
        else: %{}

    Map.get(capabilities, :streaming) || Map.get(capabilities, "streaming") || false
  end

  defp streaming_delivery_supported?(_adapter_mod, _conversation), do: false

  defp streaming_message(conversation, previous) do
    %{
      channel: conversation.channel,
      external_ref: conversation.external_ref,
      metadata: streaming_reply_context(conversation, previous)
    }
  end

  defp streaming_reply_context(_conversation, previous) do
    previous
    |> delivery_value("reply_context")
    |> Kernel.||(%{})
    |> maybe_put_stream_message_id(previous_stream_message_id(previous))
  end

  defp maybe_put_existing(map, _key, nil), do: map
  defp maybe_put_existing(map, key, value), do: Map.put(map, key, value)

  defp delivery_value(delivery, key) do
    Map.get(delivery, key) ||
      case key do
        "attempt_history" -> Map.get(delivery, :attempt_history)
        "first_attempted_at" -> Map.get(delivery, :first_attempted_at)
        "retry_count" -> Map.get(delivery, :retry_count)
        _ -> nil
      end
  end

  defp previous_stream_message_id(%{"status" => "streaming"} = delivery) do
    delivery["provider_message_id"] || delivery[:provider_message_id]
  end

  defp previous_stream_message_id(%{status: "streaming"} = delivery) do
    delivery[:provider_message_id] || delivery["provider_message_id"]
  end

  defp previous_stream_message_id(_delivery), do: nil

  defp dispatch_channel_update(nil, _adapter_mod, _adapter_config, _event, error),
    do: {:error, error}

  defp dispatch_channel_update(config, adapter_mod, adapter_config, event, _error) do
    with {:ok, state} <- adapter_mod.connect(adapter_config),
         {:ok, messages} <- adapter_normalize_inbound(adapter_mod, event, state) do
      Enum.each(messages, &route_channel_message(&1, state, config, adapter_mod))
      :ok
    end
  end

  defp adapter_normalize_inbound(adapter_mod, event, state) do
    cond do
      function_exported?(adapter_mod, :normalize_inbound, 2) ->
        adapter_mod.normalize_inbound(event, state)

      function_exported?(adapter_mod, :normalize_inbound, 1) ->
        adapter_mod.normalize_inbound(event)

      true ->
        case adapter_mod.handle_event(event, state) do
          {:messages, messages, _state} -> {:ok, messages}
          other -> {:error, {:unexpected_adapter_response, other}}
        end
    end
  end

  defp adapter_deliver(adapter_mod, payload, state) do
    cond do
      function_exported?(adapter_mod, :deliver, 2) ->
        adapter_mod.deliver(payload, state)

      true ->
        adapter_mod.send_response(payload, state)
    end
  end

  defp adapter_stream_delivery(adapter_mod, payload, state) do
    if function_exported?(adapter_mod, :deliver_stream, 2) do
      adapter_mod.deliver_stream(payload, state)
    else
      :unsupported
    end
  end

  defp adapter_format_message(adapter_mod, payload, state) do
    cond do
      function_exported?(adapter_mod, :format_message, 2) ->
        payload
        |> adapter_mod.format_message(state)
        |> stringify_keys()

      true ->
        stringify_keys(payload)
    end
  end

  defp interactive_delivery_allowed?(agent_id, channel) do
    Runtime.authorize_delivery(agent_id, :interactive, channel) == :ok
  end

  defp retry_adapter(delivery, opts) do
    with :ok <- validate_delivery(delivery) do
      channel = Map.get(delivery, "channel") || Map.get(delivery, :channel)

      case channel do
        "telegram" ->
          config = Runtime.enabled_telegram_config()

          maybe_retry_adapter(
            Telegram,
            config,
            adapter_config(config, opts),
            :telegram_not_configured
          )

        "discord" ->
          config = Runtime.enabled_discord_config()

          maybe_retry_adapter(
            Discord,
            config,
            discord_adapter_config(config, opts),
            :discord_not_configured
          )

        "slack" ->
          config = Runtime.enabled_slack_config()

          maybe_retry_adapter(
            Slack,
            config,
            slack_adapter_config(config, opts),
            :slack_not_configured
          )

        "webchat" ->
          config = Runtime.enabled_webchat_config()

          maybe_retry_adapter(
            Webchat,
            config,
            webchat_adapter_config(config, opts),
            :webchat_not_configured
          )
      end
    end
  end

  defp maybe_retry_adapter(_adapter_mod, nil, _config_map, error), do: {:error, error}

  defp maybe_retry_adapter(adapter_mod, config, config_map, _error),
    do: {:ok, adapter_mod, config, config_map}

  defp channel_adapter("telegram", opts) do
    config = Runtime.enabled_telegram_config()

    maybe_retry_adapter(
      Telegram,
      config,
      adapter_config(config, Map.new(opts)),
      :telegram_not_configured
    )
  end

  defp channel_adapter("discord", opts) do
    config = Runtime.enabled_discord_config()

    maybe_retry_adapter(
      Discord,
      config,
      discord_adapter_config(config, Map.new(opts)),
      :discord_not_configured
    )
  end

  defp channel_adapter("slack", opts) do
    config = Runtime.enabled_slack_config()

    maybe_retry_adapter(
      Slack,
      config,
      slack_adapter_config(config, Map.new(opts)),
      :slack_not_configured
    )
  end

  defp channel_adapter("webchat", opts) do
    config = Runtime.enabled_webchat_config()

    maybe_retry_adapter(
      Webchat,
      config,
      webchat_adapter_config(config, Map.new(opts)),
      :webchat_not_configured
    )
  end

  defp channel_adapter(channel, _opts), do: {:error, {:unsupported_channel, channel}}

  defp retry_adapter_config(Telegram, config), do: adapter_config(config, %{})
  defp retry_adapter_config(Discord, config), do: discord_adapter_config(config, %{})
  defp retry_adapter_config(Slack, config), do: slack_adapter_config(config, %{})
  defp retry_adapter_config(Webchat, config), do: webchat_adapter_config(config, %{})

  defp adapter_channel(Telegram), do: "Telegram"
  defp adapter_channel(Discord), do: "Discord"
  defp adapter_channel(Slack), do: "Slack"
  defp adapter_channel(Webchat), do: "Webchat"

  defp ingress_lease_name(channel, external_ref), do: "ingress:#{channel}:#{external_ref}"
  defp ingress_lease_ttl_seconds, do: 3_600

  defp ingress_message_entry(message) do
    %{
      "channel" => message.channel,
      "external_ref" => message.external_ref,
      "content" => message.content,
      "metadata" => stringify_keys(message.metadata || %{}),
      "queued_at" => DateTime.utc_now()
    }
  end

  defp ingress_entry_message(entry) do
    %{
      channel: entry["channel"],
      external_ref: entry["external_ref"],
      content: entry["content"],
      metadata: entry["metadata"] || %{}
    }
  end
end
