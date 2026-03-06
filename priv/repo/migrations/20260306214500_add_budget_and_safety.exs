defmodule HydraX.Repo.Migrations.AddBudgetAndSafety do
  use Ecto.Migration

  def change do
    create table(:budget_policies) do
      add :agent_id, references(:agent_profiles, on_delete: :delete_all), null: false
      add :daily_limit, :integer, null: false, default: 20_000
      add :conversation_limit, :integer, null: false, default: 4_000
      add :soft_warning_at, :float, null: false, default: 0.8
      add :hard_limit_action, :string, null: false, default: "reject"
      add :enabled, :boolean, null: false, default: true

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:budget_policies, [:agent_id])

    create table(:budget_usages) do
      add :agent_id, references(:agent_profiles, on_delete: :delete_all), null: false
      add :conversation_id, references(:conversations, on_delete: :delete_all)
      add :scope, :string, null: false
      add :tokens_in, :integer, null: false, default: 0
      add :tokens_out, :integer, null: false, default: 0
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:budget_usages, [:agent_id, :inserted_at])
    create index(:budget_usages, [:conversation_id, :inserted_at])

    create table(:safety_events) do
      add :agent_id, references(:agent_profiles, on_delete: :delete_all), null: false
      add :conversation_id, references(:conversations, on_delete: :nilify_all)
      add :category, :string, null: false
      add :level, :string, null: false
      add :message, :text, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:safety_events, [:agent_id, :inserted_at])
    create index(:safety_events, [:conversation_id, :inserted_at])
  end
end
