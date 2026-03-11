defmodule HydraX.Repo.Migrations.CreateCoordinationLeases do
  use Ecto.Migration

  def change do
    create table(:coordination_leases) do
      add :name, :string, null: false
      add :owner, :string, null: false
      add :owner_node, :string, null: false
      add :lease_type, :string, null: false, default: "exclusive"
      add :expires_at, :utc_datetime_usec, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:coordination_leases, [:name])
    create index(:coordination_leases, [:expires_at])
  end
end
