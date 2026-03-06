defmodule HydraX.Repo.Migrations.AddOperatorAuth do
  use Ecto.Migration

  def change do
    create table(:operator_secrets) do
      add :scope, :string, null: false, default: "control_plane"
      add :password_hash, :text, null: false
      add :password_salt, :text, null: false
      add :last_rotated_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:operator_secrets, [:scope])
  end
end
