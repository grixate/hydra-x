defmodule HydraX.Repo.Migrations.AddMemoryAgentAndSearchVectors do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :memory_agent_id,
          references(:hx_agent_profiles, on_delete: :nilify_all)
    end

    create index(:projects, [:memory_agent_id])

    # Add tsvector search columns to all new node type tables
    for table_name <- [:decisions, :strategies, :design_nodes, :architecture_nodes, :tasks, :learnings] do
      execute("""
      ALTER TABLE #{table_name}
      ADD COLUMN search_vector tsvector
      GENERATED ALWAYS AS (
        setweight(to_tsvector('english', coalesce(title, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(body, '')), 'B')
      ) STORED
      """)

      create index(table_name, [:search_vector], using: :gin)
    end
  end
end
