defmodule HydraX.Repo.Migrations.CreateWhyProseCache do
  @moduledoc """
  Why-button prose cache per spec §6. One row per (node, lineage-hash) key.
  Invalidated by recomputing the cache key — no explicit delete needed.
  """

  use Ecto.Migration

  def change do
    create table(:why_prose_cache) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :node_type, :string, null: false
      add :node_id, :integer, null: false
      add :cache_key, :string, null: false
      add :prose, :text, null: false
      add :model_id, :string
      add :generated_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:why_prose_cache, [:project_id, :node_type, :node_id, :cache_key])
    create index(:why_prose_cache, [:project_id, :generated_at])
  end
end
