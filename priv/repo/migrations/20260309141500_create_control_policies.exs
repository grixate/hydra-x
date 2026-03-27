defmodule HydraX.Repo.Migrations.CreateControlPolicies do
  use Ecto.Migration

  def change do
    create table(:hx_control_policies) do
      add :scope, :string, null: false, default: "default"
      add :require_recent_auth_for_sensitive_actions, :boolean, null: false, default: true
      add :recent_auth_window_minutes, :integer, null: false, default: 15

      add :interactive_delivery_channels_csv, :string,
        null: false,
        default: "telegram,discord,slack,webchat"

      add :job_delivery_channels_csv, :string,
        null: false,
        default: "telegram,discord,slack,webchat"

      add :ingest_roots_csv, :string, null: false, default: "ingest"
      add :agent_id, references(:hx_agent_profiles, on_delete: :delete_all)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:hx_control_policies, [:scope, :agent_id])
  end
end
