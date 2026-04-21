defmodule HydraX.Repo.Migrations.AddSourceAsData do
  @moduledoc """
  Cycle 3 — Source-as-Data Architecture.

  Sources live in the Library as queryable data, not as graph nodes by default.
  Only promoted sources appear in the graph. References between graph nodes
  and sources are stored in a polymorphic `source_references` table so queries
  like "sources cited by Decisions in the last 30 days" are efficient.

  Migration is conservative per spec §7: existing Source graph nodes stay
  promoted. Users can demote them via the new promotion UI.
  """

  use Ecto.Migration

  def up do
    # Promotion state on sources themselves. Conservative default: legacy rows
    # keep graph visibility.
    alter table(:sources) do
      add :promoted_to_graph, :boolean, null: false, default: false
      add :promoted_at, :utc_datetime_usec
      add :archived_at, :utc_datetime_usec
    end

    # Treat every pre-existing source as promoted so its graph edges keep
    # working until a user curates it.
    execute("UPDATE sources SET promoted_to_graph = TRUE, promoted_at = inserted_at")

    create index(:sources, [:project_id, :promoted_to_graph])
    create index(:sources, [:project_id, :archived_at])

    # Polymorphic references — which graph nodes cite which sources.
    create table(:source_references) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :source_id, references(:sources, on_delete: :delete_all), null: false
      add :node_type, :string, null: false
      add :node_id, :integer, null: false
      add :relationship, :string, null: false, default: "cites"
      add :excerpt, :text
      add :confidence, :string
      add :page_or_position, :string
      add :created_by, :string, default: "agent"
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:source_references, [:project_id])
    create index(:source_references, [:source_id])
    create index(:source_references, [:node_type, :node_id])
    create index(:source_references, [:project_id, :node_type, :node_id])

    create unique_index(
             :source_references,
             [:source_id, :node_type, :node_id, :relationship],
             name: :source_refs_source_node_rel_idx
           )
  end

  def down do
    drop table(:source_references)

    drop_if_exists index(:sources, [:project_id, :promoted_to_graph])
    drop_if_exists index(:sources, [:project_id, :archived_at])

    alter table(:sources) do
      remove :promoted_to_graph
      remove :promoted_at
      remove :archived_at
    end
  end
end
