defmodule HydraX.Repo.Migrations.AddStatusToMemoryEntries do
  use Ecto.Migration

  def change do
    alter table(:hx_memory_entries) do
      add :status, :string, null: false, default: "active"
    end

    create index(:hx_memory_entries, [:agent_id, :status])
  end
end
