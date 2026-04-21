defmodule HydraX.Repo.Migrations.AddConversationBranches do
  use Ecto.Migration

  def up do
    # 1. Branches table — one row per (conversation, branch).
    create table(:hx_conversation_branches) do
      add :conversation_id, references(:hx_conversations, on_delete: :delete_all), null: false
      add :branch_uuid, :uuid, null: false
      add :label, :string, null: false, default: "main"
      # parent_branch_id points at the branch we forked FROM (nullable for main)
      add :parent_branch_id, references(:hx_conversation_branches, on_delete: :nilify_all)
      # forked_from_sequence is the sequence in the parent branch that we
      # branched at; nil for main (which has no parent)
      add :forked_from_sequence, :integer

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:hx_conversation_branches, [:conversation_id, :branch_uuid])
    create index(:hx_conversation_branches, [:conversation_id])

    # 2. branch_id on turns. Nullable initially; backfilled below; then set
    # NOT NULL.
    alter table(:hx_turns) do
      add :branch_id, :uuid
    end

    # 3. active_branch_id on conversations. Nullable initially; backfilled
    # below; then set NOT NULL.
    alter table(:hx_conversations) do
      add :active_branch_id, :uuid
    end

    flush()

    # 4. Backfill: for every existing conversation, create a "main" branch and
    # point all of its turns at it, plus set the conversation's active branch.
    execute("""
    INSERT INTO hx_conversation_branches (conversation_id, branch_uuid, label, inserted_at)
    SELECT id, gen_random_uuid(), 'main', NOW()
    FROM hx_conversations
    WHERE id NOT IN (SELECT conversation_id FROM hx_conversation_branches)
    """)

    execute("""
    UPDATE hx_conversations c
    SET active_branch_id = b.branch_uuid
    FROM hx_conversation_branches b
    WHERE b.conversation_id = c.id
      AND c.active_branch_id IS NULL
    """)

    execute("""
    UPDATE hx_turns t
    SET branch_id = c.active_branch_id
    FROM hx_conversations c
    WHERE c.id = t.conversation_id
      AND t.branch_id IS NULL
    """)

    flush()

    # 5. Lock down: enforce NOT NULL now that everything is backfilled.
    alter table(:hx_turns) do
      modify :branch_id, :uuid, null: false
    end

    alter table(:hx_conversations) do
      modify :active_branch_id, :uuid, null: false
    end

    # 6. Replace the old (conversation_id, sequence) unique index with one
    # scoped to the branch. Sequences are now branch-local.
    drop unique_index(:hx_turns, [:conversation_id, :sequence])
    create unique_index(:hx_turns, [:conversation_id, :branch_id, :sequence])
    create index(:hx_turns, [:conversation_id, :branch_id])
  end

  def down do
    drop unique_index(:hx_turns, [:conversation_id, :branch_id, :sequence])
    drop index(:hx_turns, [:conversation_id, :branch_id])
    create unique_index(:hx_turns, [:conversation_id, :sequence])

    alter table(:hx_turns) do
      remove :branch_id
    end

    alter table(:hx_conversations) do
      remove :active_branch_id
    end

    drop table(:hx_conversation_branches)
  end
end
