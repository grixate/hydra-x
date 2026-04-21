defmodule HydraX.Repo.Migrations.CreateProductWorkspaces do
  use Ecto.Migration

  def change do
    create table(:hx_product_workspaces) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :fs_path, :text, null: false
      add :sandbox_mode, :string, null: false, default: "host"
      add :container_id, :string
      add :status, :string, null: false, default: "provisioning"
      add :git_origin, :text
      add :last_used_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:hx_product_workspaces, [:project_id])
    create index(:hx_product_workspaces, [:status])
  end
end
