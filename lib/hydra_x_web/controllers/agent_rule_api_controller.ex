defmodule HydraXWeb.AgentRuleAPIController do
  use HydraXWeb, :controller

  alias HydraX.Product.AgentRules

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def index(conn, %{"project_id" => project_id, "agent_id" => agent_id}) do
    rules = AgentRules.list_rules(project_id, agent_id)
    json(conn, %{data: Enum.map(rules, &to_json/1)})
  end

  def create(conn, %{"project_id" => project_id, "agent_id" => agent_id} = params) do
    attrs = %{
      rule_type: params["rule_type"],
      value: params["value"]
    }

    case AgentRules.create_rule(project_id, agent_id, attrs) do
      {:ok, rule} ->
        conn
        |> put_status(:created)
        |> json(%{data: to_json(rule)})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "invalid", details: error_messages(changeset)})
    end
  end

  def delete(conn, %{"project_id" => project_id, "id" => id}) do
    case AgentRules.delete_rule(project_id, id) do
      {:ok, _} ->
        send_resp(conn, :no_content, "")

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})
    end
  end

  defp to_json(rule) do
    %{
      id: rule.id,
      project_id: rule.project_id,
      agent_id: rule.agent_id,
      rule_type: rule.rule_type,
      value: rule.value,
      inserted_at: rule.inserted_at,
      updated_at: rule.updated_at
    }
  end

  defp error_messages(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
  end
end
