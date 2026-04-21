defmodule HydraX.Repo.Migrations.CreateAgentRules do
  use Ecto.Migration

  def change do
    create table(:agent_rules) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :agent_id, :string, null: false
      add :rule_type, :string, null: false
      add :value, :string, null: false

      timestamps()
    end

    create index(:agent_rules, [:project_id, :agent_id])
    create unique_index(:agent_rules, [:project_id, :agent_id, :rule_type, :value])
  end
end
