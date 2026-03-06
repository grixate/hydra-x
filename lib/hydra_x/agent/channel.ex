defmodule HydraX.Agent.Channel do
  @moduledoc false
  @behaviour :gen_statem

  alias HydraX.Agent.{Branch, Compactor, PromptBuilder, Worker}
  alias HydraX.Config
  alias HydraX.LLM.Router
  alias HydraX.Runtime

  def start_link(opts) do
    conversation = Keyword.fetch!(opts, :conversation)

    :gen_statem.start_link(
      {:via, Registry, {HydraX.ProcessRegistry, {:channel, conversation.id}}},
      __MODULE__,
      opts,
      []
    )
  end

  def child_spec(opts) do
    conversation = Keyword.fetch!(opts, :conversation)

    %{
      id: {__MODULE__, conversation.id},
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient
    }
  end

  def submit(agent, conversation, content, metadata \\ %{}) do
    {:ok, _pid} = ensure_started(agent.id, conversation)
    :gen_statem.call(via_name(conversation.id), {:submit, content, metadata}, 30_000)
  end

  def ensure_started(agent_id, conversation) do
    case Registry.lookup(HydraX.ProcessRegistry, {:channel, conversation.id}) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        DynamicSupervisor.start_child(
          HydraX.Agent.channel_supervisor(agent_id),
          {__MODULE__, agent_id: agent_id, conversation: conversation}
        )
    end
  end

  def via_name(conversation_id), do: HydraX.ProcessRegistry.via({:channel, conversation_id})

  @impl true
  def callback_mode, do: :handle_event_function

  @impl true
  def init(opts) do
    conversation = Keyword.fetch!(opts, :conversation)
    agent_id = Keyword.fetch!(opts, :agent_id)
    turns = Runtime.list_turns(conversation.id)
    checkpoint = Runtime.get_checkpoint(conversation.id, "channel")
    {:ok, _pid} = Compactor.ensure_started(agent_id, conversation.id)

    data =
      %{
        agent_id: agent_id,
        conversation: conversation,
        turns: turns,
        coalesce_buffer: [],
        pending_from: [],
        last_analysis: checkpoint && checkpoint.state["analysis"]
      }

    {:ok, :ready, data}
  end

  @impl true
  def handle_event({:call, from}, {:submit, content, metadata}, state, data)
      when state in [:ready, :processing] do
    {:ok, turn} =
      Runtime.append_turn(data.conversation, %{
        role: "user",
        kind: "message",
        content: content,
        metadata: metadata
      })

    data =
      data
      |> Map.update!(:turns, &(&1 ++ [turn]))
      |> Map.update!(:coalesce_buffer, &(&1 ++ [turn]))
      |> Map.update!(:pending_from, &[from | &1])

    case state do
      :ready ->
        {:keep_state, data, [{:state_timeout, Config.coalesce_window_ms(), :flush}]}

      :processing ->
        {:keep_state, data}
    end
  end

  def handle_event(:state_timeout, :flush, :ready, data) do
    {:next_state, :processing, data, [{:next_event, :internal, :process_buffer}]}
  end

  def handle_event(:internal, :process_buffer, :processing, data) do
    history = Runtime.list_turns(data.conversation.id)
    messages = data.coalesce_buffer
    analysis = Branch.run(data.agent_id, data.conversation.id, messages)
    tool_results = Worker.run(data.agent_id, data.conversation, analysis, messages)
    agent = Runtime.get_agent!(data.agent_id)
    bulletin = HydraX.Agent.Cortex.current_bulletin(data.agent_id)
    summary = Compactor.current_summary(data.conversation.id)

    prompt =
      agent
      |> PromptBuilder.build(history, bulletin, summary, tool_results)
      |> Map.put(:analysis, analysis)

    {:ok, response} = Router.complete(prompt)

    {:ok, assistant_turn} =
      Runtime.append_turn(data.conversation, %{
        role: "assistant",
        kind: "message",
        content: response.content,
        metadata: %{
          provider: response.provider,
          analysis: analysis,
          tools: tool_results
        }
      })

    Runtime.upsert_checkpoint(data.conversation.id, "channel", %{
      "analysis" => analysis,
      "assistant_turn_id" => assistant_turn.id,
      "updated_at" => DateTime.utc_now()
    })

    Enum.each(data.pending_from, &:gen_statem.reply(&1, assistant_turn.content))
    Compactor.review(data.agent_id, data.conversation.id)

    {:next_state, :ready,
     %{
       data
       | turns: history ++ [assistant_turn],
         coalesce_buffer: [],
         pending_from: [],
         last_analysis: analysis
     }}
  end

  def handle_event(_type, _event, _state, data), do: {:keep_state, data}
end
