defmodule HydraX.Repo.Migrations.CreateAgentMcpServers do
  use Ecto.Migration

  def change do
    create table(:agent_mcp_servers) do
      add :agent_id, references(:agent_profiles, on_delete: :delete_all), null: false

      add :mcp_server_config_id, references(:mcp_server_configs, on_delete: :delete_all),
        null: false

      add :enabled, :boolean, null: false, default: true
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:agent_mcp_servers, [:agent_id, :mcp_server_config_id])
    create index(:agent_mcp_servers, [:agent_id, :enabled])
  end
end
