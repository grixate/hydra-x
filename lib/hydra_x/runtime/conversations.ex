defmodule HydraX.Runtime.Conversations do
  @moduledoc """
  Conversation, turn, and checkpoint CRUD, plus transcript export.
  """

  import Ecto.Query

  alias HydraX.Budget
  alias HydraX.Repo

  alias HydraX.Runtime.{
    AgentProfile,
    Checkpoint,
    Conversation,
    Helpers,
    Turn
  }

  @resumable_checkpoint_statuses ~w(deferred planned executing_tools streaming interrupted)
  @stale_resume_statuses ~w(planned executing_tools streaming)
  @stale_resume_after_seconds 30

  def list_conversations(opts \\ []) do
    agent_id = Keyword.get(opts, :agent_id)
    status = Keyword.get(opts, :status)
    channel = Keyword.get(opts, :channel)
    search = Keyword.get(opts, :search)
    limit = Keyword.get(opts, :limit, 25)
    offset = Keyword.get(opts, :offset, 0)

    Conversation
    |> preload([:agent])
    |> maybe_filter_agent(agent_id)
    |> maybe_filter_conversation_status(status)
    |> maybe_filter_conversation_channel(channel)
    |> maybe_filter_conversation_search(search)
    |> order_by([conversation], desc: conversation.updated_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  def get_conversation!(id) do
    Conversation
    |> Repo.get!(id)
    |> Repo.preload([:agent, turns: from(turn in Turn, order_by: turn.sequence)])
  end

  def find_conversation(agent_id, channel, external_ref) do
    Repo.get_by(Conversation, agent_id: agent_id, channel: channel, external_ref: external_ref)
  end

  def start_conversation(%AgentProfile{} = agent, attrs \\ %{}) do
    attrs = Helpers.normalize_string_keys(attrs)

    params = %{
      agent_id: agent.id,
      channel: Map.get(attrs, "channel", "cli"),
      status: Map.get(attrs, "status", "active"),
      title: Map.get(attrs, "title", agent.name),
      external_ref: Map.get(attrs, "external_ref"),
      metadata: Map.get(attrs, "metadata", %{}),
      last_message_at: DateTime.utc_now()
    }

    %Conversation{}
    |> Conversation.changeset(params)
    |> Repo.insert()
  end

  def save_conversation(%Conversation{} = conversation, attrs) do
    conversation
    |> Conversation.changeset(Helpers.normalize_string_keys(attrs))
    |> Repo.update()
  end

  def archive_conversation!(id) do
    conversation = get_conversation!(id)
    {:ok, updated} = save_conversation(conversation, %{status: "archived"})

    Helpers.audit_operator_action("Archived conversation #{updated.id}",
      agent_id: updated.agent_id,
      conversation_id: updated.id
    )

    updated
  end

  def conversation_compaction(id) when is_integer(id) do
    conversation = get_conversation!(id)
    checkpoint = get_checkpoint(conversation.id, "compactor")
    state = (checkpoint && checkpoint.state) || %{}
    turns = list_turns(conversation.id)
    thresholds = HydraX.Runtime.Agents.compaction_policy(conversation.agent_id)
    token_usage = token_usage(conversation.agent_id, turns)

    %{
      conversation: conversation,
      turn_count: length(turns),
      level: state["level"],
      summary: state["summary"],
      updated_at: state["updated_at"],
      checkpoint_id: checkpoint && checkpoint.id,
      thresholds: thresholds,
      estimated_tokens: state["estimated_tokens"] || token_usage.estimated_tokens,
      conversation_limit_tokens:
        state["conversation_limit_tokens"] || token_usage.conversation_limit_tokens,
      token_ratio: state["token_ratio"] || token_usage.ratio
    }
  end

  def conversation_channel_state(id) when is_integer(id) do
    checkpoint = get_checkpoint(id, "channel")
    state = (checkpoint && checkpoint.state) || %{}
    conversation = Repo.get(Conversation, id)
    resume_stage = resumable_checkpoint_stage(state)

    ownership =
      state["ownership"] || get_in((conversation && conversation.metadata) || %{}, ["ownership"]) ||
        %{}

    %{
      checkpoint_id: checkpoint && checkpoint.id,
      status: state["status"],
      updated_at: state["updated_at"],
      ownership: ownership,
      plan: state["plan"] || %{},
      steps: state["steps"] || get_in(state, ["plan", "steps"]) || [],
      current_step_id: state["current_step_id"],
      current_step_index: state["current_step_index"],
      resumable: state["resumable"] || false,
      resume_stage: resume_stage,
      stale_stream: resume_stage == "streaming" and stale_resume_checkpoint?(state),
      execution_events: state["execution_events"] || [],
      handoff: state["handoff"],
      recovery_lineage: state["recovery_lineage"] || %{},
      provider: state["provider"],
      tool_rounds: state["tool_rounds"] || 0,
      tool_results: state["tool_results"] || [],
      tool_cache: state["tool_cache"] || [],
      tool_cache_scope_turn_id: state["tool_cache_scope_turn_id"],
      active_tool_calls: state["active_tool_calls"] || [],
      assistant_turn_id: state["assistant_turn_id"],
      pending_turn_id: state["pending_turn_id"],
      pending_response: state["pending_response"],
      stream_capture: state["stream_capture"],
      latest_user_turn_id: state["latest_user_turn_id"]
    }
  end

  def list_owned_resumable_conversations(opts \\ []) do
    owner = Keyword.get(opts, :owner, HydraX.Runtime.coordination_status().owner)
    limit = Keyword.get(opts, :limit, 50)

    Checkpoint
    |> where([checkpoint], checkpoint.process_type == "channel")
    |> join(:inner, [checkpoint], conversation in assoc(checkpoint, :conversation))
    |> where([_checkpoint, conversation], conversation.status == "active")
    |> preload([_checkpoint, conversation], conversation: [:agent])
    |> order_by([checkpoint, _conversation], desc: checkpoint.updated_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.reduce([], fn checkpoint, acc ->
      case claim_resumable_conversation(checkpoint, owner) do
        {:ok, conversation} -> [conversation | acc]
        _ -> acc
      end
    end)
    |> Enum.reverse()
  end

  def resume_owned_conversations(opts \\ []) do
    owner = Keyword.get(opts, :owner, HydraX.Runtime.coordination_status().owner)
    limit = Keyword.get(opts, :limit, 50)

    results =
      list_owned_resumable_conversations(owner: owner, limit: limit)
      |> Enum.map(&resume_owned_conversation/1)

    %{
      owner: owner,
      resumed_count: Enum.count(results, &(&1.status == "resumed")),
      skipped_count: Enum.count(results, &(&1.status == "skipped")),
      error_count: Enum.count(results, &(&1.status == "error")),
      results: results
    }
  end

  def list_owned_pending_deliveries(opts \\ []) do
    owner = Keyword.get(opts, :owner, HydraX.Runtime.coordination_status().owner)
    limit = Keyword.get(opts, :limit, 50)
    turns_query = from(turn in Turn, order_by: turn.sequence)

    Conversation
    |> where([conversation], conversation.status == "active")
    |> preload([:agent, turns: ^turns_query])
    |> order_by([conversation], desc: conversation.updated_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.reduce([], fn conversation, acc ->
      case claim_delivery_conversation(conversation, owner) do
        {:ok, refreshed} -> [refreshed | acc]
        _ -> acc
      end
    end)
    |> Enum.reverse()
  end

  def list_owned_pending_ingress_conversations(opts \\ []) do
    owner = Keyword.get(opts, :owner, HydraX.Runtime.coordination_status().owner)
    limit = Keyword.get(opts, :limit, 50)

    Checkpoint
    |> where([checkpoint], checkpoint.process_type == "ingress")
    |> join(:inner, [checkpoint], conversation in assoc(checkpoint, :conversation))
    |> where([_checkpoint, conversation], conversation.status == "active")
    |> preload([_checkpoint, conversation], conversation: [:agent])
    |> order_by([checkpoint, _conversation], desc: checkpoint.updated_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.reduce([], fn checkpoint, acc ->
      case claim_ingress_conversation(checkpoint, owner) do
        {:ok, conversation} -> [conversation | acc]
        _ -> acc
      end
    end)
    |> Enum.reverse()
  end

  def review_conversation_compaction!(id) when is_integer(id) do
    conversation = get_conversation!(id)

    {:ok, _pid} =
      HydraX.Agent.ensure_started(
        conversation.agent || HydraX.Runtime.Agents.get_agent!(conversation.agent_id)
      )

    compaction = HydraX.Agent.Compactor.review_now(conversation.agent_id, conversation.id)

    Helpers.audit_operator_action(
      "Reviewed compaction for conversation #{conversation.id}",
      agent_id: conversation.agent_id,
      conversation_id: conversation.id,
      metadata: %{"level" => compaction.level, "turn_count" => compaction.turn_count}
    )

    compaction
  end

  def reset_conversation_compaction!(id) when is_integer(id) do
    conversation = get_conversation!(id)

    from(checkpoint in Checkpoint,
      where:
        checkpoint.conversation_id == ^conversation.id and checkpoint.process_type == "compactor"
    )
    |> Repo.delete_all()

    Helpers.audit_operator_action(
      "Reset compaction for conversation #{conversation.id}",
      agent_id: conversation.agent_id,
      conversation_id: conversation.id
    )

    conversation_compaction(conversation.id)
  end

  def export_conversation_transcript!(id) do
    conversation = get_conversation!(id)
    agent = conversation.agent || HydraX.Runtime.Agents.get_agent!(conversation.agent_id)
    path = transcript_path(agent, conversation)

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, render_transcript(conversation))

    Helpers.audit_operator_action(
      "Exported transcript for conversation #{conversation.id}",
      agent: agent,
      conversation_id: conversation.id,
      metadata: %{"path" => path}
    )

    %{conversation: conversation, agent: agent, path: path}
  end

  def list_turns(conversation_id) do
    Turn
    |> where([turn], turn.conversation_id == ^conversation_id)
    |> order_by([turn], asc: turn.sequence)
    |> Repo.all()
  end

  def append_turn(%Conversation{} = conversation, attrs) do
    sequence =
      Repo.one(
        from(turn in Turn,
          where: turn.conversation_id == ^conversation.id,
          select: coalesce(max(turn.sequence), 0)
        )
      ) + 1

    params =
      attrs
      |> Helpers.normalize_string_keys()
      |> Map.merge(%{
        "conversation_id" => conversation.id,
        "sequence" => sequence,
        "metadata" => Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
      })

    Repo.transaction(fn ->
      turn =
        %Turn{}
        |> Turn.changeset(params)
        |> Repo.insert!()

      conversation
      |> Conversation.changeset(%{last_message_at: DateTime.utc_now()})
      |> Repo.update!()

      turn
    end)
    |> Helpers.unwrap_transaction()
  end

  def get_checkpoint(conversation_id, process_type) do
    Repo.get_by(Checkpoint, conversation_id: conversation_id, process_type: process_type)
  end

  def upsert_checkpoint(conversation_id, process_type, state) when is_map(state) do
    checkpoint = get_checkpoint(conversation_id, process_type) || %Checkpoint{}

    checkpoint
    |> Checkpoint.changeset(%{
      conversation_id: conversation_id,
      process_type: process_type,
      state: state
    })
    |> Repo.insert_or_update()
  end

  def update_conversation_metadata(%Conversation{} = conversation, attrs) when is_map(attrs) do
    metadata = Map.merge(conversation.metadata || %{}, attrs)

    conversation
    |> Conversation.changeset(%{metadata: metadata})
    |> Repo.update()
  end

  # -- Private helpers --

  defp transcript_path(agent, conversation) do
    safe_title =
      (conversation.title || "conversation")
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, "-")
      |> String.trim("-")
      |> case do
        "" -> "conversation"
        value -> value
      end

    Path.join([
      agent.workspace_root,
      "transcripts",
      "#{conversation.id}-#{safe_title}.md"
    ])
  end

  defp token_usage(agent_id, turns) do
    estimated_tokens =
      turns
      |> Enum.map(&%{role: &1.role, content: &1.content})
      |> Budget.estimate_prompt_tokens()

    policy = Budget.ensure_policy!(agent_id)
    limit = max(policy.conversation_limit || 0, 1)

    %{
      estimated_tokens: estimated_tokens,
      conversation_limit_tokens: limit,
      ratio: Float.round(estimated_tokens / limit, 4)
    }
  end

  defp render_transcript(conversation) do
    channel_state = conversation_channel_state(conversation.id)
    delivery = last_delivery(conversation)
    attachment_count = transcript_attachment_count(conversation.turns)

    header = [
      "# #{conversation.title || "Untitled conversation"}",
      "",
      "- id: #{conversation.id}",
      "- channel: #{conversation.channel}",
      "- status: #{conversation.status}",
      maybe_transcript_detail("- external_ref", conversation.external_ref),
      maybe_transcript_detail("- attachments", attachment_count),
      "- updated_at: #{Calendar.strftime(conversation.updated_at, "%Y-%m-%d %H:%M UTC")}",
      ""
    ]

    delivery_section = render_transcript_delivery(delivery)

    execution =
      case channel_state.status do
        nil ->
          []

        _ ->
          [
            "## Execution checkpoint",
            "",
            "- status: #{channel_state.status}",
            maybe_transcript_detail("- owner", render_ownership_line(channel_state.ownership)),
            "- provider: #{channel_state.provider || "n/a"}",
            "- tool_rounds: #{channel_state.tool_rounds || 0}",
            "- resumable: #{if(channel_state.resumable, do: "yes", else: "no")}",
            maybe_transcript_detail("- handoff", render_handoff_line(channel_state.handoff)),
            maybe_transcript_detail(
              "- pending_response",
              render_pending_response_line(channel_state.pending_response)
            ),
            maybe_transcript_detail(
              "- stream_capture",
              render_stream_capture_line(channel_state.stream_capture)
            ),
            maybe_transcript_detail(
              "- recovery",
              render_recovery_lineage(channel_state.recovery_lineage)
            ),
            maybe_transcript_detail(
              "- tool_cache_scope_turn_id",
              channel_state.tool_cache_scope_turn_id
            ),
            ""
          ] ++
            render_transcript_pending_response(channel_state.pending_response) ++
            render_transcript_stream_capture(channel_state.stream_capture) ++
            render_transcript_steps(channel_state.steps) ++
            render_transcript_events(channel_state.execution_events)
      end

    turns =
      Enum.map(conversation.turns, fn turn ->
        [
          "## #{String.capitalize(turn.role)} ##{turn.sequence}",
          "",
          turn.content,
          ""
        ] ++
          render_turn_attachments(turn) ++
          [
            ""
          ]
      end)

    [header, delivery_section, execution | turns]
    |> List.flatten()
    |> Enum.join("\n")
  end

  defp render_transcript_steps([]), do: []

  defp render_transcript_steps(steps) do
    [
      "### Steps",
      ""
    ] ++
      Enum.flat_map(steps, fn step ->
        [
          "- [#{step["status"] || "pending"}] #{step["kind"] || "step"} #{step["name"] || step["label"] || step["id"]}",
          maybe_transcript_detail("  summary", step["summary"]),
          maybe_transcript_detail("  reason", step["reason"] || step["label"]),
          maybe_transcript_detail("  output", step["output_excerpt"]),
          maybe_transcript_detail("  owner", step["owner"] || step["executor"]),
          maybe_transcript_detail("  lifecycle", step["lifecycle"]),
          maybe_transcript_detail("  result_source", step["result_source"]),
          maybe_transcript_detail("  replay_strategy", step["replay_strategy"]),
          maybe_transcript_detail("  replay_count", step["replay_count"]),
          maybe_transcript_detail("  idempotency_key", step["idempotency_key"]),
          maybe_transcript_detail("  cached", if(step["cached"], do: "yes", else: nil)),
          maybe_transcript_detail("  safety", step["safety_classification"]),
          maybe_transcript_detail(
            "  started",
            format_transcript_datetime(step["last_started_at"] || step["started_at"])
          ),
          maybe_transcript_detail(
            "  completed",
            format_transcript_datetime(step["completed_at"])
          ),
          maybe_transcript_detail("  failed", format_transcript_datetime(step["failed_at"])),
          maybe_transcript_detail("  updated", format_transcript_datetime(step["updated_at"])),
          ""
        ]
      end)
  end

  defp render_ownership_line(%{} = ownership) when map_size(ownership) > 0 do
    [
      ownership["mode"],
      ownership["owner"],
      ownership["stage"],
      ownership["contended"] && "contended"
    ]
    |> Enum.reject(&is_nil_or_empty/1)
    |> Enum.join(" · ")
  end

  defp render_ownership_line(_ownership), do: nil

  defp render_handoff_line(%{} = handoff) when map_size(handoff) > 0 do
    [handoff["status"], handoff["waiting_for"], handoff["owner"]]
    |> Enum.reject(&is_nil_or_empty/1)
    |> Enum.join(" · ")
  end

  defp render_handoff_line(_handoff), do: nil

  defp render_pending_response_line(%{} = response) when map_size(response) > 0 do
    provider = get_in(response, ["metadata", "provider"]) || "provider"
    content = response["content"] || ""
    "#{provider} · #{String.slice(content, 0, 120)}"
  end

  defp render_pending_response_line(_response), do: nil

  defp render_stream_capture_line(%{} = capture) when map_size(capture) > 0 do
    [
      capture["provider"],
      capture["chunk_count"] && "chunks #{capture["chunk_count"]}",
      capture["captured_at"] && format_transcript_datetime(capture["captured_at"])
    ]
    |> Enum.reject(&is_nil_or_empty/1)
    |> Enum.join(" · ")
  end

  defp render_stream_capture_line(_capture), do: nil

  defp render_transcript_pending_response(response) when response in [nil, %{}], do: []

  defp render_transcript_pending_response(response) when is_map(response) do
    [
      "### Pending response snapshot",
      "",
      maybe_transcript_detail("  provider", get_in(response, ["metadata", "provider"])),
      maybe_transcript_detail("  content", response["content"]),
      ""
    ]
  end

  defp render_transcript_stream_capture(capture) when capture in [nil, %{}], do: []

  defp render_transcript_stream_capture(capture) when is_map(capture) do
    [
      "### Partial stream capture",
      "",
      maybe_transcript_detail("  provider", capture["provider"]),
      maybe_transcript_detail("  chunk_count", capture["chunk_count"]),
      maybe_transcript_detail(
        "  captured_at",
        format_transcript_datetime(capture["captured_at"])
      ),
      maybe_transcript_detail("  content", capture["content"]),
      ""
    ]
  end

  defp render_transcript_events([]), do: []

  defp render_transcript_events(events) do
    recent = Enum.take(events, -8)

    [
      "### Recent execution events",
      ""
    ] ++
      Enum.flat_map(recent, fn event ->
        details = event["details"] || %{}

        [
          "- #{event["phase"]} @ #{format_transcript_datetime(event["at"])}",
          maybe_transcript_detail("  summary", details["summary"]),
          maybe_transcript_detail("  tool", details["tool_name"]),
          maybe_transcript_detail("  provider", details["provider"]),
          maybe_transcript_detail("  round", details["round"]),
          maybe_transcript_detail("  waiting_for", details["waiting_for"]),
          maybe_transcript_detail("  cache_hits", details["cache_hits"]),
          maybe_transcript_detail("  cache_misses", details["cache_misses"]),
          maybe_transcript_detail("  captured_chars", details["captured_chars"]),
          maybe_transcript_detail("  captured_chunks", details["captured_chunks"]),
          ""
        ]
      end)
  end

  defp render_transcript_delivery(delivery) when delivery == %{}, do: []
  defp render_transcript_delivery(nil), do: []

  defp render_transcript_delivery(delivery) when is_map(delivery) do
    payload = delivery["formatted_payload"] || delivery[:formatted_payload] || %{}

    provider_message_ids =
      delivery["provider_message_ids"] || delivery[:provider_message_ids] || []

    [
      "## Delivery state",
      "",
      maybe_transcript_detail("- channel", delivery["channel"] || delivery[:channel]),
      maybe_transcript_detail("- status", delivery["status"] || delivery[:status]),
      maybe_transcript_detail(
        "- external_ref",
        delivery["external_ref"] || delivery[:external_ref]
      ),
      maybe_transcript_detail(
        "- provider_message_id",
        delivery["provider_message_id"] || delivery[:provider_message_id]
      ),
      maybe_transcript_detail(
        "- provider_message_ids",
        if(provider_message_ids == [], do: nil, else: length(provider_message_ids))
      ),
      maybe_transcript_detail("- retry_count", delivery["retry_count"] || delivery[:retry_count]),
      maybe_transcript_detail("- reason", delivery["reason"] || delivery[:reason]),
      maybe_transcript_detail(
        "- next_retry_at",
        format_transcript_datetime(delivery["next_retry_at"] || delivery[:next_retry_at])
      ),
      maybe_transcript_detail(
        "- dead_lettered_at",
        format_transcript_datetime(delivery["dead_lettered_at"] || delivery[:dead_lettered_at])
      ),
      maybe_transcript_detail(
        "- reply_context",
        render_reply_context(delivery["reply_context"] || delivery[:reply_context] || %{})
      ),
      maybe_transcript_detail(
        "- chunk_count",
        delivery["chunk_count"] || delivery[:chunk_count] || payload["chunk_count"] ||
          payload[:chunk_count]
      ),
      ""
    ] ++
      render_transcript_attempts(delivery["attempt_history"] || delivery[:attempt_history] || []) ++
      render_transcript_payload(payload)
  end

  defp render_transcript_attempts([]), do: []

  defp render_transcript_attempts(history) do
    [
      "### Delivery attempts",
      ""
    ] ++
      Enum.flat_map(Enum.reverse(history), fn entry ->
        provider_message_ids = entry["provider_message_ids"] || entry[:provider_message_ids] || []

        [
          "- #{entry["status"] || entry[:status] || "unknown"}",
          maybe_transcript_detail("  retry_count", entry["retry_count"] || entry[:retry_count]),
          maybe_transcript_detail("  reason", entry["reason"] || entry[:reason]),
          maybe_transcript_detail(
            "  recorded_at",
            format_transcript_datetime(entry["recorded_at"] || entry[:recorded_at])
          ),
          maybe_transcript_detail(
            "  provider_message_ids",
            if(provider_message_ids == [], do: nil, else: length(provider_message_ids))
          ),
          maybe_transcript_detail(
            "  reply_context",
            render_reply_context(entry["reply_context"] || entry[:reply_context] || %{})
          ),
          maybe_transcript_detail("  chunk_count", entry["chunk_count"] || entry[:chunk_count]),
          ""
        ]
      end)
  end

  defp render_transcript_payload(payload) when payload == %{}, do: []

  defp render_transcript_payload(payload) when is_map(payload) do
    [
      "### Native payload preview",
      "",
      "```json",
      Jason.encode!(payload, pretty: true),
      "```",
      ""
    ]
  end

  defp render_turn_attachments(turn) do
    case turn_attachments(turn) do
      [] ->
        []

      attachments ->
        [
          "### Attachments",
          ""
        ] ++
          Enum.flat_map(attachments, fn attachment ->
            [
              "- #{attachment_label(attachment)}",
              ""
            ]
          end)
    end
  end

  defp maybe_transcript_detail(_label, nil), do: nil
  defp maybe_transcript_detail(_label, ""), do: nil
  defp maybe_transcript_detail(label, value), do: "#{label}: #{value}"

  defp render_recovery_lineage(lineage) when lineage == %{}, do: nil

  defp render_recovery_lineage(lineage) when is_map(lineage) do
    [
      "turn #{lineage["turn_scope_id"] || "n/a"}",
      "recoveries #{lineage["recovery_count"] || 0}",
      "cache hits #{lineage["cache_hits"] || 0}",
      "cache misses #{lineage["cache_misses"] || 0}"
    ]
    |> Enum.join("; ")
  end

  defp render_recovery_lineage(_lineage), do: nil

  defp format_transcript_datetime(nil), do: nil

  defp format_transcript_datetime(%DateTime{} = value),
    do: Calendar.strftime(value, "%Y-%m-%d %H:%M:%S UTC")

  defp format_transcript_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")
      _ -> value
    end
  end

  defp last_delivery(conversation) do
    metadata = conversation.metadata || %{}
    metadata["last_delivery"] || metadata[:last_delivery] || %{}
  end

  defp transcript_attachment_count(turns) do
    Enum.reduce(turns, 0, fn turn, acc -> acc + length(turn_attachments(turn)) end)
  end

  defp turn_attachments(turn) do
    metadata = turn.metadata || %{}
    metadata["attachments"] || metadata[:attachments] || []
  end

  defp attachment_label(attachment) do
    kind = attachment["kind"] || attachment[:kind] || "attachment"
    file_name = attachment["file_name"] || attachment[:file_name]

    ref =
      attachment["download_ref"] || attachment[:download_ref] || attachment["source_url"] ||
        attachment[:source_url]

    base =
      if is_binary(file_name) and file_name != "" do
        "#{kind}: #{file_name}"
      else
        kind
      end

    case ref do
      value when is_binary(value) and value != "" -> "#{base} · #{String.slice(value, 0, 64)}"
      _ -> base
    end
  end

  defp render_reply_context(context) when is_map(context) do
    [
      context["thread_ts"] || context[:thread_ts],
      context["reply_to_message_id"] || context[:reply_to_message_id],
      context["source_message_id"] || context[:source_message_id]
    ]
    |> Enum.reject(&is_nil_or_empty/1)
    |> case do
      [] -> nil
      values -> Enum.join(values, "/")
    end
  end

  defp render_reply_context(_context), do: nil

  defp is_nil_or_empty(nil), do: true
  defp is_nil_or_empty(""), do: true
  defp is_nil_or_empty(_value), do: false

  defp maybe_filter_agent(query, nil), do: query

  defp maybe_filter_agent(query, agent_id),
    do: where(query, [conversation], conversation.agent_id == ^agent_id)

  defp maybe_filter_conversation_status(query, nil), do: query
  defp maybe_filter_conversation_status(query, ""), do: query

  defp maybe_filter_conversation_status(query, status),
    do: where(query, [conversation], conversation.status == ^status)

  defp maybe_filter_conversation_channel(query, nil), do: query
  defp maybe_filter_conversation_channel(query, ""), do: query

  defp maybe_filter_conversation_channel(query, channel),
    do: where(query, [conversation], conversation.channel == ^channel)

  defp maybe_filter_conversation_search(query, nil), do: query
  defp maybe_filter_conversation_search(query, ""), do: query

  defp maybe_filter_conversation_search(query, search) do
    pattern = "%#{search}%"

    where(
      query,
      [conversation],
      like(conversation.title, ^pattern) or like(conversation.external_ref, ^pattern)
    )
  end

  defp resume_owned_conversation(conversation) do
    agent = conversation.agent || HydraX.Runtime.Agents.get_agent!(conversation.agent_id)
    state = conversation_channel_state(conversation.id)

    with {:ok, _agent_pid} <- HydraX.Agent.ensure_started(agent),
         {:ok, _channel_pid} <- HydraX.Agent.Channel.ensure_started(agent.id, conversation) do
      %{
        conversation_id: conversation.id,
        agent_id: conversation.agent_id,
        status: "resumed",
        resume_from: state.resume_stage
      }
    else
      {:error, {:owned_elsewhere, ownership}} ->
        %{
          conversation_id: conversation.id,
          agent_id: conversation.agent_id,
          status: "skipped",
          reason: "owned_elsewhere",
          owner: ownership["owner"]
        }

      {:error, reason} ->
        %{
          conversation_id: conversation.id,
          agent_id: conversation.agent_id,
          status: "error",
          reason: inspect(reason),
          resume_from: state.resume_stage
        }
    end
  end

  defp claim_resumable_conversation(%Checkpoint{} = checkpoint, owner) do
    state = checkpoint.state || %{}
    resume_stage = resumable_checkpoint_stage(state)

    cond do
      is_nil(resume_stage) ->
        :skip

      state["resumable"] != true ->
        :skip

      not is_nil(state["assistant_turn_id"]) ->
        :skip

      HydraX.Agent.Channel.active?(checkpoint.conversation.id) ->
        :skip

      resume_stage in @stale_resume_statuses and not stale_resume_checkpoint?(state) ->
        :skip

      true ->
        claim_conversation_processing_ownership(
          checkpoint.conversation,
          state,
          owner,
          resume_stage
        )
    end
  end

  defp resumable_checkpoint_stage(state) when is_map(state) do
    status = state["status"]

    if status in @resumable_checkpoint_statuses and is_nil(state["assistant_turn_id"]) do
      status
    end
  end

  defp resumable_checkpoint_stage(_state), do: nil

  defp stale_resume_checkpoint?(state) when is_map(state) do
    status = state["status"]

    status in @stale_resume_statuses and
      case normalize_datetime(state["updated_at"]) do
        nil ->
          true

        updated_at ->
          DateTime.diff(DateTime.utc_now(), updated_at, :second) >= @stale_resume_after_seconds
      end
  end

  defp stale_resume_checkpoint?(_state), do: false

  defp normalize_datetime(%DateTime{} = value), do: value

  defp normalize_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  defp normalize_datetime(_value), do: nil

  defp claim_delivery_conversation(conversation, owner) do
    delivery = last_delivery(conversation)

    cond do
      not is_map(delivery) ->
        :skip

      delivery["status"] != "deferred" ->
        :skip

      not (is_binary(delivery["external_ref"]) and delivery["external_ref"] != "") ->
        :skip

      not Enum.any?(conversation.turns || [], &(&1.role == "assistant")) ->
        :skip

      true ->
        claim_conversation_processing_ownership(
          conversation,
          get_in(conversation.metadata || %{}, ["ownership"]) || %{},
          owner,
          "delivering"
        )
    end
  end

  defp claim_ingress_conversation(%Checkpoint{} = checkpoint, owner) do
    state = checkpoint.state || %{}

    cond do
      state["status"] != "queued" ->
        :skip

      Enum.empty?(state["messages"] || []) ->
        :skip

      true ->
        claim_ingress_processing_ownership(checkpoint.conversation, checkpoint, owner)
    end
  end

  defp claim_conversation_processing_ownership(conversation, ownership_state, owner, stage) do
    case HydraX.Runtime.claim_lease(
           conversation_lease_name(conversation.id),
           owner: owner,
           ttl_seconds: conversation_lease_ttl_seconds(),
           metadata: %{
             "type" => "conversation",
             "conversation_id" => conversation.id,
             "stage" => stage
           }
         ) do
      {:ok, lease} ->
        ownership =
          conversation_ownership_payload(lease, stage, true)
          |> maybe_put_reassigned_at(ownership_state)

        {:ok, persist_conversation_ownership(conversation, ownership)}

      {:error, {:taken, lease}} ->
        ownership =
          conversation_ownership_payload(lease, stage, false)
          |> maybe_put_reassigned_at(ownership_state)

        _ = persist_conversation_ownership(conversation, ownership)
        :skip

      {:error, _reason} ->
        :skip
    end
  end

  defp claim_ingress_processing_ownership(conversation, checkpoint, owner) do
    state = checkpoint.state || %{}
    channel = state["channel"] || conversation.channel
    external_ref = state["external_ref"] || conversation.external_ref

    case HydraX.Runtime.claim_lease(
           ingress_lease_name(channel, external_ref),
           owner: owner,
           ttl_seconds: ingress_lease_ttl_seconds(),
           metadata: %{
             "type" => "ingress",
             "channel" => channel,
             "external_ref" => external_ref
           }
         ) do
      {:ok, lease} ->
        _ =
          persist_ingress_checkpoint_owner(
            conversation.id,
            checkpoint,
            ingress_owner_payload(lease, state, true)
          )

        {:ok, conversation}

      {:error, {:taken, lease}} ->
        _ =
          persist_ingress_checkpoint_owner(
            conversation.id,
            checkpoint,
            ingress_owner_payload(lease, state, false)
          )

        :skip

      {:error, _reason} ->
        :skip
    end
  end

  defp persist_conversation_ownership(conversation, ownership) do
    _ = update_conversation_metadata(conversation, %{"ownership" => ownership})
    _ = persist_conversation_checkpoint_ownership(conversation.id, ownership)
    %{conversation | metadata: Map.put(conversation.metadata || %{}, "ownership", ownership)}
  end

  defp persist_ingress_checkpoint_owner(conversation_id, checkpoint, owner_payload) do
    state = (checkpoint && checkpoint.state) || %{}

    upsert_checkpoint(
      conversation_id,
      "ingress",
      Map.merge(state, owner_payload)
    )
  end

  defp persist_conversation_checkpoint_ownership(conversation_id, ownership) do
    case get_checkpoint(conversation_id, "channel") do
      nil ->
        :ok

      checkpoint ->
        state = checkpoint.state || %{}

        upsert_checkpoint(
          conversation_id,
          "channel",
          Map.put(state, "ownership", ownership)
        )
    end
  end

  defp conversation_ownership_payload(lease, stage, active?) do
    %{
      "mode" => "database_lease",
      "lease_name" => lease.name,
      "owner" => lease.owner,
      "owner_node" => lease.owner_node,
      "expires_at" => lease.expires_at,
      "active" => active?,
      "contended" => not active?,
      "stage" => stage,
      "updated_at" => DateTime.utc_now()
    }
  end

  defp ingress_owner_payload(lease, previous_state, active?) do
    %{
      "status" => previous_state["status"] || "queued",
      "channel" => previous_state["channel"],
      "external_ref" => previous_state["external_ref"],
      "owner" => lease.owner,
      "owner_node" => lease.owner_node,
      "lease_name" => lease.name,
      "expires_at" => lease.expires_at,
      "active" => active?,
      "contended" => not active?,
      "updated_at" => DateTime.utc_now()
    }
    |> maybe_put_reassigned_at(previous_state)
  end

  defp maybe_put_reassigned_at(payload, previous) do
    previous_owner =
      previous["owner"] || get_in(previous, ["ownership", "owner"])

    if is_binary(previous_owner) and previous_owner != payload["owner"] do
      Map.put(payload, "reassigned_at", DateTime.utc_now())
    else
      payload
    end
  end

  defp conversation_lease_name(conversation_id), do: "conversation:#{conversation_id}"
  defp ingress_lease_name(channel, external_ref), do: "ingress:#{channel}:#{external_ref}"
  defp conversation_lease_ttl_seconds, do: 3_600
  defp ingress_lease_ttl_seconds, do: 3_600
end
