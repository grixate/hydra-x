defmodule HydraX.Repo.Migrations.AddLockVersionToAgentTasks do
  use Ecto.Migration

  def change do
    alter table(:agent_tasks) do
      add :lock_version, :integer, null: false, default: 1
    end
  end
end
