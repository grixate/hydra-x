defmodule HydraX.Tools.SwitchModel do
  @behaviour HydraX.Tool

  alias HydraX.Repo
  alias HydraX.Runtime
  alias HydraX.Runtime.{AgentProfile, Conversation, Providers}

  @impl true
  def name, do: "switch_model"

  @impl true
  def description,
    do: "Switch the LLM model used for subsequent messages in this conversation."

  @impl true
  def safety_classification, do: "runtime_config"

  @impl true
  def tool_schema do
    %{
      name: "switch_model",
      description:
        "Switch the LLM model for subsequent messages in this conversation. Use when the current task needs a different capability level (e.g. escalate to a more capable model for complex reasoning, drop to a cheaper model for routine edits). Returns the new model name on success.",
      input_schema: %{
        type: "object",
        properties: %{
          model: %{
            type: "string",
            description:
              "Model identifier matching an enabled provider config (e.g. \"claude-sonnet-4\", \"claude-haiku-4\"). Use `list_available_models` via the runtime if you're unsure."
          },
          reason: %{
            type: "string",
            description: "Short justification for the switch. Logged for cost analysis."
          }
        },
        required: ["model", "reason"]
      }
    }
  end

  @impl true
  def execute(params, _context) do
    conversation_id = params[:conversation_id] || params["conversation_id"]
    model = params[:model] || params["model"]
    reason = params[:reason] || params["reason"]

    cond do
      not is_integer(conversation_id) ->
        {:error, :missing_conversation_id}

      not (is_binary(model) and model != "") ->
        {:error, :missing_model}

      not (is_binary(reason) and reason != "") ->
        {:error, :missing_reason}

      true ->
        with :ok <- check_allowlist(conversation_id, model),
             provider when not is_nil(provider) <- Providers.find_provider_by_model(model) do
          case apply_override(conversation_id, provider, reason) do
              {:ok, _conv} ->
                require Logger

                Logger.info(
                  "switch_model: conversation=#{conversation_id} model=#{model} reason=#{inspect(reason)}"
                )

                {:ok,
                 %{
                   model: model,
                   provider_id: provider.id,
                   provider_name: provider.name,
                   reason: reason
                 }}

              {:error, reason} ->
                {:error, reason}
            end
        else
          nil ->
            {:error, {:model_not_available, model, Providers.list_available_models()}}

          {:error, {:model_not_allowed, _, _}} = err ->
            err
        end
    end
  end

  # Returns :ok if the model is allowed for the conversation's agent.
  # Agents without an `allowed_models` entry on runtime_state have no
  # restriction — any enabled provider is valid.
  defp check_allowlist(conversation_id, model) do
    with %Conversation{agent_id: agent_id} <- Repo.get(Conversation, conversation_id),
         %AgentProfile{runtime_state: runtime_state} <-
           Repo.get(AgentProfile, agent_id) do
      case get_in(runtime_state || %{}, ["allowed_models"]) do
        nil -> :ok
        [] -> :ok
        list when is_list(list) ->
          if model in list do
            :ok
          else
            {:error, {:model_not_allowed, model, list}}
          end

        _ -> :ok
      end
    else
      _ -> :ok
    end
  end

  defp apply_override(conversation_id, provider, reason) do
    case HydraX.Repo.get(Conversation, conversation_id) do
      nil ->
        {:error, :conversation_not_found}

      %Conversation{} = conv ->
        Runtime.update_conversation_metadata(conv, %{
          "model_override_provider_id" => provider.id,
          "model_override_model" => provider.model,
          "model_override_reason" => reason,
          "model_override_set_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        })
    end
  end

  @impl true
  def result_summary(%{model: model, reason: reason}),
    do: "switched model → #{model} (#{String.slice(reason, 0, 40)})"

  def result_summary(%{error: error}) when is_binary(error), do: error
  def result_summary(payload), do: inspect(payload, limit: 8, printable_limit: 120)
end
