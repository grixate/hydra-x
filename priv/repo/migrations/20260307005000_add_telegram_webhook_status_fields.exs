defmodule HydraX.Repo.Migrations.AddTelegramWebhookStatusFields do
  use Ecto.Migration

  def change do
    alter table(:hx_telegram_configs) do
      add :webhook_last_checked_at, :utc_datetime_usec
      add :webhook_pending_update_count, :integer, null: false, default: 0
      add :webhook_last_error, :text
    end
  end
end
