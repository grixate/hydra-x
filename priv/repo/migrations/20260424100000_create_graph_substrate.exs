defmodule HydraX.Repo.Migrations.CreateGraphSubstrate do
  @moduledoc """
  Phase 1 of the domain-extensibility substrate. Introduces the
  generic node / relationship / flag tables plus the schema-definition
  tables that replace hardcoded Ecto schemas.

  See `docs/specs/hydra-domain-extensibility-part-1-schema-substrate.md`.

  This migration is additive — existing typed tables (insights, decisions,
  product_graph_edges, etc.) are untouched. A later migration will drop
  them once all call sites move to the substrate.
  """

  use Ecto.Migration

  def change do
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

    create table(:node_type_definitions) do
      add :domain_id, references(:domains, on_delete: :delete_all), null: false
      add :type_key, :string, null: false
      add :display_name, :string, null: false
      add :description, :text
      add :extends, :string
      add :attribute_schema, :map, null: false, default: %{}
      add :status_vocabulary, {:array, :string}, null: false, default: []
      add :promotion_sources, {:array, :string}, null: false, default: []
      add :icon, :string
      add :color_token, :string
      add :version, :integer, null: false, default: 1

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:node_type_definitions, [:domain_id, :type_key])
    create index(:node_type_definitions, [:extends])

    create table(:relationship_type_definitions) do
      add :domain_id, references(:domains, on_delete: :delete_all), null: false
      add :type_key, :string, null: false
      add :display_name, :string, null: false
      add :description, :text
      add :extends, :string
      add :valid_from_types, {:array, :string}, null: false, default: ["*"]
      add :valid_to_types, {:array, :string}, null: false, default: ["*"]
      add :cardinality, :string, null: false, default: "many_to_many"
      add :directional, :boolean, null: false, default: true
      add :attribute_schema, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:relationship_type_definitions, [:domain_id, :type_key])
    create index(:relationship_type_definitions, [:extends])

    create table(:flag_type_definitions) do
      add :domain_id, references(:domains, on_delete: :delete_all), null: false
      add :type_key, :string, null: false
      add :display_name, :string, null: false
      add :description, :text
      add :default_severity, :string, null: false, default: "warning"

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:flag_type_definitions, [:domain_id, :type_key])

    create table(:nodes) do
      add :domain_id, references(:domains, on_delete: :restrict), null: false
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :type_key, :string, null: false
      add :extends_primitive, :string
      add :title, :string, null: false
      add :body, :text
      add :attributes, :map, null: false, default: %{}
      add :status, :string, null: false
      add :importance, :float
      add :confidence, :float
      add :scope, :string, null: false, default: "project"
      add :scope_root_id, :integer
      add :lock_version, :integer, null: false, default: 1
      add :created_by_agent_id, :string
      add :created_by_operator, :boolean, null: false, default: false
      add :archived_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:nodes, [:project_id, :type_key])
    create index(:nodes, [:project_id, :status])
    create index(:nodes, [:project_id, :extends_primitive])
    create index(:nodes, [:scope, :scope_root_id])
    create index(:nodes, [:project_id, :importance])

    execute "CREATE INDEX nodes_attributes_gin_idx ON nodes USING GIN (attributes)",
            "DROP INDEX nodes_attributes_gin_idx"

    execute """
            ALTER TABLE nodes
            ADD COLUMN search_vector tsvector
            GENERATED ALWAYS AS (
              setweight(to_tsvector('english', coalesce(title, '')), 'A') ||
              setweight(to_tsvector('english', coalesce(body, '')), 'B')
            ) STORED
            """,
            "ALTER TABLE nodes DROP COLUMN search_vector"

    execute "CREATE INDEX nodes_search_vector_idx ON nodes USING GIN (search_vector)",
            "DROP INDEX nodes_search_vector_idx"

    create table(:node_relationships) do
      add :domain_id, references(:domains, on_delete: :restrict), null: false
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :type_key, :string, null: false
      add :extends_primitive, :string
      add :from_node_id, references(:nodes, on_delete: :delete_all), null: false
      add :to_node_id, references(:nodes, on_delete: :delete_all), null: false
      add :weight, :float, null: false, default: 1.0
      add :attributes, :map, null: false, default: %{}
      add :created_by_agent_id, :string

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:node_relationships, [:from_node_id, :to_node_id, :type_key])
    create index(:node_relationships, [:project_id])
    create index(:node_relationships, [:project_id, :type_key])
    create index(:node_relationships, [:project_id, :extends_primitive])
    create index(:node_relationships, [:from_node_id])
    create index(:node_relationships, [:to_node_id])

    create table(:node_flags) do
      add :node_id, references(:nodes, on_delete: :delete_all), null: false
      add :flag_type_key, :string, null: false
      add :severity, :string, null: false, default: "warning"
      add :detected_by_agent_id, :string
      add :detection_context, :map, null: false, default: %{}
      add :resolved_at, :utc_datetime_usec
      add :resolved_by_operator, :boolean, null: false, default: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:node_flags, [:node_id])
    create index(:node_flags, [:flag_type_key])
    create index(:node_flags, [:node_id, :resolved_at])

    create table(:schema_change_proposals) do
      add :domain_id, references(:domains, on_delete: :delete_all), null: false
      add :proposed_by_agent_id, :string
      add :proposed_by_operator, :boolean, null: false, default: false
      add :change_kind, :string, null: false
      add :payload, :map, null: false, default: %{}
      add :rationale, :text
      add :status, :string, null: false, default: "pending"
      add :reviewed_by_operator, :boolean, null: false, default: false
      add :applied_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:schema_change_proposals, [:domain_id])
    create index(:schema_change_proposals, [:status])

    create table(:node_embeddings) do
      add :node_id, references(:nodes, on_delete: :delete_all), null: false
      add :embedding_model, :string, null: false
      add :embedding, :vector, size: 768
      add :embedded_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:node_embeddings, [:node_id, :embedding_model])
    create index(:node_embeddings, [:embedding_model])
  end
end
