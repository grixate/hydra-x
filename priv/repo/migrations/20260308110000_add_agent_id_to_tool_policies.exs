defmodule HydraX.Repo.Migrations.AddAgentIdToToolPolicies do
  use Ecto.Migration

  def change do
    alter table(:tool_policies) do
      add :agent_id, references(:agent_profiles, on_delete: :delete_all)
    end

    # Replace the old unique on :scope with a composite unique on {:scope, :agent_id}.
    # NULL agent_id represents the global default policy.
    drop_if_exists unique_index(:tool_policies, [:scope])
    create unique_index(:tool_policies, [:scope, :agent_id])
  end
end
