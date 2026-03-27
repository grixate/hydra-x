defmodule HydraX.Repo.Migrations.CreateProductCore do
  use Ecto.Migration

  def change do
    create table(:projects) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :status, :string, null: false, default: "active"
      add :metadata, :map, null: false, default: %{}

      add :researcher_agent_id,
          references(:hx_agent_profiles, on_delete: :nilify_all),
          null: false

      add :strategist_agent_id,
          references(:hx_agent_profiles, on_delete: :nilify_all),
          null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:projects, [:slug])
    create index(:projects, [:researcher_agent_id])
    create index(:projects, [:strategist_agent_id])

    create table(:sources) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :source_type, :string, null: false
      add :content, :text
      add :external_ref, :string
      add :processing_status, :string, null: false, default: "pending"
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:sources, [:project_id])
    create index(:sources, [:processing_status])

    create table(:source_chunks) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :source_id, references(:sources, on_delete: :delete_all), null: false
      add :ordinal, :integer, null: false
      add :content, :text, null: false
      add :token_count, :integer
      add :metadata, :map, null: false, default: %{}
      add :embedding, :vector, size: 768

      timestamps(type: :utc_datetime_usec)
    end

    execute("""
    ALTER TABLE source_chunks
    ADD COLUMN search_vector tsvector
    GENERATED ALWAYS AS (
      setweight(to_tsvector('english', coalesce(content, '')), 'A')
    ) STORED
    """)

    create unique_index(:source_chunks, [:source_id, :ordinal])
    create index(:source_chunks, [:project_id])
    create index(:source_chunks, [:source_id])
    create index(:source_chunks, [:search_vector], using: :gin)

    execute(
      "CREATE INDEX source_chunks_embedding_ivfflat_idx ON source_chunks USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100)",
      "DROP INDEX source_chunks_embedding_ivfflat_idx"
    )

    create table(:insights) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :body, :text, null: false
      add :status, :string, null: false, default: "draft"
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:insights, [:project_id])
    create index(:insights, [:status])

    create table(:insight_evidence) do
      add :insight_id, references(:insights, on_delete: :delete_all), null: false
      add :source_chunk_id, references(:source_chunks, on_delete: :delete_all), null: false
      add :quote, :text
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:insight_evidence, [:insight_id, :source_chunk_id])
    create index(:insight_evidence, [:source_chunk_id])

    create table(:requirements) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :body, :text, null: false
      add :status, :string, null: false, default: "draft"
      add :grounded, :boolean, null: false, default: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:requirements, [:project_id])
    create index(:requirements, [:status])

    create table(:requirement_insights) do
      add :requirement_id, references(:requirements, on_delete: :delete_all), null: false
      add :insight_id, references(:insights, on_delete: :delete_all), null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:requirement_insights, [:requirement_id, :insight_id])
    create index(:requirement_insights, [:insight_id])

    create table(:product_conversations) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false

      add :hydra_conversation_id,
          references(:hx_conversations, on_delete: :nilify_all),
          null: false

      add :persona, :string, null: false
      add :title, :string
      add :status, :string, null: false, default: "active"
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:product_conversations, [:project_id])
    create unique_index(:product_conversations, [:hydra_conversation_id])
    create index(:product_conversations, [:persona])

    create table(:product_messages) do
      add :product_conversation_id, references(:product_conversations, on_delete: :delete_all),
        null: false

      add :hydra_turn_id, references(:hx_turns, on_delete: :nilify_all)
      add :role, :string, null: false
      add :content, :text, null: false
      add :citations, {:array, :map}, null: false, default: []
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:product_messages, [:product_conversation_id])
    create index(:product_messages, [:hydra_turn_id])
  end
end
