defmodule HydraX.Runtime.Helpers do
  @moduledoc false

  import Ecto.Query

  alias HydraX.Repo
  alias HydraX.Runtime.AgentProfile

  def normalize_string_keys(attrs) do
    Enum.reduce(attrs, %{}, fn
      {key, value}, acc when is_atom(key) -> Map.put(acc, Atom.to_string(key), value)
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end

  def blank_to_nil(nil), do: nil
  def blank_to_nil(""), do: nil
  def blank_to_nil(value), do: value

  def unwrap_transaction({:ok, value}), do: {:ok, value}
  def unwrap_transaction({:error, reason}), do: {:error, reason}

  def audit_operator_action(message, opts) do
    audit_event("operator", "info", message, opts)
  end

  def audit_auth_action(message, opts) do
    audit_event("auth", Keyword.get(opts, :level, "info"), message, opts)
  end

  defp audit_event(category, level, message, opts) do
    case resolve_audit_agent(opts) do
      nil ->
        :ok

      agent ->
        HydraX.Safety.log_event(%{
          agent_id: agent.id,
          conversation_id: Keyword.get(opts, :conversation_id),
          category: category,
          level: level,
          message: message,
          metadata: Keyword.get(opts, :metadata, %{})
        })

        :ok
    end
  end

  defp resolve_audit_agent(opts) do
    cond do
      match?(%AgentProfile{}, Keyword.get(opts, :agent)) ->
        Keyword.get(opts, :agent)

      is_integer(Keyword.get(opts, :agent_id)) ->
        Repo.get(AgentProfile, Keyword.get(opts, :agent_id))

      true ->
        Repo.one(from(agent in AgentProfile, where: agent.is_default == true, limit: 1)) ||
          Repo.one(
            from(agent in AgentProfile,
              order_by: [desc: agent.is_default, asc: agent.name],
              limit: 1
            )
          )
    end
  end
end
