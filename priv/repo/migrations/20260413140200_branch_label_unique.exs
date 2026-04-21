defmodule HydraX.Repo.Migrations.BranchLabelUnique do
  use Ecto.Migration

  # Prevent two branches in the same conversation from sharing a label.
  # This also closes the ensure_main_branch race: a concurrent second
  # insert with label="main" will fail the unique constraint, letting the
  # caller fall through to the "already exists" branch on retry.
  def change do
    create unique_index(:hx_conversation_branches, [:conversation_id, :label])
  end
end
