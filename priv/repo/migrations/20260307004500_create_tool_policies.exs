defmodule HydraX.Repo.Migrations.CreateToolPolicies do
  use Ecto.Migration

  def change do
    create table(:tool_policies) do
      add :scope, :string, null: false
      add :workspace_read_enabled, :boolean, null: false, default: true
      add :http_fetch_enabled, :boolean, null: false, default: true
      add :shell_command_enabled, :boolean, null: false, default: true
      add :shell_allowlist_csv, :text, null: false, default: ""
      add :http_allowlist_csv, :text, null: false, default: ""

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tool_policies, [:scope])
  end
end
