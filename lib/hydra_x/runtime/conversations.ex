defmodule HydraX.Runtime.Conversations do
  @moduledoc """
  Conversation, turn, and checkpoint CRUD, plus transcript export.
  """

  import Ecto.Query

  alias HydraX.Repo

  alias HydraX.Runtime.{
    AgentProfile,
    Checkpoint,
    Conversation,
    Helpers,
    Turn
  }

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

    %{
      conversation: conversation,
      turn_count: length(turns),
      level: state["level"],
      summary: state["summary"],
      updated_at: state["updated_at"],
      checkpoint_id: checkpoint && checkpoint.id,
      thresholds: thresholds
    }
  end

  def conversation_channel_state(id) when is_integer(id) do
    checkpoint = get_checkpoint(id, "channel")
    state = (checkpoint && checkpoint.state) || %{}

    %{
      checkpoint_id: checkpoint && checkpoint.id,
      status: state["status"],
      updated_at: state["updated_at"],
      plan: state["plan"] || %{},
      steps: state["steps"] || get_in(state, ["plan", "steps"]) || [],
      current_step_id: state["current_step_id"],
      current_step_index: state["current_step_index"],
      resumable: state["resumable"] || false,
      execution_events: state["execution_events"] || [],
      provider: state["provider"],
      tool_rounds: state["tool_rounds"] || 0,
      tool_results: state["tool_results"] || [],
      assistant_turn_id: state["assistant_turn_id"],
      latest_user_turn_id: state["latest_user_turn_id"]
    }
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

  defp render_transcript(conversation) do
    header = [
      "# #{conversation.title || "Untitled conversation"}",
      "",
      "- id: #{conversation.id}",
      "- channel: #{conversation.channel}",
      "- status: #{conversation.status}",
      "- updated_at: #{Calendar.strftime(conversation.updated_at, "%Y-%m-%d %H:%M UTC")}",
      ""
    ]

    turns =
      Enum.map(conversation.turns, fn turn ->
        [
          "## #{String.capitalize(turn.role)} ##{turn.sequence}",
          "",
          turn.content,
          ""
        ]
      end)

    [header | turns]
    |> List.flatten()
    |> Enum.join("\n")
  end

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
end
