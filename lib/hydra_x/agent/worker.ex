defmodule HydraX.Agent.Worker do
  @moduledoc false
  @behaviour :gen_statem

  alias HydraX.Tools.{MemoryRecall, MemorySave}

  def start_link(args) do
    :gen_statem.start_link(__MODULE__, args, [])
  end

  def child_spec(args) do
    %{
      id: {__MODULE__, System.unique_integer([:positive])},
      start: {__MODULE__, :start_link, [args]},
      restart: :temporary
    }
  end

  def run(agent_id, conversation, analysis, messages) do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        HydraX.Agent.worker_supervisor(agent_id),
        {__MODULE__, %{conversation: conversation, analysis: analysis, messages: messages}}
      )

    :gen_statem.call(pid, :run, 15_000)
  end

  @impl true
  def callback_mode, do: :handle_event_function

  @impl true
  def init(args) do
    {:ok, :ready, args}
  end

  @impl true
  def handle_event(
        {:call, from},
        :run,
        :ready,
        %{conversation: conversation, analysis: analysis, messages: messages} = data
      ) do
    full_text = Enum.map_join(messages, "\n", & &1.content)

    results =
      []
      |> maybe_save_memory(analysis, conversation, full_text)
      |> maybe_recall_memory(analysis, conversation)

    {:stop_and_reply, :normal, [{:reply, from, results}], data}
  end

  def handle_event(_type, _event, _state, data), do: {:keep_state, data}

  defp maybe_save_memory(results, %{should_save_memory: false}, _conversation, _text), do: results

  defp maybe_save_memory(results, analysis, conversation, text) do
    {:ok, result} =
      MemorySave.execute(
        %{
          agent_id: conversation.agent_id,
          conversation_id: conversation.id,
          type: analysis.memory_type,
          content: String.trim(text)
        },
        %{}
      )

    [
      %{tool: MemorySave.name(), type: result.type, content: result.content, id: result.id}
      | results
    ]
  end

  defp maybe_recall_memory(results, %{should_recall_memory: false}, _conversation), do: results

  defp maybe_recall_memory(results, analysis, conversation) do
    {:ok, %{results: memories}} =
      MemoryRecall.execute(
        %{agent_id: conversation.agent_id, query: analysis.query, limit: 5},
        %{}
      )

    [%{tool: MemoryRecall.name(), results: memories} | results]
  end
end
