defmodule HydraX.Repo.Migrations.MigrateSourcesToSubstrate do
  @moduledoc """
  Phase 1g of the substrate cutover. Drops `sources`. Source rows move
  to `nodes` under `type_key: "source"`. Two child tables repoint at
  `nodes.id`:

  - `source_chunks.source_id` (direct FK)
  - `source_references.source_id` (direct FK; its own `reference_type`/
    `reference_id` polymorphic columns are left untouched — any of the
    already-ported types it references now point to the `nodes` table,
    and substrate-aware callers filter by `reference_type` anyway).

  Per spec §12 no data preservation — existing source rows and child
  rows are dropped; ingestion re-creates them.
  """

  use Ecto.Migration

  def up do
    # Child tables: clear data before repointing FK.
    execute "DELETE FROM source_chunks"
    execute "DELETE FROM source_references"
    execute "DELETE FROM insight_evidence"

    drop constraint(:source_chunks, "source_chunks_source_id_fkey")
    drop constraint(:source_references, "source_references_source_id_fkey")

    alter table(:source_chunks) do
      modify :source_id,
             references(:nodes, on_delete: :delete_all),
             null: false,
             from: {:integer, []}
    end

    alter table(:source_references) do
      modify :source_id,
             references(:nodes, on_delete: :delete_all),
             null: false,
             from: {:integer, []}
    end

    drop table(:sources)
  end

  def down do
    create table(:sources) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :source_type, :string, null: false
      add :content, :text
      add :external_ref, :string
      add :processing_status, :string, null: false, default: "pending"
      add :reviewed_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}
      add :promoted_to_graph, :boolean, null: false, default: false
      add :promoted_at, :utc_datetime_usec
      add :archived_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:sources, [:project_id])
    create index(:sources, [:processing_status])

    drop constraint(:source_chunks, "source_chunks_source_id_fkey")
    drop constraint(:source_references, "source_references_source_id_fkey")

    alter table(:source_chunks) do
      modify :source_id, references(:sources, on_delete: :delete_all), null: false
    end

    alter table(:source_references) do
      modify :source_id, references(:sources, on_delete: :delete_all), null: false
    end
  end
end
