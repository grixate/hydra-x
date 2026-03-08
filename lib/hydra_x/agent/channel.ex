defmodule HydraX.Agent.Channel do
  @moduledoc false
  @behaviour :gen_statem

  alias HydraX.Agent.{Compactor, PromptBuilder, Worker}
  alias HydraX.Budget
  alias HydraX.Cluster
  alias HydraX.Config
  alias HydraX.LLM.Router
  alias HydraX.Runtime
  alias HydraX.Safety
  alias HydraX.Telemetry

  @max_tool_rounds 5
  @streamable_channels ~w(control_plane cli)

  def start_link(opts) do
    conversation = Keyword.fetch!(opts, :conversation)

    :gen_statem.start_link(
      channel_name(conversation.id),
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
    :gen_statem.call(channel_name(conversation.id), {:submit, content, metadata}, 30_000)
  end

  def ensure_started(agent_id, conversation) do
    case channel_lookup(conversation.id) do
      {:ok, pid} ->
        {:ok, pid}

      :not_found ->
        DynamicSupervisor.start_child(
          HydraX.Agent.channel_supervisor(agent_id),
          {__MODULE__, agent_id: agent_id, conversation: conversation}
        )
    end
  end

  # In cluster mode, use :global for cross-node process registration.
  # In single-node mode, use local Registry for performance.
  defp channel_name(conversation_id) do
    if Cluster.enabled?() do
      {:global, {:channel, conversation_id}}
    else
      {:via, Registry, {HydraX.ProcessRegistry, {:channel, conversation_id}}}
    end
  end

  defp channel_lookup(conversation_id) do
    if Cluster.enabled?() do
      case :global.whereis_name({:channel, conversation_id}) do
        :undefined -> :not_found
        pid -> {:ok, pid}
      end
    else
      case Registry.lookup(HydraX.ProcessRegistry, {:channel, conversation_id}) do
        [{pid, _}] -> {:ok, pid}
        [] -> :not_found
      end
    end
  end

  @impl true
  def callback_mode, do: :handle_event_function

  @impl true
  def init(opts) do
    conversation = Keyword.fetch!(opts, :conversation)
    agent_id = Keyword.fetch!(opts, :agent_id)
    turns = Runtime.list_turns(conversation.id)
    {:ok, _pid} = Compactor.ensure_started(agent_id, conversation.id)

    data =
      %{
        agent_id: agent_id,
        conversation: conversation,
        turns: turns,
        coalesce_buffer: [],
        pending_from: []
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
    agent = Runtime.get_agent!(data.agent_id)
    bulletin = HydraX.Agent.Cortex.current_bulletin(data.agent_id)
    summary = Compactor.current_summary(data.conversation.id)
    tool_policy = Runtime.effective_tool_policy(data.agent_id)

    prompt = PromptBuilder.build(agent, history, bulletin, summary, %{tool_policy: tool_policy})

    # When no tools are available and streaming is supported, stream the response
    result =
      if (is_nil(prompt.tools) or prompt.tools == []) do
        case maybe_stream_final(prompt.messages, nil, data, 0, []) do
          {:streaming, _} = s -> s
          :not_streaming -> run_tool_loop(prompt.messages, prompt.tools, data, 0, [])
        end
      else
        run_tool_loop(prompt.messages, prompt.tools, data, 0, [])
      end

    case result do
      {:streaming, stream_data} ->
        # Streaming mode — stay in :processing state and wait for
        # {:chunk, ref, delta} and {:done, ref, response} messages
        {:keep_state, Map.merge(data, stream_data)}

      {response_content, response_metadata} ->
        {:ok, assistant_turn} =
          Runtime.append_turn(data.conversation, %{
            role: "assistant",
            kind: "message",
            content: response_content,
            metadata: response_metadata
          })

        Runtime.upsert_checkpoint(data.conversation.id, "channel", %{
          "assistant_turn_id" => assistant_turn.id,
          "updated_at" => DateTime.utc_now()
        })

        Enum.each(data.pending_from, &:gen_statem.reply(&1, assistant_turn.content))
        Compactor.review(data.agent_id, data.conversation.id)

        Phoenix.PubSub.broadcast(HydraX.PubSub, "conversations", {:conversation_updated, data.conversation.id})

        {:next_state, :ready,
         %{
           data
           | turns: history ++ [assistant_turn],
             coalesce_buffer: [],
             pending_from: []
         }}
    end
  end

  # Handle streaming chunk messages — broadcast to PubSub for LiveView
  def handle_event(:info, {:chunk, ref, delta}, :processing, data) do
    if data[:stream_ref] == ref do
      Phoenix.PubSub.broadcast(
        HydraX.PubSub,
        "conversations:stream",
        {:stream_chunk, data.conversation.id, delta}
      )
    end

    {:keep_state, data}
  end

  # Handle streaming completion — finalize the response
  def handle_event(:info, {:done, ref, response}, :processing, data) do
    if data[:stream_ref] == ref do
      finalize_streamed_response(response, data)
    else
      {:keep_state, data}
    end
  end

  # Handle streaming error — fall back to error response
  def handle_event(:info, {:stream_error, ref, reason}, :processing, data) do
    if data[:stream_ref] == ref do
      Safety.log_event(%{
        agent_id: data.agent_id,
        conversation_id: data.conversation.id,
        category: "provider",
        level: "error",
        message: "LLM streaming failed",
        metadata: %{reason: inspect(reason)}
      })

      finalize_streamed_response(
        %{content: "Streaming failed. Check /health and provider settings.", provider: "stream-error"},
        data
      )
    else
      {:keep_state, data}
    end
  end

  def handle_event(_type, _event, _state, data), do: {:keep_state, data}

  # Tool-calling loop: iteratively call LLM, execute tools, feed results back
  defp run_tool_loop(messages, _tools, data, round, all_tool_results)
       when round >= @max_tool_rounds do
    # Max rounds exceeded — force a final response without tools
    # Try streaming for the final response on streamable channels
    case maybe_stream_final(messages, nil, data, round, all_tool_results) do
      {:streaming, _} = result -> result
      :not_streaming -> sync_final_call(messages, nil, data, round, all_tool_results)
    end
  end

  defp run_tool_loop(messages, tools, data, round, all_tool_results) do
    case do_llm_call(messages, tools, data) do
      {:ok, %{tool_calls: tool_calls, stop_reason: "tool_use"} = response}
      when is_list(tool_calls) and tool_calls != [] ->
        # LLM wants to call tools — execute them and loop
        tool_results =
          Worker.execute_tool_calls(data.agent_id, data.conversation, tool_calls)

        # Build the next messages: append assistant's tool_use, then user's tool_results
        next_messages =
          messages
          |> PromptBuilder.append_assistant_tool_use(response)
          |> PromptBuilder.append_tool_results(tool_results)

        run_tool_loop(
          next_messages,
          tools,
          data,
          round + 1,
          all_tool_results ++ tool_results
        )

      {:ok, response} ->
        # Final response — no more tool calls
        content = response.content || ""

        {content,
         %{
           provider: response.provider,
           tool_rounds: round,
           tool_results: all_tool_results
         }}

      {:error_response, content, metadata} ->
        {content, Map.merge(metadata, %{tool_rounds: round, tool_results: all_tool_results})}
    end
  end

  defp do_llm_call(messages, tools, data) do
    estimated_input_tokens = Budget.estimate_prompt_tokens(messages)

    case Budget.preflight(data.agent_id, data.conversation.id, estimated_input_tokens) do
      {:ok, result} ->
        maybe_log_budget_warning(data, result)

        request =
          %{messages: messages}
          |> maybe_put_tools(tools)

        case Router.complete(request) do
          {:ok, response} ->
            Telemetry.provider_request(:ok, response.provider)
            output_tokens = Budget.estimate_tokens(response.content || "")

            Budget.record_usage(data.agent_id, data.conversation.id,
              tokens_in: estimated_input_tokens,
              tokens_out: output_tokens,
              metadata: %{provider: response.provider}
            )

            {:ok, response}

          {:error, reason} ->
            Telemetry.provider_request(:error, provider_name(data.agent_id), %{
              reason: inspect(reason)
            })

            Safety.log_event(%{
              agent_id: data.agent_id,
              conversation_id: data.conversation.id,
              category: "provider",
              level: "error",
              message: "LLM provider request failed",
              metadata: %{reason: inspect(reason)}
            })

            {:error_response,
             "Provider request failed. Check /health and provider settings before retrying.",
             %{provider: "provider-error", provider_error: inspect(reason)}}
        end

      {:error, details} ->
        Telemetry.budget_event(:rejected, %{agent_id: data.agent_id})

        Safety.log_event(%{
          agent_id: data.agent_id,
          conversation_id: data.conversation.id,
          category: "budget",
          level: "error",
          message: "Budget hard limit exceeded",
          metadata: %{estimated_tokens: estimated_input_tokens, usage: details.usage}
        })

        {:error_response,
         "Budget limit reached for this agent or conversation. Raise the policy in /budget before sending more LLM traffic.",
         %{provider: "budget-guard"}}
    end
  end

  # Attempt to stream the final LLM response on streamable channels.
  # Returns {:streaming, stream_data} if the response will be streamed asynchronously,
  # or :not_streaming if streaming is not available/applicable.
  defp maybe_stream_final(messages, tools, data, round, all_tool_results) do
    if stream_enabled?(data.conversation) do
      estimated_input_tokens = Budget.estimate_prompt_tokens(messages)

      case Budget.preflight(data.agent_id, data.conversation.id, estimated_input_tokens) do
        {:ok, result} ->
          maybe_log_budget_warning(data, result)

          request =
            %{messages: messages}
            |> maybe_put_tools(tools)

          case Router.complete_stream(request, self()) do
            {:ok, ref} ->
              # Return streaming state to be merged into gen_statem data
              {:streaming,
               %{
                 stream_ref: ref,
                 stream_round: round,
                 stream_tool_results: all_tool_results,
                 stream_input_tokens: estimated_input_tokens
               }}

            {:error, _reason} ->
              :not_streaming
          end

        {:error, _details} ->
          :not_streaming
      end
    else
      :not_streaming
    end
  end

  defp sync_final_call(messages, tools, data, round, all_tool_results) do
    case do_llm_call(messages, tools, data) do
      {:ok, response} ->
        content = response.content || "I've completed the requested actions."

        {content,
         %{
           provider: response.provider,
           tool_rounds: round,
           tool_results: all_tool_results
         }}

      {:error_response, content, metadata} ->
        {content, Map.merge(metadata, %{tool_rounds: round, tool_results: all_tool_results})}
    end
  end

  defp finalize_streamed_response(response, data) do
    round = Map.get(data, :stream_round, 0)
    all_tool_results = Map.get(data, :stream_tool_results, [])
    estimated_input_tokens = Map.get(data, :stream_input_tokens, 0)

    content = response.content || ""
    output_tokens = Budget.estimate_tokens(content)

    Budget.record_usage(data.agent_id, data.conversation.id,
      tokens_in: estimated_input_tokens,
      tokens_out: output_tokens,
      metadata: %{provider: response.provider}
    )

    Telemetry.provider_request(:ok, response.provider)

    metadata = %{
      provider: response.provider,
      tool_rounds: round,
      tool_results: all_tool_results,
      streamed: true
    }

    {:ok, assistant_turn} =
      Runtime.append_turn(data.conversation, %{
        role: "assistant",
        kind: "message",
        content: content,
        metadata: metadata
      })

    Runtime.upsert_checkpoint(data.conversation.id, "channel", %{
      "assistant_turn_id" => assistant_turn.id,
      "updated_at" => DateTime.utc_now()
    })

    Enum.each(data.pending_from, &:gen_statem.reply(&1, assistant_turn.content))
    Compactor.review(data.agent_id, data.conversation.id)

    # Broadcast stream end to clear streaming UI, then conversation update
    Phoenix.PubSub.broadcast(
      HydraX.PubSub,
      "conversations:stream",
      {:stream_done, data.conversation.id}
    )

    Phoenix.PubSub.broadcast(
      HydraX.PubSub,
      "conversations",
      {:conversation_updated, data.conversation.id}
    )

    history = Runtime.list_turns(data.conversation.id)

    # Clean up streaming state from data
    cleaned_data =
      data
      |> Map.delete(:stream_ref)
      |> Map.delete(:stream_round)
      |> Map.delete(:stream_tool_results)
      |> Map.delete(:stream_input_tokens)

    {:next_state, :ready,
     %{
       cleaned_data
       | turns: history,
         coalesce_buffer: [],
         pending_from: []
     }}
  end

  defp stream_enabled?(%{channel: channel}) when channel in @streamable_channels, do: true
  defp stream_enabled?(_conversation), do: false

  defp maybe_put_tools(request, nil), do: request
  defp maybe_put_tools(request, []), do: request
  defp maybe_put_tools(request, tools), do: Map.put(request, :tools, tools)

  defp maybe_log_budget_warning(_data, %{warnings: []}), do: :ok

  defp maybe_log_budget_warning(data, %{warnings: warnings, usage: usage}) do
    status =
      cond do
        :hard_limit_reached in warnings -> :hard_warning
        :soft_limit_reached in warnings -> :soft_warning
        true -> :warning
      end

    Telemetry.budget_event(status, %{agent_id: data.agent_id, usage: usage})

    {level, message} =
      cond do
        :hard_limit_reached in warnings ->
          {"warn", "Budget hard limit reached but policy is set to warn only"}

        :soft_limit_reached in warnings ->
          {"warn", "Budget soft limit reached"}

        true ->
          {"info", "Budget policy warning"}
      end

    Safety.log_event(%{
      agent_id: data.agent_id,
      conversation_id: data.conversation.id,
      category: "budget",
      level: level,
      message: message,
      metadata: %{warnings: warnings, usage: usage}
    })
  end

  defp provider_name(_agent_id) do
    case Runtime.enabled_provider() do
      nil -> "mock"
      provider -> provider.name || provider.kind || "configured"
    end
  end
end
