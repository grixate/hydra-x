defmodule HydraX.Repo.Migrations.CreateWorkspaceEvents do
  use Ecto.Migration

  def change do
    create table(:hx_workspace_events) do
      add :workspace_id, references(:hx_product_workspaces, on_delete: :delete_all), null: false
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :path, :text
      add :command, :map
      add :exit_code, :integer
      add :outcome, :string, null: false
      add :error, :text
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:hx_workspace_events, [:workspace_id])
    create index(:hx_workspace_events, [:project_id, :inserted_at])
    create index(:hx_workspace_events, [:kind])
  end
end
