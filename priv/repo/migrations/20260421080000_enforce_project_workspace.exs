defmodule HydraX.Repo.Migrations.EnforceProjectWorkspace do
  @moduledoc """
  Stream A2.5 — projects.workspace_id NOT-NULL constraint.

  Flow:
    1. Find any project with `workspace_id IS NULL`.
    2. Ensure there's a "default" workspace owned by a system user.
    3. Backfill `workspace_id` on every orphan project.
    4. Flip the column to NOT NULL.

  The FK from the accounts migration is `on_delete: :restrict`. Spec §7
  soft-delete with grace period is deferred; restrict is safe meanwhile.
  """

  use Ecto.Migration

  def up do
    execute("""
    DO $$
    DECLARE
      needs_backfill INTEGER;
      default_user_id UUID;
      default_workspace_id UUID;
    BEGIN
      SELECT COUNT(*) INTO needs_backfill FROM projects WHERE workspace_id IS NULL;

      IF needs_backfill > 0 THEN
        SELECT id INTO default_user_id FROM users ORDER BY inserted_at LIMIT 1;

        IF default_user_id IS NULL THEN
          INSERT INTO users (id, email, display_name, email_verified_at, inserted_at, updated_at)
          VALUES (uuid_generate_v4(), 'system@hydra.local', 'System', NOW(), NOW(), NOW())
          RETURNING id INTO default_user_id;
        END IF;

        SELECT id INTO default_workspace_id
        FROM workspaces
        WHERE created_by_user_id = default_user_id AND slug = 'default'
        LIMIT 1;

        IF default_workspace_id IS NULL THEN
          INSERT INTO workspaces (id, name, slug, created_by_user_id, inserted_at, updated_at)
          VALUES (uuid_generate_v4(), 'Default Workspace', 'default', default_user_id, NOW(), NOW())
          RETURNING id INTO default_workspace_id;

          INSERT INTO workspace_memberships (id, workspace_id, user_id, role, joined_at, inserted_at, updated_at)
          VALUES (uuid_generate_v4(), default_workspace_id, default_user_id, 'owner', NOW(), NOW(), NOW())
          ON CONFLICT (workspace_id, user_id) DO NOTHING;
        END IF;

        UPDATE projects SET workspace_id = default_workspace_id WHERE workspace_id IS NULL;
      END IF;
    END
    $$;
    """)

    alter table(:projects) do
      modify :workspace_id, :uuid, null: false
    end
  end

  def down do
    alter table(:projects) do
      modify :workspace_id, :uuid, null: true
    end
  end
end
