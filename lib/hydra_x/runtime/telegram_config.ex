defmodule HydraX.Runtime.TelegramConfig do
  use Ecto.Schema
  import Ecto.Changeset

  schema "telegram_configs" do
    field :bot_token, :string
    field :bot_username, :string
    field :webhook_secret, :string
    field :enabled, :boolean, default: false

    belongs_to :default_agent, HydraX.Runtime.AgentProfile

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(config, attrs) do
    config
    |> cast(attrs, [:bot_token, :bot_username, :webhook_secret, :enabled, :default_agent_id])
    |> validate_required([:bot_token])
    |> assoc_constraint(:default_agent)
  end
end
