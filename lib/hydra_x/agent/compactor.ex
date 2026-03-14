defmodule HydraX.Agent.Compactor do
  @moduledoc false
  use GenServer

  alias HydraX.Budget
  alias HydraX.LLM.Router
  alias HydraX.Memory
  alias HydraX.Runtime

  def start_link(opts) do
    conversation_id = Keyword.fetch!(opts, :conversation_id)
    GenServer.start_link(__MODULE__, opts, name: via_name(conversation_id))
  end

  def via_name(conversation_id), do: HydraX.ProcessRegistry.via({:compactor, conversation_id})

  def ensure_started(agent_id, conversation_id) do
    case Registry.lookup(HydraX.ProcessRegistry, {:compactor, conversation_id}) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        DynamicSupervisor.start_child(
          HydraX.Agent.compactor_supervisor(agent_id),
          {__MODULE__, agent_id: agent_id, conversation_id: conversation_id}
        )
    end
  end

  def review(agent_id, conversation_id) do
    {:ok, _pid} = ensure_started(agent_id, conversation_id)
    GenServer.cast(via_name(conversation_id), :review)
  end

  def review_now(agent_id, conversation_id) do
    {:ok, _pid} = ensure_started(agent_id, conversation_id)
    GenServer.call(via_name(conversation_id), :review_now)
  end

  def current_summary(conversation_id) do
    case Runtime.get_checkpoint(conversation_id, "compactor") do
      nil -> nil
      checkpoint -> checkpoint.state["summary"]
    end
  end

  @impl true
  def init(opts), do: {:ok, %{agent_id: opts[:agent_id], conversation_id: opts[:conversation_id]}}

  @impl true
  def handle_cast(:review, state) do
    {:noreply, review_state(state)}
  end

  @impl true
  def handle_call(:review_now, _from, state) do
    next_state = review_state(state)
    {:reply, Runtime.conversation_compaction(state.conversation_id), next_state}
  end

  defp review_state(state) do
    turns = Runtime.list_turns(state.conversation_id)
    thresholds = Runtime.compaction_policy(state.agent_id)
    token_usage = token_usage(state.agent_id, turns)
    level = level_for(length(turns), thresholds, token_usage.ratio)

    if level do
      # Summarize all turns except the most recent 3 (those stay in full context)
      older_turns = Enum.take(turns, max(length(turns) - 3, 0))
      compaction = summarize_turns(older_turns, state)

      Runtime.upsert_checkpoint(state.conversation_id, "compactor", %{
        "level" => level,
        "summary" => compaction.summary,
        "summary_source" => compaction.summary_source,
        "supporting_memories" => compaction.supporting_memories,
        "updated_at" => DateTime.utc_now(),
        "estimated_tokens" => token_usage.estimated_tokens,
        "conversation_limit_tokens" => token_usage.conversation_limit_tokens,
        "token_ratio" => token_usage.ratio
      })
    end

    state
  end

  defp summarize_turns([], _state) do
    %{summary: nil, summary_source: nil, supporting_memories: []}
  end

  defp summarize_turns(turns, state) do
    transcript =
      turns
      |> Enum.map_join("\n", fn turn -> "#{turn.role}: #{turn.content}" end)

    supporting_memories = supporting_memories(state.agent_id, transcript)
    prompt = compaction_prompt(transcript, supporting_memories)

    messages = [
      %{
        role: "user",
        content: prompt
      }
    ]

    estimated_tokens = Budget.estimate_prompt_tokens(messages)

    case Budget.preflight(state.agent_id, state.conversation_id, estimated_tokens) do
      {:ok, _} ->
        case Router.complete(%{
               messages: messages,
               agent_id: state.agent_id,
               process_type: "compactor"
             }) do
          {:ok, response} ->
            output_tokens = Budget.estimate_tokens(response.content || "")

            Budget.record_usage(state.agent_id, state.conversation_id,
              tokens_in: estimated_tokens,
              tokens_out: output_tokens,
              metadata: %{provider: response.provider, purpose: "compaction"}
            )

            %{
              summary: response.content || fallback_summary(transcript),
              summary_source: "provider",
              supporting_memories: supporting_memories
            }

          {:error, _reason} ->
            %{
              summary: fallback_summary(transcript),
              summary_source: "fallback",
              supporting_memories: supporting_memories
            }
        end

      {:error, _} ->
        %{
          summary: fallback_summary(transcript),
          summary_source: "fallback",
          supporting_memories: supporting_memories
        }
    end
  end

  defp fallback_summary(transcript), do: String.slice(transcript, 0, 800)

  defp supporting_memories(agent_id, transcript) do
    agent_id
    |> Memory.search_ranked(compaction_memory_query(transcript), 4, status: "active")
    |> Enum.map(&supporting_memory_snapshot/1)
  end

  defp compaction_memory_query(transcript) do
    transcript
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, 1_200)
  end

  defp compaction_prompt(transcript, supporting_memories) do
    """
    Summarize the following conversation concisely. Preserve key facts, decisions, \
    user preferences, and any commitments made. Omit small talk and redundant exchanges. \
    Keep the summary under 600 words.

    Use the supporting memories as grounding when they reinforce decisions, preferences, \
    or durable context from the transcript. Do not invent facts that are absent from both \
    the transcript and the supporting memories.

    #{render_supporting_memories_prompt(supporting_memories)}

    Conversation transcript:
    #{transcript}
    """
    |> String.trim()
  end

  defp render_supporting_memories_prompt([]), do: "Supporting memories:\n- none"

  defp render_supporting_memories_prompt(memories) do
    supporting_lines =
      Enum.map_join(memories, "\n", fn memory ->
        [
          "#{memory.type} score=#{memory.score}",
          Enum.join(memory.reasons || [], ", "),
          render_supporting_memory_source(memory),
          render_score_breakdown(memory.score_breakdown || %{}),
          String.slice(memory.content || "", 0, 160)
        ]
        |> Enum.reject(&is_nil_or_empty/1)
        |> Enum.join(" | ")
        |> then(&("- " <> &1))
      end)

    "Supporting memories:\n" <> supporting_lines
  end

  defp render_supporting_memory_source(memory) do
    [
      memory.source_file && "file=#{memory.source_file}",
      memory.source_section && "section=#{memory.source_section}",
      memory.source_channel && "channel=#{memory.source_channel}"
    ]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      values -> Enum.join(values, " ")
    end
  end

  defp render_score_breakdown(score_breakdown) when map_size(score_breakdown) == 0, do: nil

  defp render_score_breakdown(score_breakdown) do
    score_breakdown
    |> Enum.reject(fn {_key, value} -> value in [nil, 0.0] end)
    |> Enum.sort_by(fn {_key, value} -> -value end)
    |> Enum.map_join(", ", fn {key, value} -> "#{key}=#{value}" end)
    |> case do
      "" -> nil
      value -> "breakdown=#{value}"
    end
  end

  defp supporting_memory_snapshot(ranked) do
    memory = ranked.entry
    metadata = memory.metadata || %{}

    %{
      id: memory.id,
      type: memory.type,
      status: memory.status,
      content: memory.content,
      importance: memory.importance,
      score: ranked.score,
      reasons: ranked.reasons || [],
      score_breakdown: ranked.score_breakdown || %{},
      source_file: metadata["source_file"],
      source_section: metadata["source_section"],
      source_channel: metadata["source_channel"]
    }
  end

  defp level_for(count, thresholds, ratio) when count >= thresholds.hard or ratio >= 0.95,
    do: "hard"

  defp level_for(count, thresholds, ratio) when count >= thresholds.medium or ratio >= 0.9,
    do: "medium"

  defp level_for(count, thresholds, ratio) when count >= thresholds.soft or ratio >= 0.8,
    do: "soft"

  defp level_for(_, _, _), do: nil

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

  defp is_nil_or_empty(nil), do: true
  defp is_nil_or_empty(""), do: true
  defp is_nil_or_empty(_value), do: false
end
