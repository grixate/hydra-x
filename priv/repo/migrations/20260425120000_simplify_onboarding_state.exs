defmodule HydraX.Repo.Migrations.SimplifyOnboardingState do
  use Ecto.Migration

  def up do
    alter table(:projects) do
      add :has_completed_first_session, :boolean, null: false, default: false
    end

    # Anything not in a fresh `pending` state is treated as past first
    # session — matches the spec semantic that the fork screen is
    # one-shot.
    execute("""
    UPDATE projects
    SET has_completed_first_session = TRUE
    WHERE onboarding_state IN ('in_progress', 'completed', 'skipped')
    """)

    drop index(:projects, [:onboarding_state])

    alter table(:projects) do
      remove :onboarding_state
      remove :onboarded_at
      remove :onboarding_skipped_at
    end
  end

  def down do
    alter table(:projects) do
      add :onboarding_state, :string, null: false, default: "pending"
      add :onboarded_at, :utc_datetime_usec
      add :onboarding_skipped_at, :utc_datetime_usec
    end

    execute("""
    UPDATE projects
    SET onboarding_state = 'completed', onboarded_at = NOW()
    WHERE has_completed_first_session = TRUE
    """)

    create index(:projects, [:onboarding_state])

    alter table(:projects) do
      remove :has_completed_first_session
    end
  end
end
