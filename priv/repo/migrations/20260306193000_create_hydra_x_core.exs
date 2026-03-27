defmodule HydraX.Repo.Migrations.CreateHydraXCore do
  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS vector", "DROP EXTENSION IF EXISTS vector")

    create table(:hx_agent_profiles) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :status, :string, null: false, default: "active"
      add :workspace_root, :string, null: false
      add :description, :text
      add :is_default, :boolean, null: false, default: false
      add :last_started_at, :utc_datetime_usec
      add :runtime_state, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:hx_agent_profiles, [:slug])

    create table(:hx_provider_configs) do
      add :name, :string, null: false
      add :kind, :string, null: false
      add :base_url, :string
      add :api_key, :text
      add :model, :string, null: false
      add :enabled, :boolean, null: false, default: false
      add :config, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create table(:hx_conversations) do
      add :agent_id, references(:hx_agent_profiles, on_delete: :delete_all), null: false
      add :channel, :string, null: false
      add :external_ref, :string
      add :status, :string, null: false, default: "active"
      add :title, :string
      add :last_message_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:hx_conversations, [:agent_id, :channel])
    create unique_index(:hx_conversations, [:agent_id, :channel, :external_ref])

    create table(:hx_turns) do
      add :conversation_id, references(:hx_conversations, on_delete: :delete_all), null: false
      add :sequence, :integer, null: false
      add :role, :string, null: false
      add :kind, :string, null: false, default: "message"
      add :content, :text, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:hx_turns, [:conversation_id, :sequence])

    create table(:hx_checkpoints) do
      add :conversation_id, references(:hx_conversations, on_delete: :delete_all), null: false
      add :process_type, :string, null: false
      add :state, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:hx_checkpoints, [:conversation_id, :process_type])

    create table(:hx_memory_entries) do
      add :agent_id, references(:hx_agent_profiles, on_delete: :delete_all), null: false
      add :conversation_id, references(:hx_conversations, on_delete: :nilify_all)
      add :type, :string, null: false
      add :content, :text, null: false
      add :importance, :float, null: false, default: 0.5
      add :embedding, :vector, size: 768
      add :metadata, :map, null: false, default: %{}
      add :last_seen_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    execute("""
    ALTER TABLE hx_memory_entries
    ADD COLUMN search_vector tsvector
    GENERATED ALWAYS AS (
      setweight(to_tsvector('english', coalesce(content, '')), 'A') ||
      setweight(to_tsvector('english', coalesce(type, '')), 'B')
    ) STORED
    """)

    create index(:hx_memory_entries, [:agent_id, :type])
    create index(:hx_memory_entries, [:conversation_id])

    execute(
      "CREATE INDEX hx_memory_entries_search_vector_idx ON hx_memory_entries USING GIN (search_vector)"
    )

    execute(
      "CREATE INDEX hx_memory_entries_embedding_idx ON hx_memory_entries USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100)"
    )

    create table(:hx_memory_edges) do
      add :from_memory_id, references(:hx_memory_entries, on_delete: :delete_all), null: false
      add :to_memory_id, references(:hx_memory_entries, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :weight, :float, null: false, default: 1.0
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:hx_memory_edges, [:from_memory_id])
    create index(:hx_memory_edges, [:to_memory_id])
  end

  def down do
    execute("DROP INDEX IF EXISTS hx_memory_entries_embedding_idx")
    execute("DROP INDEX IF EXISTS hx_memory_entries_search_vector_idx")

    drop table(:hx_memory_edges)
    drop table(:hx_memory_entries)
    drop table(:hx_checkpoints)
    drop table(:hx_turns)
    drop table(:hx_conversations)
    drop table(:hx_provider_configs)
    drop table(:hx_agent_profiles)

    execute("DROP EXTENSION IF EXISTS vector")
  end
end
