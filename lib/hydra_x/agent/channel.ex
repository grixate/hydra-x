defmodule HydraX.Agent.Channel do
  @moduledoc false
  @behaviour :gen_statem

  alias HydraX.Agent.{Compactor, Planner, PromptBuilder, Worker}
  alias HydraX.Budget
  alias HydraX.Cluster
  alias HydraX.Config
  alias HydraX.LLM.Router
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

    pending_turns = resumable_pending_turns(conversation.id, turns)
    recovered? = pending_turns != []

    data =
      %{
        agent_id: agent_id,
        conversation: conversation,
        turns: turns,
        coalesce_buffer: pending_turns,
        pending_from: []
      }

    if recovered? do
      append_channel_event(conversation.id, "recovered_after_restart", %{
        "summary" =>
          "Recovered #{length(pending_turns)} pending user turn(s) after channel restart",
        "pending_turn_ids" => Enum.map(pending_turns, & &1.id)
      })

      update_channel_checkpoint(conversation.id, %{
        "status" => "interrupted",
        "resumable" => true,
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
      "plan" => plan,
      "steps" => plan["steps"] || [],
      "tool_cache" =>
        tool_cache_for_turn(data.conversation.id, latest_turn_id(data.coalesce_buffer)),
      "tool_cache_scope_turn_id" => latest_turn_id(data.coalesce_buffer),
      "current_step_id" => step_id_for_status(plan["steps"] || [], "pending"),
      "current_step_index" => step_index_for_status(plan["steps"] || [], "pending"),
      "resumable" => true,
      "latest_user_turn_id" => latest_turn_id(data.coalesce_buffer),
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

      {response_content, response_metadata} ->
        {:ok, assistant_turn} =
          Runtime.append_turn(data.conversation, %{
            role: "assistant",
            kind: "message",
            content: response_content,
            metadata: response_metadata
          })

        update_channel_checkpoint(data.conversation.id, %{
          "status" => "completed",
          "steps" => current_checkpoint_steps(data.conversation.id),
          "current_step_id" => nil,
          "current_step_index" => nil,
          "resumable" => false,
          "assistant_turn_id" => assistant_turn.id,
          "provider" => response_metadata[:provider] || response_metadata["provider"],
          "tool_rounds" =>
            response_metadata[:tool_rounds] || response_metadata["tool_rounds"] || 0,
          "tool_results" =>
            summarize_tool_results(
              response_metadata[:tool_results] || response_metadata["tool_results"] || []
            ),
          "updated_at" => DateTime.utc_now()
        })

        Enum.each(data.pending_from, &:gen_statem.reply(&1, assistant_turn.content))
        Compactor.review(data.agent_id, data.conversation.id)

        Phoenix.PubSub.broadcast(
          HydraX.PubSub,
          "conversations",
          {:conversation_updated, data.conversation.id}
        )

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
        %{
          content: "Streaming failed. Check /health and provider settings.",
          provider: "stream-error"
        },
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
        updated_steps =
          tool_calls
          |> Enum.reduce(current_checkpoint_steps(data.conversation.id), fn tool_call, steps ->
            mark_step_running(steps, "tool", tool_call.name)
          end)

        append_channel_event(data.conversation.id, "provider_tool_request", %{
          "round" => round + 1,
          "provider" => response.provider,
          "tool_count" => length(tool_calls)
        })

        {tool_results, cache_hits, cache_misses} =
          execute_tool_calls_with_cache(data, tool_calls)

        update_channel_checkpoint(data.conversation.id, %{
          "status" => "executing_tools",
          "steps" => complete_tool_steps(updated_steps, tool_results),
          "current_step_id" =>
            current_step_id_after_tools(complete_tool_steps(updated_steps, tool_results)),
          "current_step_index" =>
            current_step_index_after_tools(complete_tool_steps(updated_steps, tool_results)),
          "resumable" => true,
          "tool_rounds" => round + 1,
          "active_tool_calls" =>
            Enum.map(tool_calls, fn call ->
              %{"id" => call.id, "name" => call.name}
            end),
          "tool_cache" => merge_tool_cache(data.conversation.id, tool_results),
          "tool_results" => summarize_tool_results(all_tool_results ++ tool_results),
          "updated_at" => DateTime.utc_now()
        })

        if cache_hits > 0 do
          append_channel_event(data.conversation.id, "tool_cache_hit", %{
            "round" => round + 1,
            "cache_hits" => cache_hits,
            "cache_misses" => cache_misses
          })
        end

        Enum.each(tool_results, fn result ->
          append_channel_event(data.conversation.id, "tool_result", %{
            "round" => round + 1,
            "tool_name" => result.tool_name,
            "is_error" => result[:is_error] || false,
            "cached" => result[:cached] || false,
            "summary" => result[:summary] || summarize_tool_result_payload(result.result),
            "safety_classification" => result[:safety_classification] || "standard"
          })
        end)

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
        steps =
          current_checkpoint_steps(data.conversation.id)
          |> mark_provider_running(%{"summary" => "Waiting for final provider response"})
          |> mark_provider_completed(%{
            "summary" => "Final response generated",
            "output_excerpt" => excerpt_text(response.content || ""),
            "provider" => response.provider,
            "stop_reason" => response.stop_reason
          })

        append_channel_event(data.conversation.id, "provider_completed", %{
          "round" => round,
          "provider" => response.provider,
          "stop_reason" => response.stop_reason,
          "content_length" => String.length(response.content || "")
        })

        update_channel_checkpoint(data.conversation.id, %{
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
                "steps" => steps,
                "current_step_id" => step_id_for_running(steps),
                "current_step_index" => step_index_for_running(steps),
                "resumable" => true,
                "updated_at" => DateTime.utc_now()
              })

              append_channel_event(data.conversation.id, "stream_started", %{
                "provider" => provider_name(data.agent_id),
                "estimated_input_tokens" => estimated_input_tokens,
                "round" => round
              })

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

    {:ok, assistant_turn} =
      Runtime.append_turn(data.conversation, %{
        role: "assistant",
        kind: "message",
        content: content,
        metadata: metadata
      })

    update_channel_checkpoint(data.conversation.id, %{
      "status" => "completed",
      "steps" =>
        current_checkpoint_steps(data.conversation.id)
        |> mark_provider_completed(%{
          "summary" => "Streamed response completed",
          "output_excerpt" => excerpt_text(content),
          "provider" => response.provider
        }),
      "current_step_id" => nil,
      "current_step_index" => nil,
      "resumable" => false,
      "assistant_turn_id" => assistant_turn.id,
      "provider" => response.provider,
      "tool_rounds" => round,
      "tool_results" => summarize_tool_results(all_tool_results),
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

  defp provider_name(agent_id) do
    case Runtime.enabled_provider(agent_id, "channel") do
      nil -> "mock"
      provider -> provider.name || provider.kind || "configured"
    end
  end

  defp prompt_tools(tool_policy), do: HydraX.Tool.Registry.available_schemas(tool_policy)

  defp latest_turn_id([]), do: nil
  defp latest_turn_id(turns), do: turns |> List.last() |> then(&(&1 && &1.id))

  defp update_channel_checkpoint(conversation_id, attrs) do
    existing = Runtime.get_checkpoint(conversation_id, "channel")
    state = Map.merge((existing && existing.state) || %{}, attrs)
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

    if state["status"] in ["planned", "executing_tools", "streaming", "interrupted"] and
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
            Map.put(result, :fingerprint, Map.fetch!(fingerprints, result.tool_use_id))
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
      fingerprint: entry["fingerprint"],
      summary: entry["summary"],
      safety_classification: entry["safety_classification"]
    }
  end

  defp merge_tool_cache(conversation_id, results) do
    existing =
      current_tool_cache(conversation_id)
      |> Map.new(fn entry -> {entry["fingerprint"], entry} end)

    results
    |> Enum.reduce(existing, fn result, acc ->
      Map.put(
        acc,
        tool_result_cache_entry(result)["fingerprint"],
        tool_result_cache_entry(result)
      )
    end)
    |> Map.values()
  end

  defp tool_result_cache_entry(result) do
    %{
      "fingerprint" => result[:fingerprint],
      "tool_name" => result.tool_name,
      "result" => result.result,
      "is_error" => result[:is_error] || false,
      "summary" => result[:summary],
      "safety_classification" => result[:safety_classification] || "standard",
      "cached_at" => DateTime.utc_now()
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
            "attempt_count" => 0
          }
          |> transition_step("running")
          |> Map.put("summary", "Executing #{tool_name}")
        ]
    end
  end

  defp complete_tool_steps(steps, tool_results) do
    Enum.reduce(tool_results, steps, fn result, acc ->
      update_matching_step(acc, "tool", result.tool_name, fn step ->
        step
        |> transition_step(if(result[:is_error] || false, do: "failed", else: "completed"))
        |> Map.put("summary", result[:summary] || summarize_tool_result_payload(result.result))
        |> Map.put("output_excerpt", tool_result_excerpt(result.result))
        |> Map.put("cached", result[:cached] || false)
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
            "attempt_count" => 0
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
        "summary" => result[:summary] || summarize_tool_result_payload(result.result),
        "safety_classification" => result[:safety_classification] || "standard"
      }
    end)
  end

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
  defp tool_result_excerpt(%{"content" => content}) when is_binary(content), do: excerpt_text(content)
  defp tool_result_excerpt(%{text: text}) when is_binary(text), do: excerpt_text(text)
  defp tool_result_excerpt(%{"text" => text}) when is_binary(text), do: excerpt_text(text)
  defp tool_result_excerpt(%{results: results}) when is_list(results), do: "#{length(results)} results"
  defp tool_result_excerpt(%{"results" => results}) when is_list(results), do: "#{length(results)} results"
  defp tool_result_excerpt(%{skills: skills}) when is_list(skills), do: "#{length(skills)} skills"
  defp tool_result_excerpt(%{"skills" => skills}) when is_list(skills), do: "#{length(skills)} skills"
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
end
