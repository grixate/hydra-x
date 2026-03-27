defmodule HydraX.Repo.Migrations.AddSessionControlsToWebchatConfigs do
  use Ecto.Migration

  def change do
    alter table(:hx_webchat_configs) do
      add :allow_anonymous_messages, :boolean, default: true, null: false
      add :session_max_age_minutes, :integer, default: 24 * 60, null: false
      add :session_idle_timeout_minutes, :integer, default: 120, null: false
      add :attachments_enabled, :boolean, default: true, null: false
      add :max_attachment_count, :integer, default: 3, null: false
      add :max_attachment_size_kb, :integer, default: 2_048, null: false
    end
  end
end
