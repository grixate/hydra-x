defmodule HydraX.Repo.Migrations.AddApprovalRecords do
  use Ecto.Migration

  def change do
    create table(:approval_records) do
      add :subject_type, :string, null: false
      add :subject_id, :integer, null: false
      add :requested_action, :string, null: false
      add :decision, :string, null: false
      add :rationale, :text
      add :promoted_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}
      add :work_item_id, references(:work_items, on_delete: :nilify_all)
      add :reviewer_agent_id, references(:agent_profiles, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:approval_records, [:subject_type, :subject_id])
    create index(:approval_records, [:work_item_id])
    create index(:approval_records, [:reviewer_agent_id])
    create index(:approval_records, [:decision])
  end
end
