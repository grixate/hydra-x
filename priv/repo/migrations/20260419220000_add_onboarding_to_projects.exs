defmodule HydraX.Repo.Migrations.AddOnboardingToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :onboarding_state, :string, null: false, default: "pending"
      add :onboarded_at, :utc_datetime_usec
      add :onboarding_skipped_at, :utc_datetime_usec
    end

    # Existing projects are treated as already-past-onboarding. Without this,
    # everyone gets the onboarding banner on first deploy.
    execute(
      "UPDATE projects SET onboarding_state = 'completed', onboarded_at = NOW() WHERE onboarding_state = 'pending'",
      "SELECT 1"
    )

    create index(:projects, [:onboarding_state])
  end
end
