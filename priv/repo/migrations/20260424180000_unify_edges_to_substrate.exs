defmodule HydraX.Repo.Migrations.UnifyEdgesToSubstrate do
  @moduledoc """
  Phase 1e of the substrate cutover. Drops `product_graph_edges` and
  adds denormalized `from_node_type` / `to_node_type` columns to
  `node_relationships` so readers that want to know the endpoint
  type don't need a join.

  Per spec §12, no data preservation — existing polymorphic edges
  (insight→decision, source→insight, etc.) are dropped. Agents
  rebuild edges as they run.

  Simulation nodes still live in `product_simulations`; edges to
  them were already rare and now go unsupported. Adding simulation
  to the substrate is a separate follow-up.
  """

  use Ecto.Migration

  def up do
    drop table(:product_graph_edges)

    alter table(:node_relationships) do
      add :from_node_type, :string
      add :to_node_type, :string
    end

    create index(:node_relationships, [:project_id, :from_node_type])
    create index(:node_relationships, [:project_id, :to_node_type])
  end

  def down do
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

    drop index(:node_relationships, [:project_id, :from_node_type])
    drop index(:node_relationships, [:project_id, :to_node_type])

    alter table(:node_relationships) do
      remove :from_node_type
      remove :to_node_type
    end
  end
end
