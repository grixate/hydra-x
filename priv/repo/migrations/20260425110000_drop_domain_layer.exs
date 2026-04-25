defmodule HydraX.Repo.Migrations.DropDomainLayer do
  @moduledoc """
  Part 1 amendment: collapse the domain hierarchy.

  Removes the `domains` table and the `domain_id` column from every
  substrate table. Schema definitions become project-scoped: each
  project owns its own complete schema. Pretrained projects (Part 2)
  apply schema to a specific project; nothing global persists.

  Per spec §6 / §12, no data preservation. The schema-definition
  tables are wiped and rekeyed; existing nodes/relationships keep
  their `project_id` (added earlier) and just shed the now-unused
  `domain_id` column.
  """

  use Ecto.Migration

  def up do
    # ── Schema-definition tables — wipe + reseed under project_id ──
    execute "DELETE FROM schema_change_proposals"
    execute "DELETE FROM node_type_definitions"
    execute "DELETE FROM relationship_type_definitions"
    execute "DELETE FROM flag_type_definitions"

    drop constraint(:node_type_definitions, "node_type_definitions_domain_id_fkey")
    drop constraint(:relationship_type_definitions, "relationship_type_definitions_domain_id_fkey")
    drop constraint(:flag_type_definitions, "flag_type_definitions_domain_id_fkey")
    drop constraint(:schema_change_proposals, "schema_change_proposals_domain_id_fkey")

    drop_if_exists index(:node_type_definitions, [:domain_id, :type_key])
    drop_if_exists index(:node_type_definitions, [:extends])
    drop_if_exists index(:relationship_type_definitions, [:domain_id, :type_key])
    drop_if_exists index(:relationship_type_definitions, [:extends])
    drop_if_exists index(:flag_type_definitions, [:domain_id, :type_key])
    drop_if_exists index(:schema_change_proposals, [:domain_id])

    alter table(:node_type_definitions) do
      remove :domain_id
      add :project_id, references(:projects, on_delete: :delete_all), null: false
    end

    alter table(:relationship_type_definitions) do
      remove :domain_id
      add :project_id, references(:projects, on_delete: :delete_all), null: false
    end

    alter table(:flag_type_definitions) do
      remove :domain_id
      add :project_id, references(:projects, on_delete: :delete_all), null: false
    end

    alter table(:schema_change_proposals) do
      remove :domain_id
      add :project_id, references(:projects, on_delete: :delete_all), null: false
    end

    create unique_index(:node_type_definitions, [:project_id, :type_key])
    create index(:node_type_definitions, [:extends])
    create unique_index(:relationship_type_definitions, [:project_id, :type_key])
    create index(:relationship_type_definitions, [:extends])
    create unique_index(:flag_type_definitions, [:project_id, :type_key])
    create index(:schema_change_proposals, [:project_id])

    # ── nodes / node_relationships — drop FK + column only ──
    drop constraint(:nodes, "nodes_domain_id_fkey")
    drop constraint(:node_relationships, "node_relationships_domain_id_fkey")

    alter table(:nodes) do
      remove :domain_id
    end

    alter table(:node_relationships) do
      remove :domain_id
    end

    # ── domains table — drop entirely ──
    drop table(:domains)
  end

  def down do
    create table(:domains) do
      add :slug, :string, null: false
      add :name, :string, null: false
      add :version, :string, null: false, default: "0.1.0"
      add :status, :string, null: false, default: "active"
      add :source, :string, null: false, default: "builtin"
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:domains, [:slug])
    create index(:domains, [:status])

    alter table(:nodes) do
      add :domain_id, references(:domains, on_delete: :restrict)
    end

    alter table(:node_relationships) do
      add :domain_id, references(:domains, on_delete: :restrict)
    end

    drop_if_exists index(:node_type_definitions, [:project_id, :type_key])
    drop_if_exists index(:relationship_type_definitions, [:project_id, :type_key])
    drop_if_exists index(:flag_type_definitions, [:project_id, :type_key])
    drop_if_exists index(:schema_change_proposals, [:project_id])

    alter table(:node_type_definitions) do
      remove :project_id
      add :domain_id, references(:domains, on_delete: :delete_all)
    end

    alter table(:relationship_type_definitions) do
      remove :project_id
      add :domain_id, references(:domains, on_delete: :delete_all)
    end

    alter table(:flag_type_definitions) do
      remove :project_id
      add :domain_id, references(:domains, on_delete: :delete_all)
    end

    alter table(:schema_change_proposals) do
      remove :project_id
      add :domain_id, references(:domains, on_delete: :delete_all)
    end
  end
end
