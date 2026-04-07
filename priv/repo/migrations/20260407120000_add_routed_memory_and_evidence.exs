defmodule HydraX.Repo.Migrations.AddRoutedMemoryAndEvidence do
  use Ecto.Migration

  def change do
    alter table(:hx_memory_entries) do
      add :scope_kind, :string
      add :scope_key, :string
      add :hall, :string
      add :topic_key, :string
      add :valid_from, :utc_datetime_usec
      add :valid_to, :utc_datetime_usec
    end

    create index(:hx_memory_entries, [:agent_id, :scope_kind])
    create index(:hx_memory_entries, [:agent_id, :scope_key])
    create index(:hx_memory_entries, [:agent_id, :hall])
    create index(:hx_memory_entries, [:agent_id, :topic_key])
    create index(:hx_memory_entries, [:agent_id, :valid_from])
    create index(:hx_memory_entries, [:agent_id, :valid_to])

    create table(:hx_memory_evidence) do
      add :memory_id, references(:hx_memory_entries, on_delete: :delete_all)
      add :product_node_type, :string
      add :product_node_id, :integer
      add :source_kind, :string, null: false
      add :source_ref, :string
      add :excerpt, :text, null: false
      add :speaker_role, :string
      add :occurred_at, :utc_datetime_usec
      add :metadata, :map, default: %{}, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:hx_memory_evidence, [:memory_id])
    create index(:hx_memory_evidence, [:product_node_type, :product_node_id])
    create index(:hx_memory_evidence, [:source_kind])

    create unique_index(:hx_memory_evidence, [:memory_id, :source_kind, :source_ref, :excerpt],
             name: :hx_memory_evidence_dedupe_idx
           )
  end
end
