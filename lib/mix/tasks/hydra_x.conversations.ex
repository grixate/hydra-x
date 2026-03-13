defmodule Mix.Tasks.HydraX.Conversations do
  use Mix.Task

  @shortdoc "Lists conversations, sends messages, or retries failed channel deliveries"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      ["start", message | rest] ->
        start_conversation(message, rest)

      ["send", id, message | _rest] ->
        send_message(id, message)

      ["archive", id] ->
        archive_conversation(id)

      ["show", id] ->
        show_conversation(id)

      ["export", id] ->
        export_conversation(id)

      ["compact", id] ->
        compact_conversation(id)

      ["reset-compact", id] ->
        reset_compaction(id)

      ["retry-delivery", id] ->
        retry_delivery(id)

      _ ->
        list_conversations(args)
    end
  end

  defp retry_delivery(id) do
    conversation = HydraX.Runtime.get_conversation!(String.to_integer(id))

    case HydraX.Gateway.retry_conversation_delivery(conversation) do
      {:ok, updated} ->
        Mix.shell().info(
          "Retried #{updated.metadata["last_delivery"]["channel"]} delivery for conversation #{updated.id}"
        )

      {:error, reason} ->
        Mix.raise("retry failed: #{inspect(reason)}")
    end
  end

  defp start_conversation(message, rest) do
    {opts, _args, _invalid} =
      OptionParser.parse(rest, strict: [agent: :string, channel: :string, title: :string])

    agent =
      case opts[:agent] do
        nil -> HydraX.Runtime.ensure_default_agent!()
        slug -> HydraX.Runtime.get_agent_by_slug(slug) || raise "unknown agent #{slug}"
      end

    {:ok, _pid} = HydraX.Agent.ensure_started(agent)

    {:ok, conversation} =
      HydraX.Runtime.start_conversation(agent, %{
        channel: opts[:channel] || "control_plane",
        title: opts[:title] || "Control plane · #{Date.utc_today()}",
        metadata: %{"source" => "mix hydra_x.conversations"}
      })

    response =
      HydraX.Agent.Channel.submit(agent, conversation, message, %{"source" => "control_plane"})

    Mix.shell().info("conversation=#{conversation.id}")
    Mix.shell().info(render_channel_response(response))
  end

  defp send_message(id, message) do
    conversation = HydraX.Runtime.get_conversation!(String.to_integer(id))
    agent = conversation.agent || HydraX.Runtime.get_agent!(conversation.agent_id)

    {:ok, _pid} = HydraX.Agent.ensure_started(agent)

    response =
      HydraX.Agent.Channel.submit(agent, conversation, message, %{"source" => "control_plane"})

    Mix.shell().info("conversation=#{conversation.id}")
    Mix.shell().info(render_channel_response(response))
  end

  defp archive_conversation(id) do
    conversation = HydraX.Runtime.archive_conversation!(String.to_integer(id))
    Mix.shell().info("conversation=#{conversation.id}")
    Mix.shell().info("status=#{conversation.status}")
  end

  defp show_conversation(id) do
    conversation = HydraX.Runtime.get_conversation!(String.to_integer(id))
    channel_state = HydraX.Runtime.conversation_channel_state(conversation.id)
    delivery = (conversation.metadata || %{})["last_delivery"] || %{}
    attachment_count = conversation_attachment_count(conversation)

    Mix.shell().info("conversation=#{conversation.id}")
    Mix.shell().info("title=#{conversation.title || "Untitled"}")
    Mix.shell().info("channel=#{conversation.channel}")
    Mix.shell().info("status=#{conversation.status}")
    Mix.shell().info("external_ref=#{conversation.external_ref || "n/a"}")
    Mix.shell().info("turns=#{length(conversation.turns)}")
    Mix.shell().info("attachments=#{attachment_count}")
    Mix.shell().info("execution_status=#{channel_state.status || "idle"}")
    Mix.shell().info("owner=#{ownership_label(channel_state.ownership)}")
    Mix.shell().info("provider=#{channel_state.provider || "n/a"}")
    Mix.shell().info("tool_rounds=#{channel_state.tool_rounds || 0}")
    Mix.shell().info("resumable=#{channel_state.resumable}")
    Mix.shell().info("cache_scope_turn_id=#{channel_state.tool_cache_scope_turn_id || "n/a"}")

    if handoff = handoff_label(channel_state.handoff) do
      Mix.shell().info("handoff=#{handoff}")
    end

    if pending_response = pending_response_label(channel_state.pending_response) do
      Mix.shell().info("pending_response=#{pending_response}")
    end

    if stream_capture = stream_capture_label(channel_state.stream_capture) do
      Mix.shell().info("stream_capture=#{stream_capture}")
    end

    if preview = stream_capture_preview(channel_state.stream_capture) do
      Mix.shell().info("stream_capture_preview=#{preview}")
    end

    if is_map(channel_state.recovery_lineage) and channel_state.recovery_lineage != %{} do
      Mix.shell().info(
        "recovery_lineage=turn:#{channel_state.recovery_lineage["turn_scope_id"] || "n/a"} recoveries:#{channel_state.recovery_lineage["recovery_count"] || 0} cache_hits:#{channel_state.recovery_lineage["cache_hits"] || 0} cache_misses:#{channel_state.recovery_lineage["cache_misses"] || 0}"
      )
    end

    if map_size(delivery) > 0 do
      Mix.shell().info(
        "delivery=#{delivery["channel"] || "channel"}:#{delivery["status"] || "unknown"}"
      )

      Enum.each(delivery_labels(delivery), fn line -> Mix.shell().info(line) end)

      if payload_preview = delivery_payload_preview(delivery) do
        Mix.shell().info("payload_preview=#{payload_preview}")
      end

      Enum.each(delivery_attempt_lines(delivery), fn line -> Mix.shell().info(line) end)
    end

    Enum.each(turn_attachment_lines(conversation), fn line -> Mix.shell().info(line) end)

    Enum.each(channel_state.tool_results || [], fn result ->
      Mix.shell().info("tool_result\t#{tool_result_summary(result)}")
    end)

    Enum.each(channel_state.steps || [], fn step ->
      Mix.shell().info(
        Enum.join(
          [
            "step",
            step["kind"] || "step",
            step["name"] || step["label"] || step["id"],
            step["status"] || "pending",
            step["summary"] || step["reason"] || step["label"] || "",
            step["lifecycle"] || "",
            step["result_source"] || "",
            if(step["cached"], do: "cached", else: ""),
            if(step["replay_count"], do: "replay=#{step["replay_count"]}", else: ""),
            if(step["tool_use_id"], do: "tool_use_id=#{step["tool_use_id"]}", else: ""),
            retry_state_label(step["retry_state"])
          ],
          "\t"
        )
      )
    end)

    Enum.each(channel_state.execution_events || [], fn event ->
      details = event["details"] || %{}

      Mix.shell().info(
        Enum.join(
          [
            "event",
            event["phase"] || "unknown",
            details["summary"] || details["tool_name"] || details["provider"] || "",
            to_string(details["round"] || ""),
            if(details["kind"], do: "kind=#{details["kind"]}", else: ""),
            if(details["name"], do: "name=#{details["name"]}", else: ""),
            if(details["lifecycle"], do: "lifecycle=#{details["lifecycle"]}", else: ""),
            if(details["result_source"],
              do: "result_source=#{details["result_source"]}",
              else: ""
            ),
            if(details["tool_use_id"], do: "tool_use_id=#{details["tool_use_id"]}", else: ""),
            if(details["cached"], do: "cached", else: ""),
            if(details["replayed"], do: "replayed", else: ""),
            if(details["cache_hits"], do: "cache_hits=#{details["cache_hits"]}", else: ""),
            if(details["cache_misses"], do: "cache_misses=#{details["cache_misses"]}", else: ""),
            if(details["waiting_for"], do: "waiting_for=#{details["waiting_for"]}", else: ""),
            if(details["captured_chars"],
              do: "captured_chars=#{details["captured_chars"]}",
              else: ""
            ),
            if(details["captured_chunks"],
              do: "captured_chunks=#{details["captured_chunks"]}",
              else: ""
            )
          ],
          "\t"
        )
      )
    end)
  end

  defp export_conversation(id) do
    export = HydraX.Runtime.export_conversation_transcript!(String.to_integer(id))
    Mix.shell().info("conversation=#{export.conversation.id}")
    Mix.shell().info("path=#{export.path}")
  end

  defp compact_conversation(id) do
    compaction = HydraX.Runtime.review_conversation_compaction!(String.to_integer(id))
    Mix.shell().info("conversation=#{compaction.conversation.id}")
    Mix.shell().info("turn_count=#{compaction.turn_count}")
    Mix.shell().info("level=#{compaction.level || "idle"}")
    Mix.shell().info("soft=#{compaction.thresholds.soft}")
    Mix.shell().info("medium=#{compaction.thresholds.medium}")
    Mix.shell().info("hard=#{compaction.thresholds.hard}")
    Mix.shell().info(compaction.summary || "No summary checkpoint yet")
  end

  defp reset_compaction(id) do
    compaction = HydraX.Runtime.reset_conversation_compaction!(String.to_integer(id))
    Mix.shell().info("conversation=#{compaction.conversation.id}")
    Mix.shell().info("level=#{compaction.level || "idle"}")
    Mix.shell().info("summary=#{compaction.summary || ""}")
  end

  defp list_conversations(args) do
    {opts, _positional, _invalid} =
      OptionParser.parse(args,
        strict: [status: :string, channel: :string, search: :string, limit: :integer]
      )

    HydraX.Runtime.list_conversations(
      limit: opts[:limit] || 25,
      status: opts[:status],
      channel: opts[:channel],
      search: opts[:search]
    )
    |> Enum.each(fn conversation ->
      delivery =
        case conversation.metadata do
          %{"last_delivery" => %{"status" => status, "channel" => channel}} ->
            "#{channel}:#{status}"

          _ ->
            "-"
        end

      Mix.shell().info(
        Enum.join(
          [
            to_string(conversation.id),
            conversation.status,
            conversation.channel,
            conversation.title || "Untitled",
            delivery,
            "attachments=#{conversation_attachment_count(conversation)}",
            "execution=#{conversation_execution_status(conversation.id)}"
          ],
          "\t"
        )
      )
    end)
  end

  defp retry_state_label(%{} = retry_state) when map_size(retry_state) > 0 do
    [
      retry_state["last_status"],
      retry_state["attempt_count"] && "attempts=#{retry_state["attempt_count"]}",
      retry_state["retry_count"] && "retries=#{retry_state["retry_count"]}",
      retry_state["result_source"] && "source=#{retry_state["result_source"]}"
    ]
    |> Enum.reject(&(&1 in [nil, "", false]))
    |> case do
      [] -> ""
      values -> "retry_state=" <> Enum.join(values, ",")
    end
  end

  defp retry_state_label(_retry_state), do: ""

  defp conversation_attachment_count(conversation) do
    if Ecto.assoc_loaded?(conversation.turns) do
      Enum.reduce(conversation.turns || [], 0, fn turn, acc ->
        metadata = turn.metadata || %{}
        attachments = metadata["attachments"] || metadata[:attachments] || []
        acc + length(attachments)
      end)
    else
      0
    end
  end

  defp conversation_execution_status(conversation_id) do
    HydraX.Runtime.conversation_channel_state(conversation_id).status || "idle"
  end

  defp handoff_label(handoff) when is_map(handoff) and handoff != %{} do
    [handoff["status"], handoff["waiting_for"], handoff["owner"]]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("/")
  end

  defp handoff_label(_handoff), do: nil

  defp pending_response_label(response) when is_map(response) and response != %{} do
    provider = get_in(response, ["metadata", "provider"]) || "provider"
    content = response["content"] || ""
    "#{provider}:#{String.slice(content, 0, 80)}"
  end

  defp pending_response_label(_response), do: nil

  defp stream_capture_label(capture) when is_map(capture) and capture != %{} do
    provider = capture["provider"] || "provider"
    chunk_count = capture["chunk_count"] || 0
    "#{provider}:chunks=#{chunk_count}"
  end

  defp stream_capture_label(_capture), do: nil

  defp stream_capture_preview(capture) when is_map(capture) and capture != %{} do
    capture["content"]
    |> to_string()
    |> String.slice(0, 120)
  end

  defp stream_capture_preview(_capture), do: nil

  defp ownership_label(%{} = ownership) when map_size(ownership) > 0 do
    [ownership["mode"], ownership["owner"], ownership["stage"]]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("/")
  end

  defp ownership_label(_ownership), do: "n/a"

  defp render_channel_response({:deferred, message}), do: message
  defp render_channel_response(message), do: message

  defp delivery_labels(delivery) do
    payload = delivery["formatted_payload"] || delivery[:formatted_payload] || %{}

    provider_message_ids =
      delivery["provider_message_ids"] || delivery[:provider_message_ids] || []

    reply_context = delivery["reply_context"] || delivery[:reply_context] || %{}

    []
    |> maybe_add_delivery_line("delivery_reason=#{delivery["reason"] || delivery[:reason]}")
    |> maybe_add_delivery_line(
      "delivery_retry_count=#{delivery["retry_count"] || delivery[:retry_count] || 0}"
    )
    |> maybe_add_delivery_line(
      "delivery_next_retry=#{format_value(delivery["next_retry_at"] || delivery[:next_retry_at])}"
    )
    |> maybe_add_delivery_line(
      "delivery_dead_lettered_at=#{format_value(delivery["dead_lettered_at"] || delivery[:dead_lettered_at])}"
    )
    |> maybe_add_delivery_line(
      "delivery_provider_message_id=#{delivery["provider_message_id"] || delivery[:provider_message_id]}"
    )
    |> maybe_add_delivery_line(
      if(provider_message_ids == [],
        do: nil,
        else: "delivery_provider_message_ids=#{length(provider_message_ids)}"
      )
    )
    |> maybe_add_delivery_line("delivery_reply_context=#{render_reply_context(reply_context)}")
    |> maybe_add_delivery_line(
      "delivery_chunk_count=#{delivery["chunk_count"] || delivery[:chunk_count] || payload["chunk_count"] || payload[:chunk_count]}"
    )
  end

  defp delivery_payload_preview(delivery) do
    case delivery["formatted_payload"] || delivery[:formatted_payload] do
      payload when is_map(payload) and map_size(payload) > 0 ->
        Jason.encode!(payload)

      _ ->
        nil
    end
  end

  defp delivery_attempt_lines(delivery) do
    (delivery["attempt_history"] || delivery[:attempt_history] || [])
    |> Enum.reverse()
    |> Enum.map(fn entry ->
      [
        "delivery_attempt",
        entry["status"] || entry[:status] || "unknown",
        "retry=#{entry["retry_count"] || entry[:retry_count] || 0}",
        entry["reason"] || entry[:reason] || "none",
        render_reply_context(entry["reply_context"] || entry[:reply_context] || %{}) || "",
        format_value(entry["recorded_at"] || entry[:recorded_at]) || ""
      ]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join("\t")
    end)
  end

  defp turn_attachment_lines(conversation) do
    Enum.flat_map(conversation.turns || [], fn turn ->
      metadata = turn.metadata || %{}
      attachments = metadata["attachments"] || metadata[:attachments] || []

      Enum.map(attachments, fn attachment ->
        "attachment\tturn=#{turn.sequence}\t#{attachment_label(attachment)}"
      end)
    end)
  end

  defp attachment_label(attachment) do
    kind = attachment["kind"] || attachment[:kind] || "attachment"
    file_name = attachment["file_name"] || attachment[:file_name]

    ref =
      attachment["download_ref"] || attachment[:download_ref] || attachment["source_url"] ||
        attachment[:source_url]

    base =
      if is_binary(file_name) and file_name != "" do
        "#{kind}:#{file_name}"
      else
        kind
      end

    case ref do
      value when is_binary(value) and value != "" -> "#{base}:#{String.slice(value, 0, 48)}"
      _ -> base
    end
  end

  defp render_reply_context(context) when is_map(context) do
    [
      context["thread_ts"] || context[:thread_ts],
      context["reply_to_message_id"] || context[:reply_to_message_id],
      context["source_message_id"] || context[:source_message_id]
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> case do
      [] -> nil
      values -> Enum.join(values, "/")
    end
  end

  defp render_reply_context(_context), do: nil

  defp format_value(nil), do: nil
  defp format_value(%DateTime{} = value), do: Calendar.strftime(value, "%Y-%m-%d %H:%M:%S UTC")
  defp format_value(value), do: to_string(value)

  defp maybe_add_delivery_line(lines, nil), do: lines
  defp maybe_add_delivery_line(lines, "delivery_reason=nil"), do: lines
  defp maybe_add_delivery_line(lines, "delivery_reply_context=nil"), do: lines
  defp maybe_add_delivery_line(lines, "delivery_chunk_count=nil"), do: lines
  defp maybe_add_delivery_line(lines, line), do: lines ++ [line]

  defp tool_result_summary(result) when is_map(result) do
    [
      result["tool_name"] || result[:tool_name] || result["name"] || result[:name] || "tool",
      result["summary"] || result[:summary] || result["status"] || result[:status] || "completed",
      if(result["cached"] || result[:cached], do: "cached", else: nil)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\t")
  end

  defp tool_result_summary(result), do: inspect(result)
end
