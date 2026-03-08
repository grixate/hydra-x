defmodule HydraX.Repo.Migrations.AddMoreToolPolicyControls do
  use Ecto.Migration

  def change do
    alter table(:tool_policies) do
      add :workspace_list_enabled, :boolean, default: true, null: false
      add :workspace_write_enabled, :boolean, default: false, null: false
      add :web_search_enabled, :boolean, default: true, null: false
    end
  end
end
