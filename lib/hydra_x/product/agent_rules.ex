defmodule HydraX.Product.AgentRules do
  @moduledoc """
  Context for per-agent, per-project rules that tune background agents
  (Coherence, Continuous Research).

  Rules apply at detection time, not read time — so newly-created rules do
  not retroactively affect existing findings.
  """

  import Ecto.Query, warn: false
  alias HydraX.Repo
  alias HydraX.Product.AgentRule

  def list_rules(project_id, agent_id) do
    AgentRule
    |> where([r], r.project_id == ^project_id and r.agent_id == ^agent_id)
    |> order_by([r], asc: r.rule_type, asc: r.value)
    |> Repo.all()
  end

  def create_rule(project_id, agent_id, attrs) do
    %AgentRule{}
    |> AgentRule.changeset(Map.merge(attrs, %{project_id: project_id, agent_id: agent_id}))
    |> Repo.insert()
  end

  def delete_rule(project_id, id) do
    case Repo.get_by(AgentRule, id: id, project_id: project_id) do
      nil -> {:error, :not_found}
      rule -> Repo.delete(rule)
    end
  end

  @doc """
  Return a map of rule_type => MapSet of values for quick lookup during
  detection.
  """
  def rules_index(project_id, agent_id) do
    list_rules(project_id, agent_id)
    |> Enum.group_by(& &1.rule_type, & &1.value)
    |> Map.new(fn {k, vs} -> {k, MapSet.new(vs)} end)
  end

  @doc """
  Given an index and a category string, return true if the category is
  muted for the agent.
  """
  def muted?(%{} = index, category) do
    MapSet.member?(Map.get(index, "mute_category", MapSet.new()), to_string(category))
  end

  @doc """
  Given an index and a free-text value, return true if any configured
  ignore_pattern substring matches.
  """
  def ignored?(%{} = index, text) when is_binary(text) do
    patterns = Map.get(index, "ignore_pattern", MapSet.new())

    Enum.any?(patterns, fn pat ->
      String.contains?(String.downcase(text), String.downcase(pat))
    end)
  end

  def ignored?(_index, _), do: false
end
