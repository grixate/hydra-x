defmodule HydraX.Runtime.SlackConfig do
  use Ecto.Schema
  import Ecto.Changeset

  schema "hx_slack_configs" do
    field :bot_token, :string
    field :signing_secret, :string
    field :enabled, :boolean, default: false

    belongs_to :default_agent, HydraX.Runtime.AgentProfile

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(config, attrs) do
    config
    |> cast(attrs, [
      :bot_token,
      :signing_secret,
      :enabled,
      :default_agent_id
    ])
    |> validate_required([:bot_token])
    |> assoc_constraint(:default_agent)
  end
end
