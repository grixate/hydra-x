defmodule HydraX.Repo.Migrations.AddBrowserToolControls do
  use Ecto.Migration

  def change do
    alter table(:hx_tool_policies) do
      add :browser_automation_enabled, :boolean, default: false, null: false
      add :browser_automation_channels_csv, :string, default: "", null: false
    end
  end
end
