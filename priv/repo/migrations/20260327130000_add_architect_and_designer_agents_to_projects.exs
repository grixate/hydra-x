defmodule HydraX.Repo.Migrations.AddArchitectAndDesignerAgentsToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :architect_agent_id,
          references(:hx_agent_profiles, on_delete: :nilify_all)

      add :designer_agent_id,
          references(:hx_agent_profiles, on_delete: :nilify_all)
    end

    create index(:projects, [:architect_agent_id])
    create index(:projects, [:designer_agent_id])
  end
end
