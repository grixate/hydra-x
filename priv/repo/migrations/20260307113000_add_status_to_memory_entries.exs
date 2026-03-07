defmodule HydraX.Repo.Migrations.AddStatusToMemoryEntries do
  use Ecto.Migration

  def change do
    alter table(:memory_entries) do
      add :status, :string, null: false, default: "active"
    end

    create index(:memory_entries, [:agent_id, :status])
  end
end
