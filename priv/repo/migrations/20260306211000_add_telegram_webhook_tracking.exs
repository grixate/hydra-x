defmodule HydraX.Repo.Migrations.AddTelegramWebhookTracking do
  use Ecto.Migration

  def change do
    alter table(:telegram_configs) do
      add :webhook_url, :string
      add :webhook_registered_at, :utc_datetime_usec
    end
  end
end
