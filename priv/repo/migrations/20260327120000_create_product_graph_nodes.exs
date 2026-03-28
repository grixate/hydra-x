defmodule HydraX.Repo.Migrations.CreateProductGraphNodes do
  use Ecto.Migration

  def change do
    create table(:decisions) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :body, :text, null: false
      add :status, :string, null: false, default: "active"
      add :decided_by, :string
      add :decided_at, :utc_datetime
      add :alternatives_considered, :jsonb, null: false, default: "[]"
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:decisions, [:project_id])
    create index(:decisions, [:status])

    create table(:strategies) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :body, :text, null: false
      add :status, :string, null: false, default: "active"
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:strategies, [:project_id])
    create index(:strategies, [:status])

    create table(:design_nodes) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :body, :text, null: false
      add :node_type, :string, null: false
      add :status, :string, null: false, default: "active"
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:design_nodes, [:project_id])
    create index(:design_nodes, [:status])
    create index(:design_nodes, [:node_type])

    create table(:architecture_nodes) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :body, :text, null: false
      add :node_type, :string, null: false
      add :status, :string, null: false, default: "active"
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:architecture_nodes, [:project_id])
    create index(:architecture_nodes, [:status])
    create index(:architecture_nodes, [:node_type])

    create table(:tasks) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :body, :text, null: false
      add :status, :string, null: false, default: "backlog"
      add :assignee, :string
      add :effort_estimate, :string
      add :priority, :string, null: false, default: "medium"
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:tasks, [:project_id])
    create index(:tasks, [:status])
    create index(:tasks, [:priority])

    create table(:learnings) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :body, :text, null: false
      add :learning_type, :string, null: false
      add :status, :string, null: false, default: "active"
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:learnings, [:project_id])
    create index(:learnings, [:status])
    create index(:learnings, [:learning_type])

    create table(:product_graph_edges) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :from_node_type, :string, null: false
      add :from_node_id, :integer, null: false
      add :to_node_type, :string, null: false
      add :to_node_id, :integer, null: false
      add :kind, :string, null: false
      add :weight, :float, null: false, default: 1.0
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:product_graph_edges, [
      :from_node_type,
      :from_node_id,
      :to_node_type,
      :to_node_id,
      :kind
    ])

    create index(:product_graph_edges, [:project_id])
    create index(:product_graph_edges, [:from_node_type, :from_node_id])
    create index(:product_graph_edges, [:to_node_type, :to_node_id])

    create table(:graph_flags) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :node_type, :string, null: false
      add :node_id, :integer, null: false
      add :flag_type, :string, null: false
      add :reason, :text
      add :source_agent, :string
      add :status, :string, null: false, default: "open"
      add :resolved_by, :string
      add :resolved_at, :utc_datetime

      timestamps(type: :utc_datetime_usec)
    end

    create index(:graph_flags, [:project_id])
    create index(:graph_flags, [:node_type, :node_id])
    create index(:graph_flags, [:status])
    create index(:graph_flags, [:flag_type])
  end
end
