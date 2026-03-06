defmodule HydraX.Repo.Migrations.CreateHydraXCore do
  use Ecto.Migration

  def up do
    create table(:agent_profiles) do
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

    create unique_index(:agent_profiles, [:slug])

    create table(:provider_configs) do
      add :name, :string, null: false
      add :kind, :string, null: false
      add :base_url, :string
      add :api_key, :text
      add :model, :string, null: false
      add :enabled, :boolean, null: false, default: false
      add :config, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create table(:conversations) do
      add :agent_id, references(:agent_profiles, on_delete: :delete_all), null: false
      add :channel, :string, null: false
      add :external_ref, :string
      add :status, :string, null: false, default: "active"
      add :title, :string
      add :last_message_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:conversations, [:agent_id, :channel])
    create unique_index(:conversations, [:agent_id, :channel, :external_ref])

    create table(:turns) do
      add :conversation_id, references(:conversations, on_delete: :delete_all), null: false
      add :sequence, :integer, null: false
      add :role, :string, null: false
      add :kind, :string, null: false, default: "message"
      add :content, :text, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:turns, [:conversation_id, :sequence])

    create table(:checkpoints) do
      add :conversation_id, references(:conversations, on_delete: :delete_all), null: false
      add :process_type, :string, null: false
      add :state, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:checkpoints, [:conversation_id, :process_type])

    create table(:memory_entries) do
      add :agent_id, references(:agent_profiles, on_delete: :delete_all), null: false
      add :conversation_id, references(:conversations, on_delete: :nilify_all)
      add :type, :string, null: false
      add :content, :text, null: false
      add :importance, :float, null: false, default: 0.5
      add :metadata, :map, null: false, default: %{}
      add :last_seen_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:memory_entries, [:agent_id, :type])
    create index(:memory_entries, [:conversation_id])

    create table(:memory_edges) do
      add :from_memory_id, references(:memory_entries, on_delete: :delete_all), null: false
      add :to_memory_id, references(:memory_entries, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :weight, :float, null: false, default: 1.0
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:memory_edges, [:from_memory_id])
    create index(:memory_edges, [:to_memory_id])

    execute("""
    CREATE VIRTUAL TABLE memory_search
    USING fts5(content, type, content='memory_entries', content_rowid='id');
    """)

    execute("""
    CREATE TRIGGER memory_entries_ai AFTER INSERT ON memory_entries BEGIN
      INSERT INTO memory_search(rowid, content, type)
      VALUES (new.id, new.content, new.type);
    END;
    """)

    execute("""
    CREATE TRIGGER memory_entries_ad AFTER DELETE ON memory_entries BEGIN
      INSERT INTO memory_search(memory_search, rowid, content, type)
      VALUES('delete', old.id, old.content, old.type);
    END;
    """)

    execute("""
    CREATE TRIGGER memory_entries_au AFTER UPDATE ON memory_entries BEGIN
      INSERT INTO memory_search(memory_search, rowid, content, type)
      VALUES('delete', old.id, old.content, old.type);
      INSERT INTO memory_search(rowid, content, type)
      VALUES (new.id, new.content, new.type);
    END;
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS memory_entries_au")
    execute("DROP TRIGGER IF EXISTS memory_entries_ad")
    execute("DROP TRIGGER IF EXISTS memory_entries_ai")
    execute("DROP TABLE IF EXISTS memory_search")

    drop table(:memory_edges)
    drop table(:memory_entries)
    drop table(:checkpoints)
    drop table(:turns)
    drop table(:conversations)
    drop table(:provider_configs)
    drop table(:agent_profiles)
  end
end
