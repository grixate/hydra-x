defmodule HydraX.Repo.Migrations.AddCoderAgentToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :coder_agent_id, references(:hx_agent_profiles, on_delete: :nilify_all)
    end

    create index(:projects, [:coder_agent_id])
  end
end
