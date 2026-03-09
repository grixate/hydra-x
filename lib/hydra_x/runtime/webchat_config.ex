defmodule HydraX.Runtime.WebchatConfig do
  use Ecto.Schema
  import Ecto.Changeset

  schema "webchat_configs" do
    field :title, :string, default: "Hydra-X Webchat"
    field :subtitle, :string, default: "A public channel into the operator runtime."
    field :welcome_prompt, :string
    field :composer_placeholder, :string, default: "Ask Hydra-X anything about this workspace..."
    field :enabled, :boolean, default: false

    belongs_to :default_agent, HydraX.Runtime.AgentProfile

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(config, attrs) do
    config
    |> cast(attrs, [
      :title,
      :subtitle,
      :welcome_prompt,
      :composer_placeholder,
      :enabled,
      :default_agent_id
    ])
    |> validate_required([:title])
    |> assoc_constraint(:default_agent)
  end
end
