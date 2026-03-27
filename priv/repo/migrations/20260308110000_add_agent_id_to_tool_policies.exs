defmodule HydraX.Repo.Migrations.AddAgentIdToToolPolicies do
  use Ecto.Migration

  def change do
    alter table(:hx_tool_policies) do
      add :agent_id, references(:hx_agent_profiles, on_delete: :delete_all)
    end

    # Replace the old unique on :scope with a composite unique on {:scope, :agent_id}.
    # NULL agent_id represents the global default policy.
    drop_if_exists unique_index(:hx_tool_policies, [:scope])
    create unique_index(:hx_tool_policies, [:scope, :agent_id])
  end
end
