defmodule HydraX.Repo.Migrations.RelaxActiveBranchIdConstraint do
  use Ecto.Migration

  # The previous migration set active_branch_id NOT NULL after backfilling
  # existing rows. But new conversations are created before any branch
  # exists — the main branch is created lazily on first append_turn. Drop
  # the constraint and rely on the lazy-heal paths in
  # Conversations.list_turns/append_turn.
  def change do
    alter table(:hx_conversations) do
      modify :active_branch_id, :uuid, null: true, from: {:uuid, null: false}
    end
  end
end
