defmodule HydraX.Repo.Migrations.CreateMcpServerConfigs do
  use Ecto.Migration

  def change do
    create table(:hx_mcp_server_configs) do
      add :name, :string, null: false
      add :transport, :string, null: false
      add :command, :string
      add :args_csv, :string
      add :cwd, :string
      add :url, :string
      add :healthcheck_path, :string, default: "/health"
      add :auth_token, :text
      add :enabled, :boolean, null: false, default: true
      add :retry_limit, :integer, null: false, default: 2
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:hx_mcp_server_configs, [:enabled])
  end
end
