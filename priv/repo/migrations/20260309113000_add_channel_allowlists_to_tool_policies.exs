defmodule HydraX.Repo.Migrations.AddChannelAllowlistsToToolPolicies do
  use Ecto.Migration

  def change do
    alter table(:tool_policies) do
      add :workspace_write_channels_csv, :text, null: false, default: ""
      add :http_fetch_channels_csv, :text, null: false, default: ""
      add :web_search_channels_csv, :text, null: false, default: ""
      add :shell_command_channels_csv, :text, null: false, default: ""
    end
  end
end
