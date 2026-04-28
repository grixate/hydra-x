defmodule HydraX.Repo.Migrations.AddLocalAuthToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :password_hash, :text
      add :operator_at, :utc_datetime_usec
    end

    create index(:users, [:operator_at])

    execute(
      "CREATE UNIQUE INDEX users_single_operator_index ON users ((operator_at IS NOT NULL)) WHERE operator_at IS NOT NULL",
      "DROP INDEX users_single_operator_index"
    )
  end
end
