defmodule HydraX.Repo.Migrations.CreateBoardSchemas do
  use Ecto.Migration

  def change do
    create table(:board_sessions) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :description, :text
      add :status, :string, null: false, default: "active"
      add :created_by_user_id, :string
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:board_sessions, [:project_id])
    create index(:board_sessions, [:status])

    create table(:board_nodes) do
      add :board_session_id, references(:board_sessions, on_delete: :delete_all), null: false
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :node_type, :string, null: false
      add :title, :string, null: false
      add :body, :text, null: false
      add :status, :string, null: false, default: "draft"
      add :promoted_node_type, :string
      add :promoted_node_id, :integer
      add :created_by, :string, null: false, default: "agent"
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:board_nodes, [:board_session_id])
    create index(:board_nodes, [:project_id])
    create index(:board_nodes, [:status])
    create index(:board_nodes, [:node_type])

    create table(:board_edges) do
      add :board_session_id, references(:board_sessions, on_delete: :delete_all), null: false

      add :from_board_node_id, references(:board_nodes, on_delete: :delete_all), null: false
      add :to_board_node_id, references(:board_nodes, on_delete: :delete_all), null: false

      add :kind, :string, null: false
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:board_edges, [:board_session_id])

    create unique_index(:board_edges, [:from_board_node_id, :to_board_node_id, :kind])

    alter table(:product_conversations) do
      add :board_session_id, references(:board_sessions, on_delete: :nilify_all)
    end

    create index(:product_conversations, [:board_session_id])
  end
end
