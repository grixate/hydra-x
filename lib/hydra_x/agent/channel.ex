defmodule HydraX.Agent.Channel do
  @moduledoc false
  @behaviour :gen_statem

  alias HydraX.Agent.{Compactor, Planner, PromptBuilder, Worker}
  alias HydraX.Budget
  alias HydraX.Cluster
  alias HydraX.Config
  alias HydraX.Gateway
  alias HydraX.LLM.Router
  alias HydraX.Repo
  alias HydraX.Runtime
  alias HydraX.Safety
  alias HydraX.Telemetry

  @max_tool_rounds 5
  @streamable_channels ~w(control_plane cli webchat)

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
    case ensure_started(agent.id, conversation) do
      {:ok, _pid} ->
        response =
          :gen_statem.call(channel_name(conversation.id), {:submit, content, metadata}, 30_000)

        wait_for_stable_channel_state(conversation.id)
        response

      {:error, {:owned_elsewhere, ownership}} ->
        {:ok, turn} =
          append_deferred_turn(conversation, content, metadata, ownership)

        update_channel_checkpoint(conversation.id, %{
          "status" => "deferred",
          "ownership" => ownership,
          "resumable" => true,
          "pending_turn_id" => turn.id,
          "updated_at" => DateTime.utc_now()
        })

        append_channel_event(conversation.id, "ownership_deferred", %{
          "summary" => deferred_message(ownership),
          "pending_turn_id" => turn.id,
          "owner" => ownership["owner"],
          "owner_node" => ownership["owner_node"]
        })

        {:deferred, deferred_message(ownership)}
    end
  end

  def ensure_started(agent_id, conversation) do
    case channel_lookup(conversation.id) do
      {:ok, pid} ->
        {:ok, pid}

      :not_found ->
        case ownership_conflict(conversation.id) do
          {:error, ownership} ->
            {:error, {:owned_elsewhere, ownership}}

          :ok ->
            with {:ok, pid} <-
                   DynamicSupervisor.start_child(
                     HydraX.Agent.channel_supervisor(agent_id),
                     {__MODULE__, agent_id: agent_id, conversation: conversation}
                   ) do
              if recovery_pending?(conversation.id) do
                wait_for_stable_channel_state(conversation.id, 300)
              end

              {:ok, pid}
            end
        end
    end
  end

  def active?(conversation_id) when is_integer(conversation_id) do
    case channel_lookup(conversation_id) do
      {:ok, pid} -> Process.alive?(pid)
      :not_found -> false
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

    pending_turns = resumable_pending_turns(conversation.id, turns)
    recovered? = pending_turns != []

    data =
      %{
        agent_id: agent_id,
        conversation: conversation,
        turns: turns,
        coalesce_buffer: pending_turns,
        pending_from: [],
        ownership: nil,
        release_ownership_on_terminate: true,
        handoff_pending: nil,
        handoff_waiting_for: nil
      }
      |> refresh_conversation_ownership(if(recovered?, do: "recovering", else: "idle"))
      |> schedule_lease_tick()

    if recovered? do
      append_channel_event(conversation.id, "recovered_after_restart", %{
        "summary" =>
          "Recovered #{length(pending_turns)} pending user turn(s) after channel restart",
        "pending_turn_ids" => Enum.map(pending_turns, & &1.id)
      })

      update_channel_checkpoint(conversation.id, %{
        "status" => "interrupted",
        "ownership" => data.ownership,
        "resumable" => true,
        "recovery_lineage" => recovered_recovery_lineage(conversation.id, pending_turns),
        "updated_at" => DateTime.utc_now()
      })

      {:ok, :processing, data, [{:next_event, :internal, :process_buffer}]}
    else
      {:ok, :ready, data}
    end
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
    case refresh_conversation_ownership(data, "processing") do
      %{ownership: %{"active" => false} = ownership} = refreshed_data ->
        maybe_defer_ownership_loss(:processing, refreshed_data, ownership)

      refreshed_data ->
        process_buffer(refreshed_data)
    end
  end

  def handle_event(:info, :lease_tick, state, data) when state in [:ready, :processing] do
    refreshed_data = refresh_conversation_ownership(data, current_state_stage(state))

    case refreshed_data.ownership do
      %{"active" => false} = ownership ->
        maybe_defer_ownership_loss(state, refreshed_data, ownership)

      _ ->
        update_channel_checkpoint(refreshed_data.conversation.id, %{
          "ownership" => refreshed_data.ownership,
          "updated_at" => DateTime.utc_now()
        })

        {:keep_state, schedule_lease_tick(refreshed_data)}
    end
  end

  def handle_event(:info, :lease_tick, _state, data) do
    {:keep_state, schedule_lease_tick(data)}
  end

  # Handle streaming chunk messages — broadcast to PubSub for LiveView
  def handle_event(:info, {:chunk, ref, delta}, :processing, data) do
    handle_stream_chunk(ref, delta, data)
  end

  # Handle streaming completion — finalize the response
  def handle_event(:info, {:done, ref, response}, :processing, data) do
    handle_stream_done(ref, response, data)
  end

  # Handle streaming error — fall back to error response
  def handle_event(:info, {:stream_error, ref, reason}, :processing, data) do
    handle_stream_error(ref, reason, data)
  end

  def handle_event(:info, {:tool_results_ready, ref, payload}, :processing, data) do
    handle_tool_results(ref, payload, data)
  end

  def handle_event(:info, {:tool_results_error, ref, reason}, :processing, data) do
    handle_tool_results_error(ref, reason, data)
  end

  def handle_event(_type, _event, _state, data), do: {:keep_state, data}

  @impl true
  def terminate(_reason, _state, data) do
    _ = release_conversation_ownership(data)
    :ok
  end

  defp process_buffer(data) do
    maybe_record_handoff_restart(data.conversation.id)

    case pending_response_state(data.conversation.id) do
      %{"content" => content, "metadata" => metadata} ->
        finalize_pending_response(content, metadata, data)

      _ ->
        process_buffer_turns(data)
    end
  end

  defp process_buffer_turns(data) do
    history = Runtime.list_turns(data.conversation.id)
    agent = Runtime.get_agent!(data.agent_id)
    bulletin = HydraX.Agent.Cortex.current_bulletin(data.agent_id)
    summary = Compactor.current_summary(data.conversation.id)
    tool_policy = Runtime.effective_tool_policy(data.agent_id)

    prompt =
      PromptBuilder.build(agent, history, bulletin, summary, %{
        tool_policy: tool_policy,
        skill_context:
          Runtime.skill_prompt_context(agent.id, %{
            channel: data.conversation.channel,
            tool_names: Enum.map(prompt_tools(tool_policy), & &1.name)
          }),
        mcp_context: Runtime.mcp_prompt_context(agent.id)
      })

    plan =
      Planner.build(
        data.conversation,
        data.coalesce_buffer,
        prompt.tools || [],
        Runtime.enabled_skills(data.agent_id)
      )

    update_channel_checkpoint(data.conversation.id, %{
      "status" => "planned",
      "ownership" => data.ownership,
      "handoff" => nil,
      "plan" => plan,
      "steps" => plan["steps"] || [],
      "tool_cache" =>
        tool_cache_for_turn(data.conversation.id, latest_turn_id(data.coalesce_buffer)),
      "tool_cache_scope_turn_id" => latest_turn_id(data.coalesce_buffer),
      "current_step_id" => step_id_for_status(plan["steps"] || [], "pending"),
      "current_step_index" => step_index_for_status(plan["steps"] || [], "pending"),
      "resumable" => true,
      "latest_user_turn_id" => latest_turn_id(data.coalesce_buffer),
      "recovery_lineage" =>
        planning_recovery_lineage(data.conversation.id, latest_turn_id(data.coalesce_buffer)),
      "tool_rounds" => 0,
      "tool_results" => [],
      "execution_events" =>
        append_execution_event(
          current_execution_events(data.conversation.id),
          "planned",
          %{
            "summary" => "Planned #{length(plan["steps"] || [])} execution steps",
            "step_count" => length(plan["steps"] || []),
            "mode" => plan["mode"],
            "skill_hint_count" => length(plan["skill_hints"] || [])
          }
        ),
      "updated_at" => DateTime.utc_now()
    })

    # When no tools are available and streaming is supported, stream the response
    result =
      if is_nil(prompt.tools) or prompt.tools == [] do
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

      {:tool_execution, tool_data} ->
        {:keep_state, Map.merge(data, tool_data)}

      {response_content, response_metadata} ->
        complete_response(response_content, response_metadata, data)

      {:stop, _, _} = stop ->
        stop
    end
  end

  defp handle_stream_chunk(ref, delta, data) do
    if data[:stream_ref] == ref do
      updated_data =
        data
        |> Map.update(:stream_content, delta, &(&1 <> delta))
        |> Map.update(:stream_chunk_count, 1, &(&1 + 1))

      if is_nil(updated_data[:handoff_pending]) do
        Phoenix.PubSub.broadcast(
          HydraX.PubSub,
          "conversations:stream",
          {:stream_chunk, data.conversation.id, delta}
        )

        maybe_refresh_streaming_delivery(updated_data)
        maybe_persist_stream_snapshot(updated_data)
      else
        update_channel_checkpoint(
          data.conversation.id,
          %{"stream_capture" => stream_capture_payload(updated_data)}
        )

        maybe_refresh_streaming_delivery(updated_data)
      end

      {:keep_state, updated_data}
    else
      {:keep_state, data}
    end
  end

  defp handle_stream_done(ref, response, data) do
    if data[:stream_ref] == ref do
      finalize_streamed_response(response, data)
    else
      {:keep_state, data}
    end
  end

  defp handle_stream_error(ref, reason, data) do
    if data[:stream_ref] == ref do
      Safety.log_event(%{
        agent_id: data.agent_id,
        conversation_id: data.conversation.id,
        category: "provider",
        level: "error",
        message: "LLM streaming failed",
        metadata: %{reason: inspect(reason)}
      })

      stream_error_response = %{
        content: "Streaming failed. Check /health and provider settings.",
        provider: "stream-error"
      }

      case data[:handoff_pending] do
        nil ->
          finalize_streamed_response(stream_error_response, data)

        ownership ->
          stop_for_ownership_loss(
            :processing,
            clear_handoff_state(data),
            ownership,
            %{"handoff" => nil, "updated_at" => DateTime.utc_now()}
          )
      end
    else
      {:keep_state, data}
    end
  end

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
        with {:ok, refreshed_data} <- ensure_active_ownership(data, "tool_requested") do
          updated_steps =
            tool_calls
            |> Enum.reduce(current_checkpoint_steps(refreshed_data.conversation.id), fn tool_call,
                                                                                        steps ->
              mark_step_running(steps, "tool", tool_call.name)
            end)

          append_channel_event(refreshed_data.conversation.id, "provider_tool_request", %{
            "round" => round + 1,
            "provider" => response.provider,
            "tool_count" => length(tool_calls)
          })

          launch_tool_execution(
            messages,
            tools,
            refreshed_data,
            round,
            all_tool_results,
            response,
            tool_calls,
            updated_steps
          )
        else
          {:error, ownership, lost_data} ->
            stop_for_ownership_loss(:processing, lost_data, ownership)
        end

      {:ok, response} ->
        with {:ok, refreshed_data} <- ensure_active_ownership(data, "provider_response") do
          steps =
            current_checkpoint_steps(refreshed_data.conversation.id)
            |> mark_provider_running(%{"summary" => "Waiting for final provider response"})
            |> mark_provider_completed(%{
              "summary" => "Final response generated",
              "output_excerpt" => excerpt_text(response.content || ""),
              "provider" => response.provider,
              "stop_reason" => response.stop_reason
            })

          append_channel_event(refreshed_data.conversation.id, "provider_completed", %{
            "round" => round,
            "provider" => response.provider,
            "stop_reason" => response.stop_reason,
            "content_length" => String.length(response.content || "")
          })

          update_channel_checkpoint(refreshed_data.conversation.id, %{
            "ownership" => refreshed_data.ownership,
            "steps" => steps,
            "current_step_id" => nil,
            "current_step_index" => nil
          })

          content = response.content || ""

          {content,
           %{
             provider: response.provider,
             tool_rounds: round,
             tool_results: all_tool_results
           }}
        else
          {:error, ownership, lost_data} ->
            stop_for_ownership_loss(
              :processing,
              lost_data,
              ownership,
              pending_response_attrs(response, round, all_tool_results)
            )
        end

      {:error_response, content, metadata} ->
        steps =
          current_checkpoint_steps(data.conversation.id)
          |> mark_provider_running(%{"summary" => "Waiting for final provider response"})
          |> mark_provider_failed(%{
            "summary" => "Provider response failed",
            "output_excerpt" => excerpt_text(content),
            "provider" => metadata[:provider] || metadata["provider"],
            "reason" => metadata[:provider_error] || metadata["provider_error"]
          })

        update_channel_checkpoint(data.conversation.id, %{
          "status" => "failed",
          "ownership" => data.ownership,
          "steps" => steps,
          "current_step_id" => current_step_id_after_failure(steps),
          "current_step_index" => current_step_index_after_failure(steps),
          "resumable" => false,
          "updated_at" => DateTime.utc_now()
        })

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
          |> Map.put(:agent_id, data.agent_id)
          |> Map.put(:process_type, "channel")
          |> maybe_put_tools(tools)

        append_channel_event(data.conversation.id, "provider_requested", %{
          "provider" => provider_name(data.agent_id),
          "estimated_input_tokens" => estimated_input_tokens,
          "tooling" => if(is_list(tools) and tools != [], do: "tool_capable", else: "direct")
        })

        case Router.complete(request) do
          {:ok, response} ->
            Telemetry.provider_request(:ok, response.provider)
            output_tokens = Budget.estimate_tokens(response.content || "")

            Budget.record_usage(data.agent_id, data.conversation.id,
              tokens_in: estimated_input_tokens,
              tokens_out: output_tokens,
              metadata: %{provider: response.provider}
            )

            append_channel_event(data.conversation.id, "provider_succeeded", %{
              "provider" => response.provider,
              "output_tokens" => output_tokens,
              "stop_reason" => response.stop_reason
            })

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

            append_channel_event(data.conversation.id, "provider_failed", %{
              "provider" => provider_name(data.agent_id),
              "reason" => inspect(reason)
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
            |> Map.put(:agent_id, data.agent_id)
            |> Map.put(:process_type, "channel")
            |> maybe_put_tools(tools)

          case Router.complete_stream(request, self()) do
            {:ok, ref} ->
              steps =
                current_checkpoint_steps(data.conversation.id)
                |> mark_provider_running(%{"summary" => "Streaming provider response"})

              update_channel_checkpoint(data.conversation.id, %{
                "status" => "streaming",
                "ownership" => data.ownership,
                "steps" => steps,
                "current_step_id" => step_id_for_running(steps),
                "current_step_index" => step_index_for_running(steps),
                "resumable" => true,
                "stream_capture" => nil,
                "updated_at" => DateTime.utc_now()
              })

              append_channel_event(data.conversation.id, "stream_started", %{
                "provider" => provider_name(data.agent_id),
                "estimated_input_tokens" => estimated_input_tokens,
                "round" => round
              })

              maybe_mark_streaming_delivery(data, "", 0)

              # Return streaming state to be merged into gen_statem data
              {:streaming,
               %{
                 stream_ref: ref,
                 stream_round: round,
                 stream_tool_results: all_tool_results,
                 stream_input_tokens: estimated_input_tokens,
                 stream_content: "",
                 stream_chunk_count: 0
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

    append_channel_event(data.conversation.id, "stream_completed", %{
      "provider" => response.provider,
      "output_tokens" => output_tokens,
      "round" => round
    })

    Telemetry.provider_request(:ok, response.provider)

    metadata = %{
      provider: response.provider,
      tool_rounds: round,
      tool_results: all_tool_results,
      streamed: true
    }

    case data[:handoff_pending] do
      nil ->
        case ensure_active_ownership(data, "stream_finalizing") do
          {:ok, refreshed_data} ->
            complete_response(
              content,
              metadata,
              refreshed_data,
              steps:
                current_checkpoint_steps(refreshed_data.conversation.id)
                |> mark_provider_completed(%{
                  "summary" => "Streamed response completed",
                  "output_excerpt" => excerpt_text(content),
                  "provider" => response.provider
                }),
              streamed?: true
            )

          {:error, ownership, lost_data} ->
            stop_for_ownership_loss(
              :processing,
              lost_data,
              ownership,
              pending_response_attrs(response, round, all_tool_results, streamed: true)
            )
        end

      ownership ->
        stop_for_ownership_loss(
          :processing,
          clear_handoff_state(data),
          ownership,
          Map.merge(
            pending_response_attrs(response, round, all_tool_results, streamed: true),
            %{"handoff" => nil}
          )
        )
    end
  end

  defp launch_tool_execution(
         messages,
         tools,
         data,
         round,
         all_tool_results,
         response,
         tool_calls,
         updated_steps
       ) do
    tool_task_ref = make_ref()
    caller = self()

    Task.Supervisor.start_child(HydraX.TaskSupervisor, fn ->
      try do
        {tool_results, cache_hits, cache_misses} = execute_tool_calls_with_cache(data, tool_calls)

        send(caller, {
          :tool_results_ready,
          tool_task_ref,
          %{
            tool_results: tool_results,
            cache_hits: cache_hits,
            cache_misses: cache_misses
          }
        })
      rescue
        error ->
          send(
            caller,
            {:tool_results_error, tool_task_ref, Exception.format(:error, error, __STACKTRACE__)}
          )
      end
    end)

    active_tool_calls =
      Enum.map(tool_calls, fn call ->
        %{"id" => call.id, "name" => call.name}
      end)

    update_channel_checkpoint(data.conversation.id, %{
      "status" => "executing_tools",
      "ownership" => data.ownership,
      "steps" => updated_steps,
      "current_step_id" => step_id_for_running(updated_steps),
      "current_step_index" => step_index_for_running(updated_steps),
      "resumable" => true,
      "tool_rounds" => round + 1,
      "active_tool_calls" => active_tool_calls,
      "handoff" => nil,
      "stream_capture" => nil,
      "updated_at" => DateTime.utc_now()
    })

    {:tool_execution,
     %{
       tool_task_ref: tool_task_ref,
       tool_task_round: round,
       tool_task_active_calls: active_tool_calls,
       tool_task_messages: messages,
       tool_task_tools: tools,
       tool_task_tool_calls: tool_calls,
       tool_task_response: response,
       tool_task_all_results: all_tool_results,
       tool_task_updated_steps: updated_steps
     }}
  end

  defp handle_tool_results(ref, payload, data) do
    if data[:tool_task_ref] == ref do
      tool_results = payload.tool_results
      cache_hits = payload.cache_hits
      cache_misses = payload.cache_misses
      updated_steps = data[:tool_task_updated_steps] || []
      round = data[:tool_task_round] || 0
      all_tool_results = data[:tool_task_all_results] || []
      response = data[:tool_task_response]
      messages = data[:tool_task_messages] || []
      tools = data[:tool_task_tools]
      tool_calls = data[:tool_task_tool_calls] || []

      completed_steps = complete_tool_steps(updated_steps, tool_results)

      tool_attrs = %{
        "steps" => completed_steps,
        "current_step_id" => current_step_id_after_tools(completed_steps),
        "current_step_index" => current_step_index_after_tools(completed_steps),
        "resumable" => true,
        "tool_rounds" => round + 1,
        "active_tool_calls" =>
          Enum.map(tool_calls, fn call ->
            %{"id" => call.id, "name" => call.name}
          end),
        "tool_cache" =>
          merge_tool_cache(
            data.conversation.id,
            tool_results,
            latest_turn_id(data.coalesce_buffer),
            round + 1
          ),
        "recovery_lineage" =>
          update_recovery_lineage_cache_stats(
            data.conversation.id,
            cache_hits,
            cache_misses,
            tool_results
          ),
        "tool_results" => summarize_tool_results(all_tool_results ++ tool_results),
        "updated_at" => DateTime.utc_now()
      }

      cleaned_data = clear_tool_execution_state(data)

      case data[:handoff_pending] do
        nil ->
          case ensure_active_ownership(cleaned_data, "tool_results") do
            {:ok, post_tool_data} ->
              update_channel_checkpoint(
                post_tool_data.conversation.id,
                %{
                  "status" => "executing_tools",
                  "ownership" => post_tool_data.ownership,
                  "handoff" => nil
                }
                |> Map.merge(tool_attrs)
              )

              if cache_hits > 0 do
                append_channel_event(post_tool_data.conversation.id, "tool_cache_hit", %{
                  "round" => round + 1,
                  "cache_hits" => cache_hits,
                  "cache_misses" => cache_misses
                })
              end

              Enum.each(tool_results, fn result ->
                append_channel_event(post_tool_data.conversation.id, "tool_result", %{
                  "round" => round + 1,
                  "tool_name" => result.tool_name,
                  "is_error" => result[:is_error] || false,
                  "cached" => result[:cached] || false,
                  "summary" => result[:summary] || summarize_tool_result_payload(result.result),
                  "safety_classification" => result[:safety_classification] || "standard"
                })
              end)

              next_messages =
                messages
                |> PromptBuilder.append_assistant_tool_use(response)
                |> PromptBuilder.append_tool_results(tool_results)

              case run_tool_loop(
                     next_messages,
                     tools,
                     post_tool_data,
                     round + 1,
                     all_tool_results ++ tool_results
                   ) do
                {:streaming, stream_data} ->
                  {:keep_state, Map.merge(post_tool_data, stream_data)}

                {response_content, response_metadata} ->
                  complete_response(response_content, response_metadata, post_tool_data)

                {:stop, _, _} = stop ->
                  stop
              end

            {:error, ownership, lost_data} ->
              stop_for_ownership_loss(:processing, lost_data, ownership, tool_attrs)
          end

        ownership ->
          stop_for_ownership_loss(
            :processing,
            clear_handoff_state(cleaned_data),
            ownership,
            Map.merge(tool_attrs, %{"handoff" => nil})
          )
      end
    else
      {:keep_state, data}
    end
  end

  defp handle_tool_results_error(ref, reason, data) do
    if data[:tool_task_ref] == ref do
      case data[:handoff_pending] do
        nil ->
          {error_content, error_metadata} =
            {"Tool execution failed before results were persisted. Retry the conversation after checking tool safety and runtime state.",
             %{
               provider: "tool-error",
               provider_error: reason,
               tool_rounds: (data[:tool_task_round] || 0) + 1,
               tool_results: []
             }}

          cleaned_data = clear_tool_execution_state(data)
          complete_response(error_content, error_metadata, cleaned_data)

        ownership ->
          stop_for_ownership_loss(
            :processing,
            clear_handoff_state(clear_tool_execution_state(data)),
            ownership,
            %{"handoff" => nil, "updated_at" => DateTime.utc_now()}
          )
      end
    else
      {:keep_state, data}
    end
  end

  defp complete_response(response_content, response_metadata, data, opts \\ []) do
    {:ok, assistant_turn} =
      Runtime.append_turn(data.conversation, %{
        role: "assistant",
        kind: "message",
        content: response_content,
        metadata: response_metadata
      })

    idle_data = refresh_conversation_ownership(data, "idle")
    steps = Keyword.get(opts, :steps, current_checkpoint_steps(data.conversation.id))

    update_channel_checkpoint(data.conversation.id, %{
      "status" => "completed",
      "ownership" => idle_data.ownership,
      "handoff" => nil,
      "stream_capture" => nil,
      "steps" => steps,
      "current_step_id" => nil,
      "current_step_index" => nil,
      "resumable" => false,
      "assistant_turn_id" => assistant_turn.id,
      "provider" => response_metadata[:provider] || response_metadata["provider"],
      "tool_rounds" => response_metadata[:tool_rounds] || response_metadata["tool_rounds"] || 0,
      "tool_results" =>
        summarize_tool_results(
          response_metadata[:tool_results] || response_metadata["tool_results"] || []
        ),
      "pending_response" => nil,
      "updated_at" => DateTime.utc_now()
    })

    Enum.each(data.pending_from, &:gen_statem.reply(&1, assistant_turn.content))
    Compactor.review(data.agent_id, data.conversation.id)

    if Keyword.get(opts, :streamed?, false) do
      Phoenix.PubSub.broadcast(
        HydraX.PubSub,
        "conversations:stream",
        {:stream_done, data.conversation.id}
      )
    end

    Phoenix.PubSub.broadcast(
      HydraX.PubSub,
      "conversations",
      {:conversation_updated, data.conversation.id}
    )

    history = Runtime.list_turns(data.conversation.id)

    cleaned_data =
      idle_data
      |> Map.delete(:stream_ref)
      |> Map.delete(:stream_round)
      |> Map.delete(:stream_tool_results)
      |> Map.delete(:stream_input_tokens)
      |> Map.delete(:tool_task_ref)
      |> Map.delete(:tool_task_round)
      |> Map.delete(:tool_task_active_calls)
      |> Map.delete(:tool_task_messages)
      |> Map.delete(:tool_task_tools)
      |> Map.delete(:tool_task_tool_calls)
      |> Map.delete(:tool_task_response)
      |> Map.delete(:tool_task_all_results)
      |> Map.delete(:tool_task_updated_steps)
      |> Map.put(:handoff_pending, nil)
      |> Map.put(:handoff_waiting_for, nil)

    {:next_state, :ready,
     %{
       cleaned_data
       | turns: history,
         coalesce_buffer: [],
         pending_from: []
     }}
  end

  defp finalize_pending_response(content, metadata, data) do
    append_channel_event(data.conversation.id, "handoff_response_replayed", %{
      "summary" => "Completed a provider response captured before ownership handoff",
      "provider" => metadata["provider"] || metadata[:provider]
    })

    complete_response(content, metadata, data)
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

  defp provider_name(agent_id) do
    case Runtime.enabled_provider(agent_id, "channel") do
      nil -> "mock"
      provider -> provider.name || provider.kind || "configured"
    end
  end

  defp prompt_tools(tool_policy), do: HydraX.Tool.Registry.available_schemas(tool_policy)

  defp latest_turn_id([]), do: nil
  defp latest_turn_id(turns), do: turns |> List.last() |> then(&(&1 && &1.id))

  defp recovery_pending?(conversation_id) do
    state = Runtime.conversation_channel_state(conversation_id)

    state.status in ["deferred", "planned", "executing_tools", "streaming", "interrupted"] and
      is_nil(state.assistant_turn_id)
  end

  defp wait_for_stable_channel_state(conversation_id, attempts \\ 200)

  defp wait_for_stable_channel_state(_conversation_id, 0), do: :ok

  defp wait_for_stable_channel_state(conversation_id, attempts) do
    case Runtime.conversation_channel_state(conversation_id).status do
      status when status in ["planned", "executing_tools", "streaming", "interrupted"] ->
        Process.sleep(10)
        wait_for_stable_channel_state(conversation_id, attempts - 1)

      _ ->
        :ok
    end
  end

  defp update_channel_checkpoint(conversation_id, attrs) do
    existing = Runtime.get_checkpoint(conversation_id, "channel")
    ownership = current_conversation_ownership(conversation_id)

    state =
      ((existing && existing.state) || %{})
      |> maybe_put_current_ownership(ownership)
      |> Map.merge(attrs)

    Runtime.upsert_checkpoint(conversation_id, "channel", state)
  end

  defp append_channel_event(conversation_id, phase, details) when is_map(details) do
    existing = Runtime.get_checkpoint(conversation_id, "channel")
    state = (existing && existing.state) || %{}
    events = append_execution_event(Map.get(state, "execution_events", []), phase, details)

    Runtime.upsert_checkpoint(
      conversation_id,
      "channel",
      Map.put(state, "execution_events", events)
    )
  end

  defp current_execution_events(conversation_id) do
    Runtime.conversation_channel_state(conversation_id).execution_events || []
  end

  defp refresh_conversation_ownership(data, stage) do
    ownership = claim_conversation_ownership(data.conversation.id, stage)

    {:ok, conversation} =
      Runtime.update_conversation_metadata(data.conversation, %{
        "ownership" => ownership
      })

    %{data | conversation: conversation, ownership: ownership}
  end

  defp release_conversation_ownership(%{conversation: conversation} = data) do
    if not Map.get(data, :release_ownership_on_terminate, true) do
      :ok
    else
      if Config.repo_multi_writer?() do
        _ = Runtime.release_lease(conversation_lease_name(conversation.id))
      end

      ownership =
        ownership_payload(
          data.ownership || local_conversation_ownership(conversation.id, "released"),
          "released"
        )
        |> Map.put("active", false)
        |> Map.put("released_at", DateTime.utc_now())

      Runtime.update_conversation_metadata(conversation, %{"ownership" => ownership})
    end
  end

  defp maybe_defer_ownership_loss(state, data, ownership) do
    cond do
      data[:handoff_pending] ->
        {:keep_state, schedule_lease_tick(data)}

      data[:tool_task_ref] ->
        defer_ownership_handoff(data, ownership, "tool_results")

      data[:stream_ref] ->
        defer_ownership_handoff(data, ownership, "stream_response")

      true ->
        stop_for_ownership_loss(state, data, ownership)
    end
  end

  defp defer_ownership_handoff(data, ownership, waiting_for) do
    append_channel_event(data.conversation.id, "ownership_handoff_pending", %{
      "summary" => "Ownership changed while in-flight work was still running",
      "owner" => ownership["owner"],
      "owner_node" => ownership["owner_node"],
      "awaiting" => waiting_for
    })

    if waiting_for == "stream_response" do
      Phoenix.PubSub.broadcast(
        HydraX.PubSub,
        "conversations:stream",
        {:stream_done, data.conversation.id}
      )
    end

    update_channel_checkpoint(data.conversation.id, %{
      "status" => "deferred",
      "ownership" => ownership,
      "resumable" => true,
      "handoff" => handoff_payload(ownership, waiting_for),
      "stream_capture" => deferred_stream_capture(data, waiting_for),
      "updated_at" => DateTime.utc_now()
    })

    {:keep_state,
     schedule_lease_tick(%{
       data
       | ownership: ownership,
         handoff_pending: ownership,
         handoff_waiting_for: waiting_for
     })}
  end

  defp stop_for_ownership_loss(state, data, ownership, attrs \\ %{}) do
    summary = deferred_message(ownership)
    status = ownership_loss_status(state, data)
    resumable = status == "deferred"

    Enum.each(data.pending_from, &:gen_statem.reply(&1, {:deferred, summary}))

    append_channel_event(data.conversation.id, "ownership_lost", %{
      "summary" => summary,
      "owner" => ownership["owner"],
      "owner_node" => ownership["owner_node"],
      "stage" => ownership["stage"]
    })

    update_channel_checkpoint(
      data.conversation.id,
      %{
        "status" => status,
        "ownership" => ownership,
        "resumable" => resumable,
        "handoff" => nil,
        "updated_at" => DateTime.utc_now()
      }
      |> Map.merge(attrs)
    )

    Phoenix.PubSub.broadcast(
      HydraX.PubSub,
      "conversations",
      {:conversation_updated, data.conversation.id}
    )

    {:stop, :ownership_lost,
     %{
       data
       | ownership: ownership,
         pending_from: [],
         release_ownership_on_terminate: false
     }}
  end

  defp ownership_loss_status(:processing, _data), do: "deferred"

  defp ownership_loss_status(_state, data) do
    if data.coalesce_buffer != [] or data.pending_from != [] do
      "deferred"
    else
      "ownership_lost"
    end
  end

  defp claim_conversation_ownership(conversation_id, stage) do
    if Config.repo_multi_writer?() do
      case Runtime.claim_lease(conversation_lease_name(conversation_id),
             ttl_seconds: conversation_lease_ttl_seconds(),
             metadata: %{
               "type" => "conversation",
               "conversation_id" => conversation_id,
               "stage" => stage
             }
           ) do
        {:ok, lease} ->
          %{
            "mode" => "database_lease",
            "lease_name" => lease.name,
            "owner" => lease.owner,
            "owner_node" => lease.owner_node,
            "expires_at" => lease.expires_at,
            "active" => true
          }
          |> ownership_payload(stage)

        {:error, {:taken, lease}} ->
          %{
            "mode" => "database_lease",
            "lease_name" => lease.name,
            "owner" => lease.owner,
            "owner_node" => lease.owner_node,
            "expires_at" => lease.expires_at,
            "active" => false,
            "contended" => true
          }
          |> ownership_payload(stage)

        {:error, _reason} ->
          local_conversation_ownership(conversation_id, stage)
      end
    else
      local_conversation_ownership(conversation_id, stage)
    end
  end

  defp local_conversation_ownership(conversation_id, stage) do
    %{
      "mode" => "local_process",
      "lease_name" => conversation_lease_name(conversation_id),
      "owner" => Runtime.coordination_status().owner,
      "owner_node" => to_string(Cluster.node_id()),
      "expires_at" => nil,
      "active" => true
    }
    |> ownership_payload(stage)
  end

  defp ownership_payload(ownership, stage) do
    ownership
    |> Map.put("stage", stage)
    |> Map.put("updated_at", DateTime.utc_now())
  end

  defp ensure_active_ownership(data, stage) do
    refreshed_data = refresh_conversation_ownership(data, stage)

    case refreshed_data.ownership do
      %{"active" => false} = ownership -> {:error, ownership, refreshed_data}
      _ -> {:ok, refreshed_data}
    end
  end

  defp clear_tool_execution_state(data) do
    data
    |> Map.delete(:tool_task_ref)
    |> Map.delete(:tool_task_round)
    |> Map.delete(:tool_task_active_calls)
    |> Map.delete(:tool_task_messages)
    |> Map.delete(:tool_task_tools)
    |> Map.delete(:tool_task_tool_calls)
    |> Map.delete(:tool_task_response)
    |> Map.delete(:tool_task_all_results)
    |> Map.delete(:tool_task_updated_steps)
  end

  defp clear_handoff_state(data) do
    data
    |> Map.put(:handoff_pending, nil)
    |> Map.put(:handoff_waiting_for, nil)
  end

  defp schedule_lease_tick(data) do
    if Config.repo_multi_writer?() do
      Process.send_after(self(), :lease_tick, lease_tick_ms())
    end

    data
  end

  defp current_state_stage(:ready), do: "idle"
  defp current_state_stage(:processing), do: "processing"
  defp current_state_stage(_state), do: "idle"

  defp current_conversation_ownership(conversation_id) do
    case Repo.get(HydraX.Runtime.Conversation, conversation_id) do
      nil ->
        nil

      conversation ->
        metadata = conversation.metadata || %{}
        metadata["ownership"] || metadata[:ownership]
    end
  end

  defp maybe_put_current_ownership(state, nil), do: state

  defp maybe_put_current_ownership(state, ownership),
    do: Map.put_new(state, "ownership", ownership)

  defp conversation_lease_name(conversation_id), do: "conversation:#{conversation_id}"
  defp conversation_lease_ttl_seconds, do: 3_600
  defp lease_tick_ms, do: max(div(conversation_lease_ttl_seconds() * 1000, 3), 5_000)

  defp ownership_conflict(conversation_id) do
    if Config.repo_multi_writer?() do
      current_owner = Runtime.coordination_status().owner

      case Runtime.active_lease(conversation_lease_name(conversation_id)) do
        %{owner: owner} = lease ->
          if owner != current_owner do
            {:error,
             %{
               "mode" => "database_lease",
               "lease_name" => lease.name,
               "owner" => lease.owner,
               "owner_node" => lease.owner_node,
               "expires_at" => lease.expires_at,
               "active" => false,
               "contended" => true,
               "stage" => "deferred",
               "updated_at" => DateTime.utc_now()
             }}
          else
            :ok
          end

        nil ->
          :ok
      end
    else
      :ok
    end
  end

  defp deferred_message(ownership) do
    "Conversation ownership is held by #{ownership["owner"] || "another node"}; local execution deferred."
  end

  defp handoff_payload(ownership, waiting_for) do
    %{
      "status" => "pending",
      "owner" => ownership["owner"],
      "owner_node" => ownership["owner_node"],
      "waiting_for" => waiting_for,
      "requested_at" => DateTime.utc_now()
    }
  end

  defp pending_response_state(conversation_id) do
    Runtime.conversation_channel_state(conversation_id).pending_response
  end

  defp maybe_record_handoff_restart(conversation_id) do
    state = Runtime.conversation_channel_state(conversation_id)
    handoff = state.handoff || %{}

    if is_map(handoff) and handoff["status"] == "pending" and is_nil(state.pending_response) do
      append_channel_event(conversation_id, "handoff_restart", %{
        "summary" => "Restarted execution after an unfinished ownership handoff",
        "waiting_for" => handoff["waiting_for"],
        "captured_chars" => String.length(get_in(state.stream_capture || %{}, ["content"]) || ""),
        "captured_chunks" => get_in(state.stream_capture || %{}, ["chunk_count"])
      })
    end
  end

  defp deferred_stream_capture(data, "stream_response"), do: stream_capture_payload(data)
  defp deferred_stream_capture(_data, _waiting_for), do: nil

  defp maybe_persist_stream_snapshot(data) do
    chunk_count = data[:stream_chunk_count] || 0

    if Config.repo_multi_writer?() and stream_snapshot_due?(chunk_count) do
      update_channel_checkpoint(data.conversation.id, %{
        "stream_capture" => stream_capture_payload(data),
        "updated_at" => DateTime.utc_now()
      })

      Phoenix.PubSub.broadcast(
        HydraX.PubSub,
        "conversations",
        {:conversation_updated, data.conversation.id}
      )
    end
  end

  defp maybe_refresh_streaming_delivery(data) do
    chunk_count = data[:stream_chunk_count] || 0

    if stream_snapshot_due?(chunk_count) do
      maybe_mark_streaming_delivery(data, data[:stream_content] || "", chunk_count)
    end
  end

  defp maybe_mark_streaming_delivery(data, preview, chunk_count) do
    _ =
      Gateway.mark_streaming_delivery(data.conversation,
        preview: preview,
        chunk_count: chunk_count,
        provider: provider_name(data.agent_id)
      )

    :ok
  end

  defp stream_snapshot_due?(1), do: true
  defp stream_snapshot_due?(count) when is_integer(count) and count > 1, do: rem(count, 4) == 0
  defp stream_snapshot_due?(_count), do: false

  defp stream_capture_payload(data) do
    content = data[:stream_content] || ""
    chunk_count = data[:stream_chunk_count] || 0

    if content == "" and chunk_count == 0 do
      nil
    else
      %{
        "content" => content,
        "chunk_count" => chunk_count,
        "provider" => provider_name(data.agent_id),
        "captured_at" => DateTime.utc_now()
      }
    end
  end

  defp pending_response_attrs(response, round, all_tool_results, opts \\ []) do
    content = response.content || ""

    %{
      "pending_response" => %{
        "content" => content,
        "metadata" => %{
          "provider" => response.provider,
          "tool_rounds" => round,
          "tool_results" => all_tool_results,
          "streamed" => Keyword.get(opts, :streamed?, false)
        },
        "captured_at" => DateTime.utc_now(),
        "summary" => excerpt_text(content)
      },
      "provider" => response.provider,
      "tool_rounds" => round,
      "tool_results" => summarize_tool_results(all_tool_results),
      "updated_at" => DateTime.utc_now()
    }
  end

  defp append_deferred_turn(conversation, content, metadata, ownership) do
    Runtime.append_turn(conversation, %{
      role: "user",
      kind: "message",
      content: content,
      metadata:
        Map.merge(metadata || %{}, %{
          "deferred_to_owner" => ownership["owner"],
          "deferred_owner_node" => ownership["owner_node"]
        })
    })
  end

  defp append_execution_event(events, phase, details) do
    events
    |> List.wrap()
    |> Kernel.++([execution_event(phase, details)])
    |> Enum.take(-15)
  end

  defp execution_event(phase, details) do
    %{
      "phase" => phase,
      "at" => DateTime.utc_now(),
      "details" => details
    }
  end

  defp resumable_pending_turns(conversation_id, turns) do
    checkpoint = Runtime.get_checkpoint(conversation_id, "channel")
    state = (checkpoint && checkpoint.state) || %{}

    if state["status"] in ["deferred", "planned", "executing_tools", "streaming", "interrupted"] and
         is_nil(state["assistant_turn_id"]) do
      turns_after_last_assistant(turns)
    else
      []
    end
  end

  defp turns_after_last_assistant(turns) do
    last_assistant_sequence =
      turns
      |> Enum.filter(&(&1.role == "assistant"))
      |> List.last()
      |> then(&(&1 && &1.sequence))

    turns
    |> Enum.filter(fn turn ->
      turn.role == "user" and
        (is_nil(last_assistant_sequence) or turn.sequence > last_assistant_sequence)
    end)
  end

  defp current_checkpoint_steps(conversation_id) do
    Runtime.conversation_channel_state(conversation_id).steps || []
  end

  defp execute_tool_calls_with_cache(data, tool_calls) do
    cache =
      data.conversation.id
      |> current_tool_cache()
      |> Map.new(fn entry -> {entry["fingerprint"], entry} end)

    {cached_results, uncached_calls} =
      Enum.reduce(tool_calls, {[], []}, fn tool_call, {cached, uncached} ->
        fingerprint = tool_call_fingerprint(tool_call)

        case Map.get(cache, fingerprint) do
          nil ->
            {cached, [tool_call | uncached]}

          entry ->
            result =
              cached_tool_result(tool_call, entry)

            {[result | cached], uncached}
        end
      end)

    fresh_results =
      uncached_calls
      |> Enum.reverse()
      |> case do
        [] ->
          []

        calls ->
          fingerprints =
            Map.new(calls, fn call -> {call.id, tool_call_fingerprint(call)} end)

          Worker.execute_tool_calls(data.agent_id, data.conversation, calls)
          |> Enum.map(fn result ->
            result
            |> Map.put(:fingerprint, Map.fetch!(fingerprints, result.tool_use_id))
            |> Map.put(:cached, false)
            |> Map.put(:replayed, false)
            |> Map.put(:result_source, "fresh")
          end)
      end

    {
      Enum.reverse(cached_results) ++ fresh_results,
      length(cached_results),
      length(fresh_results)
    }
  end

  defp cached_tool_result(tool_call, entry) do
    %{
      tool_use_id: tool_call.id,
      tool_name: tool_call.name,
      result: entry["result"],
      is_error: entry["is_error"] || false,
      cached: true,
      replayed: true,
      result_source: "cache",
      fingerprint: entry["fingerprint"],
      summary: entry["summary"],
      safety_classification: entry["safety_classification"],
      cache_recorded_at: entry["cached_at"],
      cache_scope_turn_id: entry["scope_turn_id"],
      replay_provenance: entry["replay_provenance"] || %{}
    }
  end

  defp merge_tool_cache(conversation_id, results, scope_turn_id, round) do
    existing =
      current_tool_cache(conversation_id)
      |> Map.new(fn entry -> {entry["fingerprint"], entry} end)

    results
    |> Enum.reduce(existing, fn result, acc ->
      entry = tool_result_cache_entry(result, conversation_id, scope_turn_id, round)

      Map.put(
        acc,
        entry["fingerprint"],
        entry
      )
    end)
    |> Map.values()
  end

  defp tool_result_cache_entry(result, conversation_id, scope_turn_id, round) do
    %{
      "fingerprint" => result[:fingerprint],
      "tool_name" => result.tool_name,
      "result" => result.result,
      "is_error" => result[:is_error] || false,
      "summary" => result[:summary],
      "safety_classification" => result[:safety_classification] || "standard",
      "cached_at" => DateTime.utc_now(),
      "scope_turn_id" => scope_turn_id,
      "recorded_round" => round,
      "source_conversation_id" => conversation_id,
      "source_tool_use_id" => result.tool_use_id,
      "replay_provenance" => %{
        "result_source" => result[:result_source] || "fresh",
        "replayed" => result[:replayed] || false
      }
    }
  end

  defp current_tool_cache(conversation_id) do
    state = (Runtime.get_checkpoint(conversation_id, "channel") || %{state: %{}}).state || %{}
    Map.get(state, "tool_cache", [])
  end

  defp tool_cache_for_turn(conversation_id, latest_user_turn_id) do
    state = (Runtime.get_checkpoint(conversation_id, "channel") || %{state: %{}}).state || %{}

    if Map.get(state, "tool_cache_scope_turn_id") == latest_user_turn_id do
      Map.get(state, "tool_cache", [])
    else
      []
    end
  end

  defp tool_call_fingerprint(%{name: name, arguments: arguments}) do
    [name, normalized_fingerprint_term(arguments)]
    |> :erlang.term_to_binary()
    |> Base.encode16(case: :lower)
  end

  defp normalized_fingerprint_term(term) when is_map(term) do
    term
    |> Enum.map(fn {key, value} -> {to_string(key), normalized_fingerprint_term(value)} end)
    |> Enum.sort()
  end

  defp normalized_fingerprint_term(term) when is_list(term) do
    Enum.map(term, &normalized_fingerprint_term/1)
  end

  defp normalized_fingerprint_term(term), do: term

  defp mark_step_running(steps, "tool", tool_name) do
    {updated, found?} =
      Enum.map_reduce(steps, false, fn step, found? ->
        cond do
          found? ->
            {step, true}

          step["kind"] != "provider" and step["name"] == tool_name and step["status"] != "running" ->
            {
              step
              |> transition_step("running")
              |> Map.put("summary", "Executing #{tool_name}"),
              true
            }

          true ->
            {step, found?}
        end
      end)

    if found? do
      updated
    else
      updated ++
        [
          %{
            "id" => "tool-dynamic-#{tool_name}",
            "kind" => dynamic_step_kind(tool_name),
            "name" => tool_name,
            "label" => dynamic_step_label(tool_name),
            "reason" => "dynamically requested by provider",
            "status" => "pending",
            "executor" => "channel",
            "owner" => "channel",
            "attempt_count" => 0,
            "lifecycle" => "planned",
            "idempotency_key" => "tool-dynamic-#{tool_name}",
            "replay_strategy" => "cache_or_replay"
          }
          |> transition_step("running")
          |> Map.put("summary", "Executing #{tool_name}")
        ]
    end
  end

  defp complete_tool_steps(steps, tool_results) do
    Enum.reduce(tool_results, steps, fn result, acc ->
      update_matching_step(acc, "tool", result.tool_name, fn step ->
        terminal_status = if(result[:is_error] || false, do: "failed", else: "completed")

        step
        |> transition_step(terminal_status)
        |> Map.put("lifecycle", tool_step_lifecycle(result, terminal_status))
        |> Map.put("summary", result[:summary] || summarize_tool_result_payload(result.result))
        |> Map.put("output_excerpt", tool_result_excerpt(result.result))
        |> Map.put("cached", result[:cached] || false)
        |> Map.put("replayed", result[:replayed] || false)
        |> Map.put("result_source", result[:result_source] || "fresh")
        |> Map.put("cache_fingerprint", result[:fingerprint])
        |> Map.put(
          "replay_count",
          (step["replay_count"] || 0) + if(result[:replayed], do: 1, else: 0)
        )
        |> Map.put("tool_use_id", result.tool_use_id)
        |> Map.put("safety_classification", result[:safety_classification] || "standard")
      end)
    end)
  end

  defp mark_provider_running(steps, attrs) do
    update_matching_step(steps, "provider", nil, fn step ->
      step
      |> transition_step("running")
      |> merge_step_attrs(attrs)
    end)
  end

  defp mark_provider_completed(steps, attrs) do
    update_matching_step(steps, "provider", nil, fn step ->
      step
      |> transition_step("completed")
      |> merge_step_attrs(attrs)
    end)
  end

  defp mark_provider_failed(steps, attrs) do
    update_matching_step(steps, "provider", nil, fn step ->
      step
      |> transition_step("failed")
      |> merge_step_attrs(attrs)
    end)
  end

  defp update_matching_step(steps, "provider", _name, fun) do
    {updated, found?} =
      Enum.map_reduce(steps, false, fn step, found? ->
        cond do
          found? ->
            {step, true}

          step["kind"] == "provider" ->
            {fun.(step), true}

          true ->
            {step, found?}
        end
      end)

    if found? do
      updated
    else
      updated ++
        [
          %{
            "id" => "provider-final",
            "kind" => "provider",
            "label" => "Final response",
            "status" => "pending",
            "executor" => "channel",
            "owner" => "channel",
            "attempt_count" => 0,
            "lifecycle" => "planned",
            "idempotency_key" => "provider-final",
            "replay_strategy" => "replay"
          }
          |> fun.()
        ]
    end
  end

  defp update_matching_step(steps, "tool", name, fun) do
    Enum.map(steps, fn step ->
      if step["kind"] != "provider" and step["name"] == name do
        fun.(step)
      else
        step
      end
    end)
  end

  defp current_step_id_after_tools(steps), do: step_id_for_status(steps, "pending")
  defp current_step_index_after_tools(steps), do: step_index_for_status(steps, "pending")
  defp current_step_id_after_failure(steps), do: step_id_for_status(steps, "failed")
  defp current_step_index_after_failure(steps), do: step_index_for_status(steps, "failed")
  defp step_id_for_running(steps), do: step_id_for_status(steps, "running")
  defp step_index_for_running(steps), do: step_index_for_status(steps, "running")

  defp step_id_for_status(steps, status) do
    steps
    |> Enum.find(&(&1["status"] == status))
    |> then(&(&1 && &1["id"]))
  end

  defp step_index_for_status(steps, status) do
    Enum.find_index(steps, &(&1["status"] == status))
  end

  defp summarize_tool_results(results) do
    Enum.map(results, fn result ->
      %{
        "tool_use_id" => result.tool_use_id,
        "tool_name" => result.tool_name,
        "is_error" => result[:is_error] || false,
        "cached" => result[:cached] || false,
        "replayed" => result[:replayed] || false,
        "result_source" => result[:result_source] || "fresh",
        "fingerprint" => result[:fingerprint],
        "summary" => result[:summary] || summarize_tool_result_payload(result.result),
        "safety_classification" => result[:safety_classification] || "standard"
      }
    end)
  end

  defp tool_step_lifecycle(result, "failed") do
    if result[:cached], do: "replayed_failed", else: "failed"
  end

  defp tool_step_lifecycle(result, "completed") do
    cond do
      result[:cached] -> "cached"
      result[:replayed] -> "replayed"
      true -> "completed"
    end
  end

  defp tool_step_lifecycle(_result, status), do: status

  defp summarize_tool_result_payload(%{error: error}) when is_binary(error), do: error
  defp summarize_tool_result_payload(%{"error" => error}) when is_binary(error), do: error

  defp summarize_tool_result_payload(%{path: path}) when is_binary(path),
    do: "path=#{path}"

  defp summarize_tool_result_payload(%{"path" => path}) when is_binary(path),
    do: "path=#{path}"

  defp summarize_tool_result_payload(%{snapshot_path: path}) when is_binary(path),
    do: "snapshot=#{path}"

  defp summarize_tool_result_payload(%{"snapshot_path" => path}) when is_binary(path),
    do: "snapshot=#{path}"

  defp summarize_tool_result_payload(%{title: title}) when is_binary(title),
    do: "title=#{title}"

  defp summarize_tool_result_payload(%{"title" => title}) when is_binary(title),
    do: "title=#{title}"

  defp summarize_tool_result_payload(%{query: query}) when is_binary(query),
    do: "query=#{query}"

  defp summarize_tool_result_payload(%{"query" => query}) when is_binary(query),
    do: "query=#{query}"

  defp summarize_tool_result_payload(%{command: command}) when is_binary(command),
    do: "command=#{command}"

  defp summarize_tool_result_payload(%{"command" => command}) when is_binary(command),
    do: "command=#{command}"

  defp summarize_tool_result_payload(payload) do
    payload
    |> inspect(limit: 12, printable_limit: 120)
    |> String.slice(0, 180)
  end

  defp dynamic_step_kind("memory_recall"), do: "memory"
  defp dynamic_step_kind("memory_save"), do: "memory"
  defp dynamic_step_kind("mcp_inspect"), do: "integration"
  defp dynamic_step_kind("mcp_probe"), do: "integration"
  defp dynamic_step_kind("skill_inspect"), do: "skill"
  defp dynamic_step_kind("browser_automation"), do: "browser"
  defp dynamic_step_kind("web_search"), do: "search"
  defp dynamic_step_kind("http_fetch"), do: "fetch"
  defp dynamic_step_kind("shell_command"), do: "shell"
  defp dynamic_step_kind("workspace_read"), do: "workspace"
  defp dynamic_step_kind("workspace_list"), do: "workspace"
  defp dynamic_step_kind("workspace_write"), do: "workspace"
  defp dynamic_step_kind("workspace_patch"), do: "workspace"
  defp dynamic_step_kind(_tool_name), do: "tool"

  defp dynamic_step_label("memory_recall"), do: "Recall relevant memory"
  defp dynamic_step_label("memory_save"), do: "Persist new memory"
  defp dynamic_step_label("mcp_inspect"), do: "Inspect MCP integrations"
  defp dynamic_step_label("mcp_probe"), do: "Probe MCP integrations"
  defp dynamic_step_label("skill_inspect"), do: "Inspect enabled skills"
  defp dynamic_step_label("browser_automation"), do: "Inspect web page state"
  defp dynamic_step_label("web_search"), do: "Search the public web"
  defp dynamic_step_label("http_fetch"), do: "Fetch a specific URL"
  defp dynamic_step_label("shell_command"), do: "Run an allowlisted shell command"
  defp dynamic_step_label("workspace_read"), do: "Read a workspace file"
  defp dynamic_step_label("workspace_list"), do: "List workspace files"
  defp dynamic_step_label("workspace_write"), do: "Write a workspace file"
  defp dynamic_step_label("workspace_patch"), do: "Patch a workspace file"
  defp dynamic_step_label(tool_name), do: tool_name

  defp tool_result_excerpt(%{content: content}) when is_binary(content), do: excerpt_text(content)

  defp tool_result_excerpt(%{"content" => content}) when is_binary(content),
    do: excerpt_text(content)

  defp tool_result_excerpt(%{text: text}) when is_binary(text), do: excerpt_text(text)
  defp tool_result_excerpt(%{"text" => text}) when is_binary(text), do: excerpt_text(text)

  defp tool_result_excerpt(%{results: results}) when is_list(results),
    do: "#{length(results)} results"

  defp tool_result_excerpt(%{"results" => results}) when is_list(results),
    do: "#{length(results)} results"

  defp tool_result_excerpt(%{skills: skills}) when is_list(skills), do: "#{length(skills)} skills"

  defp tool_result_excerpt(%{"skills" => skills}) when is_list(skills),
    do: "#{length(skills)} skills"

  defp tool_result_excerpt(%{memories: memories}) when is_list(memories),
    do: "#{length(memories)} memories"

  defp tool_result_excerpt(%{"memories" => memories}) when is_list(memories),
    do: "#{length(memories)} memories"

  defp tool_result_excerpt(payload), do: summarize_tool_result_payload(payload)

  defp excerpt_text(text) when is_binary(text) do
    text
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, 180)
  end

  defp excerpt_text(_), do: nil

  defp merge_step_attrs(step, attrs) when is_map(attrs) do
    Enum.reduce(attrs, step, fn {key, value}, acc ->
      if is_nil(value) or value == "" do
        acc
      else
        Map.put(acc, to_string(key), value)
      end
    end)
  end

  defp transition_step(step, status) do
    now = DateTime.utc_now()

    step
    |> Map.put("status", status)
    |> Map.put("lifecycle", if(status == "running", do: "started", else: status))
    |> Map.put("updated_at", now)
    |> maybe_mark_step_started(status, now)
    |> maybe_mark_step_finished(status, now)
  end

  defp maybe_mark_step_started(step, "running", now) do
    step
    |> Map.update("attempt_count", 1, &((&1 || 0) + 1))
    |> Map.put_new("started_at", now)
    |> Map.put("last_started_at", now)
  end

  defp maybe_mark_step_started(step, _status, _now), do: step

  defp maybe_mark_step_finished(step, "completed", now) do
    step
    |> Map.put("completed_at", now)
    |> Map.delete("failed_at")
  end

  defp maybe_mark_step_finished(step, "failed", now) do
    step
    |> Map.put("failed_at", now)
    |> Map.delete("completed_at")
  end

  defp maybe_mark_step_finished(step, _status, _now), do: step

  defp current_recovery_lineage(conversation_id) do
    state = (Runtime.get_checkpoint(conversation_id, "channel") || %{state: %{}}).state || %{}
    Map.get(state, "recovery_lineage", %{})
  end

  defp planning_recovery_lineage(conversation_id, latest_user_turn_id) do
    current = current_recovery_lineage(conversation_id)

    if current["turn_scope_id"] == latest_user_turn_id and not is_nil(latest_user_turn_id) do
      Map.put(current, "last_planned_at", DateTime.utc_now())
    else
      %{
        "turn_scope_id" => latest_user_turn_id,
        "recovery_count" => 0,
        "cache_hits" => 0,
        "cache_misses" => 0,
        "replayed_tool_names" => [],
        "last_planned_at" => DateTime.utc_now()
      }
    end
  end

  defp recovered_recovery_lineage(conversation_id, pending_turns) do
    current = current_recovery_lineage(conversation_id)

    %{
      "turn_scope_id" => List.last(pending_turns) && List.last(pending_turns).id,
      "recovery_count" => (current["recovery_count"] || 0) + 1,
      "cache_hits" => current["cache_hits"] || 0,
      "cache_misses" => current["cache_misses"] || 0,
      "replayed_tool_names" => current["replayed_tool_names"] || [],
      "latest_recovery_at" => DateTime.utc_now(),
      "latest_recovered_turn_ids" => Enum.map(pending_turns, & &1.id)
    }
  end

  defp update_recovery_lineage_cache_stats(
         conversation_id,
         cache_hits,
         cache_misses,
         tool_results
       ) do
    current = current_recovery_lineage(conversation_id)

    replayed_tool_names =
      tool_results
      |> Enum.filter(&(&1[:replayed] || false))
      |> Enum.map(& &1.tool_name)

    current
    |> Map.update("cache_hits", cache_hits, &((&1 || 0) + cache_hits))
    |> Map.update("cache_misses", cache_misses, &((&1 || 0) + cache_misses))
    |> Map.update("replayed_tool_names", replayed_tool_names, fn existing ->
      (existing || [])
      |> Kernel.++(replayed_tool_names)
      |> Enum.uniq()
    end)
    |> Map.put("last_cache_activity_at", DateTime.utc_now())
  end
end
