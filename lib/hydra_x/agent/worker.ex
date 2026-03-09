defmodule HydraX.Agent.Worker do
  @moduledoc false
  @behaviour :gen_statem

  alias HydraX.Runtime
  alias HydraX.Safety
  alias HydraX.Telemetry
  alias HydraX.Tool.Registry

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

  @doc """
  Execute a list of tool calls from the LLM response.
  Returns a list of `%{tool_use_id, tool_name, result}` maps.
  """
  def execute_tool_calls(agent_id, conversation, tool_calls) do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        HydraX.Agent.worker_supervisor(agent_id),
        {__MODULE__, %{conversation: conversation, tool_calls: tool_calls}}
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
        %{conversation: conversation, tool_calls: tool_calls} = data
      ) do
    agent = Runtime.get_agent!(conversation.agent_id)
    tool_policy = Runtime.effective_tool_policy(agent.id)

    context = %{
      workspace_root: agent.workspace_root,
      http_allowlist: tool_policy.http_allowlist,
      shell_allowlist: tool_policy.shell_allowlist,
      agent_id: conversation.agent_id,
      conversation_id: conversation.id,
      current_channel: conversation.channel
    }

    results =
      Enum.map(tool_calls, fn tool_call ->
        execute_single(tool_call, context, conversation, tool_policy)
      end)

    {:stop_and_reply, :normal, [{:reply, from, results}], data}
  end

  def handle_event(_type, _event, _state, data), do: {:keep_state, data}

  defp execute_single(
         %{id: id, name: name, arguments: arguments},
         context,
         conversation,
         tool_policy
       ) do
    case Registry.find_tool(name) do
      nil ->
        %{
          tool_use_id: id,
          tool_name: name,
          result: %{error: "Unknown tool: #{name}"},
          is_error: true
        }

      tool_module ->
        if tool_enabled?(tool_module, tool_policy, conversation.channel) do
          params = enrich_params(arguments, name, context)

          case tool_module.execute(params, context) do
            {:ok, result} ->
              Telemetry.tool_execution(name, :ok)
              %{tool_use_id: id, tool_name: name, result: result, is_error: false}

            {:error, reason} ->
              log_tool_warning(conversation, name, arguments, reason)

              %{
                tool_use_id: id,
                tool_name: name,
                result: %{error: inspect(reason)},
                is_error: true
              }
          end
        else
          log_tool_warning(conversation, name, arguments, :tool_disabled)

          %{
            tool_use_id: id,
            tool_name: name,
            result: %{error: "Tool #{name} is disabled by policy"},
            is_error: true
          }
        end
    end
  end

  defp tool_enabled?(module, policy) do
    case module.name() do
      "workspace_list" -> Map.get(policy, :workspace_list_enabled, true)
      "workspace_read" -> Map.get(policy, :workspace_read_enabled, true)
      "http_fetch" -> Map.get(policy, :http_fetch_enabled, true)
      "web_search" -> Map.get(policy, :web_search_enabled, true)
      "shell_command" -> Map.get(policy, :shell_command_enabled, true)
      "workspace_write" -> Map.get(policy, :workspace_write_enabled, false)
      "workspace_patch" -> Map.get(policy, :workspace_write_enabled, false)
      _ -> true
    end
  end

  defp tool_enabled?(module, policy, channel) do
    case module.name() do
      "workspace_write" ->
        Map.get(policy, :workspace_write_enabled, false) and
          channel_allowed?(channel, Map.get(policy, :workspace_write_channels, []))

      "workspace_patch" ->
        Map.get(policy, :workspace_write_enabled, false) and
          channel_allowed?(channel, Map.get(policy, :workspace_write_channels, []))

      "http_fetch" ->
        Map.get(policy, :http_fetch_enabled, true) and
          channel_allowed?(channel, Map.get(policy, :http_fetch_channels, []))

      "web_search" ->
        Map.get(policy, :web_search_enabled, true) and
          channel_allowed?(channel, Map.get(policy, :web_search_channels, []))

      "shell_command" ->
        Map.get(policy, :shell_command_enabled, true) and
          channel_allowed?(channel, Map.get(policy, :shell_command_channels, []))

      _ ->
        tool_enabled?(module, policy)
    end
  end

  defp enrich_params(arguments, "memory_save", context) do
    arguments
    |> Map.put(:agent_id, context.agent_id)
    |> Map.put(:conversation_id, context.conversation_id)
  end

  defp enrich_params(arguments, "memory_recall", context) do
    Map.put(arguments, :agent_id, context.agent_id)
  end

  defp enrich_params(arguments, _name, _context), do: arguments

  defp log_tool_warning(conversation, tool_name, params, reason) do
    Telemetry.tool_execution(tool_name, :error, %{reason: inspect(reason)})

    Safety.log_event(%{
      agent_id: conversation.agent_id,
      conversation_id: conversation.id,
      category: "tool",
      level: "warn",
      message: "#{tool_name} blocked or failed",
      metadata: %{
        tool: tool_name,
        params: params,
        reason: inspect(reason)
      }
    })
  end

  defp channel_allowed?(channel, channels) when is_binary(channel) and is_list(channels),
    do: channel in channels

  defp channel_allowed?(_, _), do: false
end
